# Sessions — bidirectional, role-aware traffic

The `flows` table is append-only and granular: every NetFlow record
the daemon ingests becomes one row. That is the right shape for
forensic drill-down but the wrong shape for an analyst asking
*"what conversations happened?"*. obserae folds raw flows into
bidirectional, role-aware **sessions** that match how a SOC
operator thinks about traffic.

One TCP connection (say, a 30-minute SSH session) produces
**one** session row, regardless of how many flow records the
exporter sent for it.

---

## What a session represents

```
flows (append-only, one row per NetFlow record)
   ▲
   │  each flow streams through the pipeline once. As it passes,
   │  the sessionizer folds a copy into per-session state held in
   │  memory — no re-reading the flows table. Every ~10s it closes
   │  finished sessions and writes the changes to:
   ▼
sessions  (mutable while state ∈ {active, half_open}, immutable once closed)
```

The sessionizer is an **in-memory stage** in the ingestion
pipeline: folding a flow into its session is a quick in-RAM update,
so the work per flow stays the same whether the database holds a
thousand flows or a billion.

A session is the consolidation of all flows sharing the same
**canonical key**:

```
(sampler_address, min/max(ip), min/max(port), protocol)
```

Direction-independent — opposite halves of the same TCP/UDP
exchange fold into the same row. Counters are split per direction:
`ab_bytes` / `ba_bytes`, `ab_pkts` / `ba_pkts`, etc.

> **Why `sampler_address` is part of the key.** If two exporters
> see the same physical conversation (redundancy, asymmetric
> routing), each gets its own session row. Merging them would
> double-count packets and bytes. To get a sampler-agnostic view,
> `GROUP BY ip_a, port_a, ip_b, port_b, protocol` at query time.

---

## Lifecycle

```
            (1st flow)                                 (FIN/RST/idle/no_reply)
   (∅) ─────────────────►  active   ────────────────►  closed
                              ▲ │
                              │ │ per flow:
                              │ │   accumulate counters
                              │ │   advance last_activity_at
                              │ │
                              │ └── (TCP only) initial SYN-only flow
                              │     opens half_open; promoted to
                              │     active when the opposite direction
                              │     replies (firewall didn't drop)
                              │
                       packet seen on the other direction
```

### States

| `state`     | Meaning                                                                                              |
|-------------|-------------------------------------------------------------------------------------------------------|
| `active`    | Bidirectional or single-side traffic. Idle window is `tcp_established` (or UDP/ICMP/other).          |
| `half_open` | TCP only. Initial SYN observed in one direction, no reply yet. Idle window is `tcp_half_open` (5s default) so scans surface fast. |
| `closed`    | Terminal. Counters and inferred role are frozen — the row is **never** mutated by the engine again.  |

### Close reasons

| `close_reason`   | Trigger                                                       |
|------------------|----------------------------------------------------------------|
| `tcp_rst`        | RST flag observed in either direction (TCP only)              |
| `tcp_fin`        | FIN flag observed in **both** directions (TCP only)           |
| `no_reply`       | `half_open` aged past `tcp_half_open`                         |
| `idle_timeout`   | `active` aged past the protocol's idle window                 |
| `capacity`       | The in-memory open-session map hit its cap; the oldest sessions were force-closed to keep memory bounded (see [Memory and pressure](#memory-and-pressure)) |
| `shutdown`       | Daemon stopped while the session was open *(reserved)*        |

`close_reason` is `NULL` while the session is still open.

---

## Visibility

A session becomes "operationally visible" when its `visible_since`
timestamp is ≤ now. Two paths set it:

1. **On insert**, `visible_since = opened_at + hard_timeout`
   (default 15 min). Long-running sessions surface after the
   threshold without being fragmented into multiple rows.
2. **On close**, `visible_since = min(visible_since, closed_at)`.
   A short session that RST-closes 2 s after opening is visible
   2 s after opening.

This resolves the tension between "show me what's happening
**right now**" and "give me **one row** per logical conversation
even if it lasts an hour".

---

## Role inference (client / server)

Every **closed** session carries a `(server_ip, server_port,
role_method, role_conf)` tuple. The cascade is evaluated at close
time, top-down, until one method succeeds:

| #  | Method               | Confidence | Fires when…                                                                          |
|----|----------------------|-----------|---------------------------------------------------------------------------------------|
| 1  | `tcp_handshake`      | HIGH      | TCP. Two narrow sub-cases (see below): complete bidirectional handshake, or isolated client SYN with no peer activity. |
| 2  | `cartography`        | HIGH      | One endpoint declares a service for `(port, proto)` in the cartography.              |
| 3  | `privileged_port`    | MEDIUM    | One side ≤ 1023 and the other in `[32768, 65535]`.                                  |
| 4  | `iana_port`          | MEDIUM    | One side matches a known IANA service (HTTP, SSH, …) on the right protocol.         |
| 5  | `volume_asymmetry`   | LOW       | Both directions exchanged data and one moved ≥ 4× the other (download-dominant).    |
| 6  | `lowest_port`        | LOW       | Always applies. Server is the side with the lower port.                              |

`role_conf` is the lever for downstream consumers. A SOC alert
that triggers on `role_conf = 'HIGH'` is far more reliable than
one that fires on `LOW`, by design.

> **About `tcp_handshake`.** NetFlow exporters aggregate TCP
> flags with OR across the flow window, so an OR-aggregated
> half-flow tells us almost nothing about which packet carried
> which flag. The client side of a normal HTTPS session
> accumulates `SYN|ACK|PSH|FIN|RST` in a single direction —
> exactly the same signature as a server's reply. The handshake
> step therefore only fires on the two patterns that survive OR
> aggregation as unambiguous proof of the listener:
>
> - **Bidirectional clean handshake** — one side has the client
>   SYN alone (`SYN && !ACK`), the other has `SYN+ACK`. The
>   `SYN+ACK` side is the server.
> - **Isolated client SYN, no reply at all** — one side has the
>   client SYN, the other side has zero packets and zero flags.
>   The empty side is the listener that never answered (scan or
>   connect-without-reply).
>
> Every other signature is ambiguous and the step abstains. In
> particular, **one-way captures** (exporter that only ships the
> client→server *or* the server→client direction of an outbound
> conversation) fall through to `cartography` / `privileged_port`
> / `iana_port` / `lowest_port`. For a typical one-way HTTPS
> capture (`443` vs an ephemeral port) the port-based methods
> correctly designate `443` at MEDIUM confidence, which is what
> the evidence actually warrants — the flag pattern alone never
> proved the role.

---

## What you see in the GUI

The **Sessions** page (see [web-gui.md](web-gui.md#sessions))
shows the sessions table with filters across the top: time window,
state, source/destination chips, port/protocol, and an "unmatched
only" toggle that surfaces closed sessions not caught by any rule.

Click any row for a drawer with the full detail: per-direction
counters, role inference, the raw flows that contributed, and any
matched rules.

---

## Querying sessions in NFQL

`FROM sessions` exposes every column listed in
[nfql.md](nfql.md#most-used-columns). The virtual `ip` and `port`
columns expand to `ip_a OR ip_b` / `port_a OR port_b`. Cartography
references work as on `flows`.

```nfql
# Currently active sessions to the database tier
FROM sessions
  | WHERE state == "active" AND ip == "databases" AND port == 5432
  | KEEP ip_a, ip_b, ab_pkts, ba_pkts, opened_at
  | SORT opened_at DESC

# Today's closed sessions where role inference was confident
FROM sessions
  | LAST 86400
  | WHERE state == "closed" AND role_conf == "HIGH"
  | KEEP server_ip, server_port, role_method, ab_bytes, ba_bytes
  | SORT ab_bytes DESC
  | LIMIT 50

# Scan candidates (TCP half-open closures)
FROM sessions
  | WHERE close_reason == "no_reply" AND protocol == TCP
  | KEEP ip_a, ip_b, port_b, opened_at
  | SORT opened_at DESC

# Late-arrival audit
FROM sessions_dead_letter
  | LAST 3600
  | WHERE reason == "late_arrival"
  | KEEP ip_a, ip_b, port_b, flow_end, dropped_at, related_session_id
```

---

## Tuning

Defaults are sensible. Tune via the `sessions:` block of the YAML
(see [configuration.md](configuration.md)):

```yaml
sessions:
  interval: 10s             # close + flush cadence
  grace: 30s                # hold back recent flows (correctness vs latency)
  hard_timeout: 15m         # visibility threshold for long-running sessions
  max_open_ksessions: 500   # cap on concurrent open sessions (×1000)
  recovery_window: 10m      # how far back to replay flows after a restart
  idle:
    tcp_established: 60s
    tcp_half_open: 5s       # short on purpose: scans surface fast
    udp: 30s
    icmp: 10s
    other: 60s
```

| Knob              | Effect                                                                                          |
|-------------------|--------------------------------------------------------------------------------------------------|
| `interval`        | Smaller → lower closure latency, higher CPU.                                                    |
| `grace`           | Smaller → lower visibility delay, more late-arrival rejections.                                 |
| `hard_timeout`    | Smaller → long sessions surface earlier; more in-flight rows visible.                           |
| `max_open_ksessions` | The ceiling on how many sessions can be open at once before the oldest get force-closed. Raise it if you legitimately have many concurrent conversations; a flood of `capacity` closures means it is too low (or you are being scanned). |
| `recovery_window` | After a restart, how far back the engine replays flows to rebuild its in-memory state. |
| `idle.tcp_*`      | Tune to match your environment's keepalive cadence. Most stacks: 60–90 s keepalives.            |
| `idle.tcp_half_open` | Lower bound is what you can reliably detect — 2 s aggressive, 5 s safe.                       |

---

## Late-arriving flows

NetFlow records sometimes arrive minutes after the underlying
traffic happened. The engine guards against two failure modes:

- **Recent-but-delayed arrivals** — a flow whose `time_received`
  is younger than `now - grace` is held back in an ordered
  in-memory buffer and folded only once it matures. This gives a
  flow's late siblings time to arrive first.
- **Truly late arrivals** — a flow whose `time_flow_end` pre-dates
  the `closed_at` of an existing closed session with the same
  canonical key is rejected. Closed sessions are immutable, so the
  flow is recorded in `sessions_dead_letter` with
  `reason = 'late_arrival'`. An analyst can find it with the NFQL
  query above.

A spike of late-arrival entries usually signals exporter clock
drift or a too-short `sessions.grace`.

---

## Memory and pressure

Open sessions now live in memory, not on disk, so obserae caps how
many it will hold at once: `sessions.max_open_ksessions` (in
thousands; default 500 = 500 000). When the cap is reached, the
least-recently-active sessions are force-closed with
`close_reason = 'capacity'` and the new one takes their slot — a
graceful, bounded fallback instead of unbounded memory growth.

A burst of `capacity` closures means one of two things: a scan or
SYN flood is opening huge numbers of short-lived sessions, or the
cap is simply too small for your normal traffic. The cockpit
surfaces this in real time:

- an **Open sessions** fill gauge — open count vs cap, green /
  amber / red as the map fills (a count, not bytes),
- a **CRITICAL banner** when the map is ≥ 90% full ("Capacité
  sessions atteinte … les sessions les plus anciennes sont fermées
  prématurément"),
- a **pressure badge in the topbar** so the warning is visible from
  any page, not just the cockpit.

See [web-gui.md](web-gui.md#cockpit) for the visual indicators and
[operations.md](operations.md#monitoring) for the `obserae-cli
status` gauges.

If obserae restarts, it reloads the sessions that were open at the
last flush and replays recent flows (bounded by
`sessions.recovery_window`) so long-running sessions are not
truncated. Flows that were in flight but not yet stored at the
moment of a crash are lost — the same small window the raw-flow
buffer loses.

---

## Multi-source correlation

A session is **per exporter**. When a switch and a firewall both see
the same conversation, you get two sessions — by design, so their
byte/packet counters are never double-counted. At close, obserae
groups them into one **conversation** with a shared `correlation_id`
(table `sessions_correlation`), matching on the *flow clock* — when the
conversation actually happened — not record reception time, because two
exporters flush the same conversation's NetFlow record tens of seconds
apart.

The `sessions_consolidated` table exposes one row per conversation,
**client/server oriented**: `client_ip`/`client_port`,
`server_ip`/`server_port`, and `min`/`max` directional volumes
(`client_to_server_*` for the request, `server_to_client_*` for the
response) across exporters (never summed, so no double-counting) plus a
`coherence_pct` (how much the exporters agree on the packet total).
`sampler_count > 1` isolates the genuine multi-source consolidations.
Toggle and tune via the `correlation` config block.

Correlation only matches a freshly-closed session against peers closed
**recently** — within `correlation.horizon` (default 16m), the window
that bounds how long two exporters can flush the same conversation
apart. That recency floor is what keeps correlation fast no matter how
many sessions the table has accumulated. If you run exporters whose
export timers are *very* far apart and see one conversation split into
several `correlation_id`s, raise `correlation.horizon`.

---

## Where to next

- [rules.md](rules.md) — the detection rules that consume closed
  sessions.
- [nfql.md](nfql.md) — query sessions interactively.
- [web-gui.md](web-gui.md#sessions) — the visual session browser.

# Web GUI

obserae ships with a web interface bound to `http://localhost:8080`
by default. This page tours every screen so you know what you're
looking at.

> **Security reminder.** The GUI has no built-in authentication. The
> default `127.0.0.1:8080` bind keeps it on the loopback. To expose
> it on the network, put a reverse proxy with TLS and auth in front
> (see [configuration.md](configuration.md#expose-the-web-gui-on-the-network)).

---

## Navigation

```
┌──────────────────────────────────────────────────────────────────────┐
│  obserae   [● daemon up]  [⚡ flows/s]              [Ctrl+K palette] │  topbar
├────────────┬─────────────────────────────────────────────────────────┤
│ ▣ Cockpit  │                                                         │
│ ✦ Carto    │                                                         │
│ ▦ Flow Mtx │                  Page content                           │
│ ≈ Simul.   │                                                         │
│ ◫ Sessions │                                                         │
│ ✶ Query    │                                                         │
│ ◆ Rules    │                                                         │
│ ◬ Detection│                                                         │
│ ⇅ Sources  │                                                         │
│ ⧗ Lifecycle│                                                         │
└────────────┴─────────────────────────────────────────────────────────┘
```

Click any item in the sidebar to switch page.

The **topbar** is always visible. It shows a live indicator for the
daemon (green = up, red = unreachable) and the current ingest rate
(flows per second), pushed in real time over a WebSocket. When the
in-memory session map comes under pressure, a **pressure badge**
appears here too (amber, then red) — so a "too many open sessions"
condition is visible from any page, not just the cockpit.

The **command palette** (`Ctrl+K`) jumps to any page or searches
across cartography entities and rules.

---

## Cockpit

The landing page. Designed so an analyst opening obserae in the
morning knows within 5 seconds whether anything is wrong.

Four zones:

1. **Health strip** — five live counters: flows/s, active sessions,
   half-open sessions, closed sessions, total NetFlow records since
   daemon start.
2. **NetFlow timeline** — line chart of records received over the
   last 5 minutes. Pulses every 2 seconds.
3. **Top rules (1h)** — the detection rules that fired the most in
   the last hour, with counts.
4. **Coverage & alerts** — the headline operational metric: what
   fraction of closed sessions matched at least one rule in the
   last hour. A low number means your rule set isn't covering
   reality; an analyst should investigate the unmatched sessions.
5. **Fill gauges** — two bars showing how full obserae's in-memory
   working sets are. They are **counts against a cap** (open
   sessions, cached IPs), not a byte figure — but since the cap is
   what bounds memory, a near-full bar is the memory-pressure
   signal. Colour-coded green (< 70%), amber (70–90%), red (≥ 90%):
   - **Open sessions** — how full the in-memory open-session map is
     versus its `sessions.max_open_ksessions` cap. At ≥ 90% an
     explicit **CRITICAL banner** appears ("Capacité sessions
     atteinte … les sessions les plus anciennes sont fermées
     prématurément. Réseau anormalement bavard ou scan en cours ?")
     because at that point obserae is force-closing the oldest
     sessions to stay within memory — see
     [sessions.md](sessions.md#memory-and-pressure).
   - **Enrichment LRU** — how full the insert-time enrichment
     resolver's cache is. A full cache only costs re-resolutions,
     not correctness.

The Cockpit is the right place to start every shift.

---

## Cartography

Interactive graph of *your* network. Each node is a host, network,
group or service; edges show traffic seen on each link.

```
       ┌─────────┐        ┌─────────┐
       │ webserver├──────→│ database│
       └─────────┘  443    └─────────┘
            ▲                  ▲
            │ 80,443           │ 5432
       ┌────┴────┐        ┌────┴────┐
       │ internet│        │  admin  │
       └─────────┘        └─────────┘
```

What you can do on this page:

- **Click a host or group** to open a side drawer with its detail:
  interfaces, services, current session activity, recent matches.
- **A hexagon labelled `DHCP · N`** is tethered to every network
  that has a DHCP range — N counts the distinct in-range IPs seen
  over the last 24h. Click the hexagon to open a dedicated drawer
  with the pool bounds and the live leases (see
  [cartography.md](cartography.md#dhcp-networks)).
- **Orphan IPs drawer** (toolbar button) lists every IP seen in
  traffic but not yet declared as an interface. A small switch in
  the drawer header — **All IPs** / **Declared only** — hides the
  rows tagged `outside known CIDRs` so you can focus on candidates
  already covered by one of your networks. The switch state is
  session-only (does not survive a tab reload).
- **Right-click a node** for the create / rename / delete actions.
- **Box-select** several nodes to group them in one click.
- **Wheel to zoom**, drag the canvas to pan.
- **Layout reset** snaps the graph back to its automatic layout.

The graph is **live**: when sessions close on a link, the edge
pulses. Inactive hosts (no session activity in the last 24h by
default — see `web.carto_inactivity_threshold`) are greyed out so
you can spot dead hardware at a glance.

Right-click anywhere on the empty canvas to create a new network,
host or group from scratch.

### Bulk import / export

The cartography you build in the GUI is the same YAML file you
import from the CLI. To export the current state as YAML, head to
**Data** (see below). To bulk-import, drop a YAML file there.

---

## Sessions

Tabular view of every session the engine knows about, with strong
filters.

```
opened_at  ip_a:port_a    ↔ ip_b:port_b    state    role     bytes_ab/ba   close_reason
10:42:18   10.0.0.10:443  ↔ 73.x.x.x:60123 closed   server   1.4 MB / 89 KB  tcp_fin
10:42:17   192.168.1.50:5432 ↔ 10.0.0.10:51200 closed   server   12 KB / 412 KB  idle_timeout
…
```

Filters across the top:

- **Time window** — last 5m / 15m / 1h / 6h / 24h / 7d, or an
  explicit range.
- **State** — active, half-open, closed.
- **Source / destination** — chip pickers populated from your
  cartography. Accept hosts, groups, networks, and the
  family-specific reserved keywords `any4` / `any6` and
  `internet4` / `internet6`.
- **Port / protocol** — narrow by destination port and L4 protocol.
- **Unmatched only** — show only closed sessions that *no rule*
  caught. This is the canonical "what's anomalous?" filter.

An IPv6 endpoint with a port renders in RFC 3986 bracket notation —
`[2001:db8::1]:443` — so the port stays unambiguous.

Each row in the table is **click-throughable** — a drawer slides
in with the session's full detail (counters per direction, role
inference, raw flows that contributed, matched rules).

The session model is described in [sessions.md](sessions.md).

---

## Query (Investigation)

The home of NFQL — the query language. Use this page when you need
to ask arbitrary questions of the data.

```
┌──────────────────────────────────────────────────────────────┐
│  FROM sessions                                               │
│    | LAST 3600                                               │
│    | WHERE ip == "production"                                │
│    | KEEP ip_a, ip_b, ab_bytes                               │
│    | SORT ab_bytes DESC                                      │
│    | LIMIT 50                                                │
│                                                              │
│  [Run]      ⌚ took 47 ms · 23 rows                           │
└──────────────────────────────────────────────────────────────┘
```

- **Syntax-highlighted editor** with line numbers (CodeMirror).
- **Run** (or `Ctrl+Enter`) executes the query and shows results
  in a sortable table below.
- **Errors** are inlined under the offending token, with the
  same `line:column` positions as the CLI.
- **Saved queries** in the side panel — name a query, recall it
  later.
- **Export** — buttons at the top of the results pane export the
  current rows as CSV or JSON.

The full language reference is in [nfql.md](nfql.md). The example
queries from that doc all run unmodified on this page.

---

## Flow Matrix

The full lifecycle of a connectivity **detection rule** from one screen
(in the sidebar this page is labelled **Flow Matrix**). These rules
describe which hosts *may* talk to which — a different feature from the
NFQL **Rules** (alerting) page below.

```
NAME                          TAGS                 ENABLED  EXPANSIONS  MATCHES (24h)  LAST_ERROR
webserver-to-database         critical             yes              4              891
public-https  ⊂ 1             edge external        yes            206         12,453
backends-to-redis             datastore            no              24              0
…
```

What you can do:

- **Create / edit a rule** — a form with **Name** and
  **Description** in full width at the top, then two side-by-side
  blocks: **SOURCE** (left) and **DESTINATION** (right). Each block
  has an entity picker (host / group / network), a **port/service**
  field, and an interface picker. The source port/service defaults
  to `*` (any port). The entity autocomplete also offers the
  family-specific reserved keywords `any4` / `any6` and `internet4`
  / `internet6`, plus the DHCP projections
  `network:NAME.dhcp` / `network:NAME.static` for any network that
  has a DHCP range — type a dot (`office.`) or the keyword `dhcp` /
  `static` to reveal them; bare-name lookups stay uncluttered. The
  port/service field carries the protocol (`*/TCP`, `53/UDP`, or a
  catalogued service name like `https`) — there is no separate
  protocol dropdown. A live preview shows how many expansions the
  rule will compile to.
- **Tag a rule** — a chips picker at the bottom of the form.
  Type a tag and press **Enter**, **comma** or **click outside**
  to commit it as a chip; **×** on a chip removes it;
  **Backspace** on an empty input removes the last chip. Each tag
  gets a stable colour (hashed from its name), so the same tag
  looks identical across the form, the table row, and the drawer.
- **Search with operators** — the search box understands
  `tag:critical`, `proto:tcp`, `port:443`, `host:srv-web`,
  `group:lan`, `network:dmz` and `service:ssh`. Multiple terms
  are AND-ed (`tag:edge port:22`). A plain word like `https`
  matches across name, description, src/dst, services, tags and
  any host the rule transitively touches via groups/networks. See
  [rules.md#searching-rules](rules.md#searching-rules) for the
  full grammar.
- **Spot redundant rules** — when one rule fully covers another
  (e.g. `group:lan → internet4:443` and `host:web → internet4:443`),
  the narrower one gets a small `⊂ N` badge after its name meaning
  "covered by N rules". Open its drawer for the dedicated
  **Relations** section, which lists each parent (`subset` /
  `equal`) and each child the rule covers (`overlap` too). When
  the rule is strictly covered by another **enabled** rule, a
  *"Disable this redundant rule"* button appears — clicking it
  toggles `enabled=false`, it never deletes.
- **Enable / disable** — toggle the row's switch. Disabled rules
  cost zero CPU per tick.
- **Click a rule** to see its compiled expansions plus a chart of
  matches over the last 24h.
- **Validate before import** — drop a `rules.yml` and the page
  shows what would change before you commit.

A rule with a non-empty `LAST_ERROR` is *quarantined*: it lives
in the database but the matcher skips it. Typical cause: a
cartography mutation removed an entity the rule referenced. Fix
the cartography (or the rule) and re-import to clear the error.

The rule model is described in [rules.md](rules.md).

---

## Rules (alerting)

NFQL-based alert rules. Each rule runs a **saved NFQL query** (authored
on the Query page) on its own schedule and raises an alert when a
condition is met. The list mirrors the Flow Matrix — click a row to open
its panel.

```
NAME              QUERY              CONDITION   SEVERITY  CADENCE  LAST EXEC   STATUS
ssh-from-internet ssh-watch          presence    high      30s      83 ms       enabled
scan-detector     distinct-dst-ports threshold>100 medium  1m       412 ms ⚠    enabled
new-external-asn  egress-asn         first_seen  low       5m       21 ms       enabled
log-collector-up  collector-flows    heartbeat   critical  1m       12 ms       enabled
```

What you can do:

- **Create / edit a rule**: find a saved query with the **searchable
  picker** (type a word, or `name:` / `tag:` to target a field), then
  set a **condition** (presence / threshold / first seen / heartbeat), a
  **severity**, a **cadence** (10 s … 1 h) and a **cooldown**, and an
  optional remediation note.
- **Sort by Last exec** to find slow ("heavy") rules — the column is
  colour-coded and a slow run is flagged.
- Open a rule's panel to see its **recent runs** (when each ran, whether
  it fired, row count, duration, and a sample of the result).

The full model is described in [alerting.md](alerting.md).

---

## Detection

The dashboard of alerts your rules raised. New alerts appear live.

```
FIRED                SEVERITY  RULE               MATCHED  STATUS
2026-05-31 09:14:02  high      ssh-from-internet  3        new
2026-05-31 09:02:41  medium    scan-detector      128      ack
2026-05-30 23:51:10  critical  log-collector-up   0        closed
```

What you can do:

- **Filter** by severity, status, rule, or time window.
- **Advance status**: new → acknowledged → closed.
- **Delete** alerts (single or in bulk).
- Open an alert to see the **rows that matched** and jump to its rule.

See [alerting.md](alerting.md) for the workflow end to end.

---

## Sources

Everything that *produces data* for obserae lives here: the NetFlow
exporters (the devices that emit flows), the cloud-provider
attribution sources, and the threat-intelligence feeds. Three tabs.
See [sources.md](sources.md) for the full walkthrough.

### Exporters tab

A table with one row per NetFlow-emitting device the daemon has
seen. The IP is the `sampler_address` carried on every flow; the
**name**, **equipment type** and **details** columns are yours to
fill in — once labelled, the rest of the GUI (Sessions, Cartography,
Investigation) shows the friendly name instead of the raw IP.

The list auto-refreshes from observed traffic every 5 minutes; a
**Rescan** button forces a sweep on demand if you just added a new
device.

### Cloud attribution tab

The master toggle for IP enrichment plus the list of cloud-provider
sources (AWS, Azure, Google). When on, every IP gets a discreet
cloud-provider badge across the GUI.

### Threat intelligence tab

Same controls for open-source TI feeds (FireHOL …). Hits surface as
a red triangle on Sessions and Cartography.

The full enrichment mechanism is described in
[enrichment.md](enrichment.md).

---

## Lifecycle

Everything that *manages data over time*: retention, backup,
storage footprint, and the manual import / export controls. Four
tabs. See [lifecycle.md](lifecycle.md) for the full walkthrough.

### Storage tab

The on-disk footprint: DuckDB file size, free disk space on the
mount, byte totals for the parquet buffer and backup directories.
Polled every 10 seconds — these values move slowly. Use this tab
to size the retention policy below, or to confirm the backup
directory isn't ballooning past its rotation cap.

### Retention tab

Periodic purge of stale rows from `flows` and `sessions`. **Off by
default** — flip the master switch only after you have picked at
least one max age. Changes take effect on the next sweep; no
restart needed.

### Backup tab

Periodic gzipped JSON dump of the `flows` table. Files are named
`flows-YYYYMMDDTHHMMSS.json.gz` and land under the configured
directory. Rotation enforces the two limits you set (max age and/or
max files). A **Backup now** button writes one snapshot
immediately; the file listing below refreshes as soon as it lands.

The exact format is identical to what the import below accepts —
so a backup file round-trips cleanly into a fresh daemon for
forensic replay.

### Flow I/O tab

Manual export and import of the `flows` table as a hand-editable
JSON array. The import accepts both `.json` and `.json.gz` (gzip
detection is automatic). The **time mode** radio controls whether
timestamps are kept absolute or shifted so the newest record lands
at "now" — useful for replaying a fixture captured days ago.

---

## Simulation

A built-in NetFlow simulator. Generates synthetic traffic against
your cartography so you can develop detection rules without waiting
for real exporters, or rehearse an incident with a known scenario.

What you configure:

- A **traffic profile** — pick one of the built-in profiles
  (homelab, multi-tier app, scan storm) or build a custom one.
- A **rate** — flows per second to inject.
- A **duration** — `1m`, `5m`, `1h`, or run indefinitely.

Simulated flows enter the **same pipeline** as real exporters —
they are sessionized, enriched, matched against rules, and shown on
the cartography, exactly like real NetFlow. They produce genuine
**sessions**, not just raw flow rows. The only difference is the
`sampler_address` (a fixed loopback IP) so you can distinguish them
at query time:

```nfql
FROM flows | WHERE sampler_address == "127.0.0.1"
```

Stop the simulator and the live traffic resumes as before.

---

## Keyboard shortcuts

| Shortcut         | Action                                                |
|------------------|-------------------------------------------------------|
| `Ctrl+K`         | Open the command palette (jump to page or entity)     |
| `Ctrl+Enter`     | Run the query (Investigation page)                    |
| `Esc`            | Close any open drawer or modal                        |
| `g c`            | Go to Cartography                                     |
| `g s`            | Go to Sessions                                        |
| `g q`            | Go to Query                                           |
| `g r`            | Go to Rules                                           |

---

## Where to next

- [nfql.md](nfql.md) — get fluent in the query language.
- [cartography.md](cartography.md) — model your real infrastructure.
- [rules.md](rules.md) — write rules that catch what matters.

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
│ ◫ Sessions │                  Page content                           │
│ ✶ Query    │                                                         │
│ ⚑ Rules    │                                                         │
│ ⚙ Data     │                                                         │
│ ⚒ Simul.   │                                                         │
└────────────┴─────────────────────────────────────────────────────────┘
```

Click any item in the sidebar to switch page.

The **topbar** is always visible. It shows a live indicator for the
daemon (green = up, red = unreachable) and the current ingest rate
(flows per second), pushed in real time over a WebSocket.

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
  cartography. Accept hosts, groups, networks, and the reserved
  keywords `any` and `internet`.
- **Port / protocol** — narrow by destination port and L4 protocol.
- **Unmatched only** — show only closed sessions that *no rule*
  caught. This is the canonical "what's anomalous?" filter.

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

## Rules

The full lifecycle of a detection rule from one screen.

```
NAME                       ENABLED  EXPANSIONS  MATCHES (24h)  LAST_ERROR
webserver-to-database      yes              4              891
public-https               yes            206         12,453
backends-to-redis          no              24              0
…
```

What you can do:

- **Create / edit a rule** — a form with searchable chip pickers
  for `src` and `dst`, dropdowns for protocol, and a live preview
  of how many expansions the rule will compile to.
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

## Data

Bulk import / export plus IP enrichment.

### Import / export

- **Export topology** → downloads a YAML you can edit and re-import.
- **Export rules** → same, for detection rules.
- **Import topology / rules** → drag-and-drop a YAML file. Validation
  runs first; the GUI shows what would change before you confirm.

### IP enrichment

Tag the IPs you see with cloud-provider metadata so a session to
`52.x.x.x` shows up as "AWS / us-east-1" instead of an opaque IP.

The page lists every source (AWS, Azure, Google) with:

- An **enable/disable toggle** per source.
- The **last refresh time** and current range count.
- A **Refresh now** button — useful right after you enable a source.

When enrichment is on, IPs across the GUI render with a small badge
that hovers to show the provider details. The full mechanism is
described in [enrichment.md](enrichment.md).

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

Simulated flows enter the same pipeline as real exporters — they
are written to DuckDB, sessionized, matched against rules. The only
difference is the `sampler_address` (a fixed loopback IP) so you
can distinguish them at query time:

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

# Web GUI

obserae ships with a web interface bound to `http://localhost:8080`
by default. This page tours every screen so you know what you're
looking at.

> **Sign in required.** The GUI asks every visitor to log in. On the
> very first start obserae creates an `admin` account and prints its
> generated password **once** in the daemon log — look for a `WARN`
> line `generated admin password (first boot)`. Sign in with it, then
> change it (topbar user menu, or `obserae-cli user reset-admin-password`).
> The default `127.0.0.1:8080` bind still keeps the GUI on the loopback;
> add a reverse proxy with TLS to expose it on the network
> (see [configuration.md](configuration.md#expose-the-web-gui-on-the-network)).

---

## Navigation

```
┌──────────────────────────────────────────────────────────────────────┐
│  obserae   [● daemon up]  [⚡ flows/s]              [Ctrl+K palette] │  topbar
├────────────┬─────────────────────────────────────────────────────────┤
│ ▣ Cockpit  │                                                         │
│ NETWORK   ▾│                                                         │
│   Cartography                                                        │
│   Flow Matrix                Page content                            │
│ ANALYSIS  ▸│                                                         │
│ CONNECTORS▸│   (Investigation · Sessions · Rules · Detection)        │
│ ❒ Audit log│   (Exporters · Cloud Attribution · Threat Intel ·       │
│            │    GeoIP · ASN · Outputs)                               │
│ SETTINGS  ▾│                                                         │
│   Monitoring · Users · Storage · Retention · Backup · Config I/O     │
└────────────┴─────────────────────────────────────────────────────────┘
```

The sidebar is an **accordion**: pages are grouped under four
collapsible themes — **Network** (Cartography, Flow Matrix),
**Analysis** (Investigation, Sessions, Rules, Detection),
**Connectors** (Exporters, Cloud Attribution, Threat Intelligence,
GeoIP, ASN, Outputs) and **Settings** (Monitoring, Users, Storage,
Retention, Backup, Config I/O) — with **Cockpit** and **Audit log** as
direct top-level links. The group holding the page you are on opens
automatically; you can expand or collapse any group by clicking its
header, and obserae remembers your choice across pages. Click any item
to switch page.

The **topbar** is always visible. It shows a live indicator for the
daemon (green = up, red = unreachable) and the current ingest rate
(flows per second), pushed in real time over a WebSocket. When the
in-memory session map comes under pressure, a **pressure badge**
appears here too (amber, then red) — so a "too many open sessions"
condition is visible from any page, not just the cockpit. A separate
**warning icon** appears when there is a database or ingestion problem
(writer contention or matcher backlog) and links to the
[Monitoring](monitoring.md) page.

The **command palette** (`Ctrl+K`) jumps to any page or searches
across cartography entities and rules.

---

## Cockpit

The landing page. Designed so an analyst opening obserae in the
morning knows within 5 seconds whether anything is wrong.

Five zones:

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

The Cockpit is the right place to start every shift. The database and
ingestion internals (DB activity, writer pool, parquet throughput, memory)
live on the [Monitoring](monitoring.md) page instead — the Cockpit stays
focused on product use, and a top-bar warning links you to Monitoring when
something is wrong there.

---

## Monitoring

The operational dashboard (Settings → Monitoring), for whoever runs the
daemon. It updates live from the same WebSocket as the Cockpit and shows:

- **Ingestion (parquet)** — files and records written, flush timings
  (last/avg/max), and the last-flush detail. The "are flows landing and
  importing fast" signal.
- **Memory** — heap in-use (the leak signal), the RSS ceiling, goroutines,
  GC cycles, and the sessions-in-RAM gauge.
- **Pipeline** — per-channel saturation and UDP drops.
- **Database** — a live "ps for the database". obserae writes through a
  **single** connection, so when ingestion slows the question is always
  "what is holding that connection?". The writer-pool header shows `in-use`,
  a live **wait Δ**, and (muted) the cumulative totals; a **Writer
  contention** banner appears only when the per-interval wait crosses the
  threshold (*not* when the cumulative total is high — that only ever grows).
  Below it, **In-flight operations** lists what's running (the writer op is
  flagged `RUNNING`) and **Recent operations** shows the last ops that
  completed, with their duration and any error — so DB activity is visible
  even when nothing is in flight. It's the GUI twin of `obserae-cli ps`
  (see [cli.md](cli.md#ps)); reach for it the moment flows/s drops.

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
- **Network Discovery drawer** (toolbar button) proposes candidate
  **subnets** detected from non-routable (private) traffic, so you can
  declare your networks straight from the observed flows. **+ Declare**
  opens the network form pre-filled with the candidate CIDR.
- **IP Discovery drawer** (toolbar button, formerly *Orphan IPs*) lists
  every IP seen in traffic but not yet declared as an interface — the
  machines to add as hosts. A small switch in the drawer header —
  **All IPs** / **Declared only** — hides the rows tagged
  `outside known CIDRs` so you can focus on candidates already covered
  by one of your networks. The switch state is session-only (does not
  survive a tab reload).
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

The cartography you build in the GUI is part of the single YAML
configuration file you export and import from the **Config I/O**
page (see below) — its `cartography:` section. The Carto page's
File menu keeps only **Export SVG** (a picture of the canvas).

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

The flow-matrix rules are the `flow_matrix:` section of the single
YAML config exported/imported from the **Config I/O** page (see
below). The per-page YAML File menu was removed.

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

## Outputs

Export destinations for your alerts — **webhooks** and **Gotify**. Each
output receives alerts at or above a minimum severity, optionally filtered
by rule name or tag, and obserae delivers them reliably with automatic
retry.

What you can do:

- **Add** a webhook (any URL, optional HMAC signing, custom headers and
  body template) or a Gotify destination (server URL + app token).
- **TLS** for internal endpoints: trust a custom CA certificate, or skip
  verification (with an explicit insecure warning).
- **Route** by minimum severity and optional rule name / tag.
- **Send test** to confirm connectivity and signing before relying on it.
- Watch **Recent deliveries** with per-attempt status (sent / failed /
  dead).

See [outputs.md](outputs.md) for the full reference.

---

## Connectors

Everything that *produces data* for obserae lives under the
**Connectors** group: the Exporters page plus four IP-enrichment
pages (Cloud Attribution, Threat Intelligence, GeoIP, ASN). See
[sources.md](sources.md) for the full walkthrough — including what each
source is good for and its limitations.

### Exporters page

`🖧 Exporters` (`/exporters`) — a table with one row per
NetFlow-emitting device the daemon has seen. The IP is the
`sampler_address` carried on every flow; the **name**, **equipment
type** and **details** columns are yours to fill in — once labelled,
the rest of the GUI (Sessions, Cartography, Investigation) shows the
friendly name instead of the raw IP.

The list auto-refreshes from observed traffic every 5 minutes; a
**Rescan** button forces a sweep on demand if you just added a new
device. Each row also has a **🗑 Delete** button to drop a sampler
you have decommissioned — the rescan only adds new exporters, so
Delete is how you clear out stale ones.

### Cloud Attribution page

`☁ Cloud Attribution` (`/cloud-attribution`) — the master toggle for
IP enrichment plus the list of cloud-provider sources (AWS, Azure,
Google, Oracle Cloud, Cloudflare). When on, every IP gets a discreet
cloud-provider badge across the GUI.

### Threat Intelligence page

`🛡 Threat Intelligence` (`/threat-intel`) — the same controls for
open-source TI feeds (FireHOL Level 1, Tor exit nodes, Tor relays). It
carries the same global IP enrichment toggle (synced with Cloud
Attribution). Hits surface as a red triangle on Sessions and
Cartography. [sources.md](sources.md#threat-intelligence-page) explains
why flagging Tor traffic matters.

### GeoIP page

`🌐 GeoIP` (`/geoip`) — country-level geolocation built from the public
regional-internet-registry (RIR) data; no MaxMind account required. When
on, every public IP gets an ISO country code and Cartography hosts show a
small **country flag**. Same global toggle as the other enrichment pages,
but it refreshes **weekly** (RIR data changes slowly). Note the accuracy
caveats — country only, allocation rather than physical location — in
[sources.md](sources.md#geoip-page).

### ASN page

`⑂ ASN` (`/asn`) — autonomous-system attribution from the ip2asn dataset:
which network operator (`AS<n> <org>`) owns each public IP. It catches IPs
the curated cloud/threat lists miss. Same global toggle; refreshes
**weekly** and is the heaviest source. See
[sources.md](sources.md#asn-page) for what an ASN is and when it helps.

The full enrichment mechanism is described in
[enrichment.md](enrichment.md).

---

## Audit log

> **Enterprise feature — free during the alpha.** The audit log is a
> planned Enterprise feature, fully usable now at no cost while obserae is
> in alpha. See [Licensing & transparency](../LICENSING.md).

`❒ Audit log` (`/auditlog`) is the **append-only record of every operator
action** taken on obserae — across both control planes (the web GUI and
the `obserae-cli` socket). It answers "who changed what, and when": a rule
edited, a source disabled, a user created, a backup restored, an alert
deleted.

```
WHEN                 ACTOR   PLANE  ACTION                 TARGET
2026-06-18 09:14:02  admin   web    rule.updated           ssh-from-internet
2026-06-18 09:02:41  alice   cli    enrichment.disabled    (master switch)
2026-06-17 23:51:10  admin   web    user.created           bob
```

What you can do:

- **Filter** by actor, action, target or time window to reconstruct a
  change history.
- **Open an entry** to see the full detail recorded for that action.
- Conserve it for as long as you need — its retention is configured
  separately on the [Retention](#storage-retention--backup) page, so the
  trail outlives ordinary flow/session data.

### Tamper-evidence

The journal is **tamper-evident**, not just append-only. Every line is
chained to the previous one with a SHA-256 hash, and closed files are
sealed with an HMAC in a separate registry. That means any attempt to
edit, delete or reorder a past entry breaks the chain and is **detectable
after the fact** — even by someone with disk access.

You can verify the chain **independently, offline**, without trusting the
running daemon:

```sh
# Built into the CLI (offline — reads the files directly, no daemon needed)
obserae-cli verify-auditlog --dir ./data/auditlog

# Or with the standalone, dependency-free Python verifier
python3 tools/verify_auditlog.py --dir ./data/auditlog
```

Both read the raw on-disk bytes and report any break in the chain (exit 0 =
intact, non-zero = a break was found). This is what lets the audit log
stand up as evidence rather than a convenience log.

---

## Config I/O

`⇄ Config I/O` (`/config-io`) is the **one place** to export and
import your whole operator configuration as a single YAML file —
it replaces the per-page YAML File menus that used to live on
Carto, Flow Matrix and Rules.

The file has one top-level key per domain, each in the format that
domain already used:

```yaml
cartography: { networks: [...], hosts: [...], groups: [...] }
flow_matrix: { rules: [...] }
alerting:    { queries: [...], rules: [...] }
outputs:     [ ... ]
enrichment:  { enabled: true, sources: [...] }
exporters:   [ ... ]
users:       { groups: [...], users: [...], api_tokens: [...] }
backup:      { ... }
retention:   { ... }
```

The `users` section carries accounts, **custom** groups and API tokens (with
password/token hashes, never plaintext — treat the file as sensitive). The three
**built-in groups** (`admin`, `analyst`, `auditor`) are **never exported**: they
are always present and the server manages their permissions. If a hand-edited
bundle still defines one, the import **ignores it** and shows a warning — so a
file cannot redefine a privileged built-in role.

Three actions:

- **Export configuration** — downloads `obserae-config.yaml`.
  Empty domains are omitted. The file contains secrets in clear
  text (output tokens / HMAC keys) — treat it as sensitive.
- **Validate file…** — checks a file without writing anything
  (the same checks the import runs).
- **Import file…** — after a confirmation, applies it. A section
  **present** in the file *replaces* that domain; a section
  **absent** is left untouched. The whole file is validated first,
  so a mistake never half-applies. A summary then lists which
  domains were applied, which were skipped, and any warnings.
  Exporters are created even if the daemon has never observed
  traffic from them — re-importing a full config usually targets a
  blank database, so unseen exporters are kept rather than dropped.

Cartography is always applied before the flow matrix and the
alerting rules, since those reference topology by name.

---

## Storage, Retention & Backup

Everything that *manages data over time* lives under the **Settings**
group in the sidebar, as three separate pages. See
[lifecycle.md](lifecycle.md) for the full walkthrough.

> Retention and backup changes made here persist across restarts
> (stored in `app_settings`), so they no longer revert to
> `obserae.yaml` on reboot.

### Storage

The on-disk footprint: DuckDB file size, free disk space on the
mount, byte totals for the parquet stores and backup directory.
Polled every 10 seconds — these values move slowly. Use this page
to size the retention policy, or to confirm the backup directory
isn't ballooning past its rotation cap.

### Retention

Periodic purge of stale rows from `flows`, `sessions` and the audit
log. **Off by default** — flip the master switch only after you have
picked at least one max age. Changes take effect on the next sweep;
no restart needed.

### Backup

Periodic native DuckDB snapshots of the whole database, landing
under the configured directory. Rotation enforces the two limits
you set (max age and/or max files). A **Backup now** button writes
one snapshot immediately; the timeline below shows the snapshot
chain, and any point can be previewed and restored from here.

---

## Users & Access

> **Enterprise feature — free during the alpha.** Multiple user accounts, groups,
> role-based access (RBAC) and API-token management are a planned Enterprise
> feature, fully usable now at no cost while obserae is in alpha. The single
> administrator login the GUI always requires is part of the core product. See
> [Licensing & transparency](../LICENSING.md).

The **Users** page (visible only to administrators) manages who can sign in
and what they can do. It has three tabs, each laid out like the Flow Matrix: a
list of rows with **Edit** and **Delete** buttons, and a **+ New …** button at
the top right that opens a creation dialog. Edits and deletions open a dialog
too (deletes ask for confirmation first).

- **Users** — each row shows the account, its groups and its status. **+ New
  user** creates an account (username, display name, password, groups);
  **Edit** changes the display name, groups, enabled/disabled state, and can set
  a new password (leave the password blank to keep the current one). The
  built-in `admin` account is always present and cannot be deleted.
- **Groups** — a user's permissions are the union of their groups'. Three
  built-in groups ship and cannot be edited or deleted:
  - **admin** — full access to everything.
  - **analyst** — operate the product: view, investigate, run NFQL,
    acknowledge alerts, edit cartography, rules and detection.
  - **auditor** — read-only: dashboard, cartography, sessions, rules, alerts.

  Use **+ New group** to create a **custom group** and tick exactly the
  permissions it grants (e.g. `cartography:read`, `nfql:execute`,
  `outputs:manage`); **Edit** adjusts its description and permissions. A custom
  group can only be deleted once it has no members.
- **API tokens** — **+ New token** mints a token for a user to call the REST
  API from a script: `Authorization: Bearer obs_…`. The secret is shown **once**
  in a dialog right after creation — copy it then. Tokens inherit their owner's
  permissions and can be revoked or deleted from their row.

Pages and actions a user isn't allowed to use are hidden from their sidebar and
toolbars, and the server refuses them regardless (so a hidden action can't be
forced by hand). Sign out from the **user menu** at the top-right of any page.

The same operations are available headless via the CLI — see
[cli.md](cli.md#user--access-management) — including recovering access with
`obserae-cli user reset-admin-password` if you are locked out of the GUI.

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

# Command-line interface

`obserae-cli` is the admin client. It talks to the daemon over a
Unix socket — no network port, no authentication beyond filesystem
permissions on the socket itself.

```
obserae-cli [--socket PATH] <command> [flags]
```

---

## Connecting to the daemon

By default, `obserae-cli` looks for `/var/run/obserae.sock`. For
local development or non-standard paths, pass `--socket`:

```sh
obserae-cli --socket ./data/obserae.sock status
```

The easiest way to avoid repeating the flag is a shell alias:

```sh
alias obserae-cli='obserae-cli --socket /var/lib/obserae/run/obserae.sock'
```

---

## Getting help

Every command and verb is self-documenting, and help is printed locally —
no running daemon required:

```sh
obserae-cli                  # list every command
obserae-cli --help           # same (also: -h, help)
obserae-cli rule --help      # a group's verbs (also: rule -h, rule help)
obserae-cli rule add --help  # a verb's flags
```

A mistyped command or verb prints the relevant usage and exits non-zero,
so a typo never fails silently.

---

## Command map

| Command         | Purpose                                                         |
|-----------------|-----------------------------------------------------------------|
| `status`        | Daemon liveness + per-table counts                              |
| `config`        | Bulk import / export / validate the WHOLE configuration (one YAML bundle) |
| `network`       | CRUD on networks                                                |
| `host`          | CRUD on hosts                                                   |
| `interface`     | CRUD on host interfaces (always `--host`-scoped)                |
| `service`       | CRUD on host services (always `--host`-scoped)                  |
| `group`         | CRUD on groups (members are hosts and/or other groups)          |
| `rule`          | CRUD on individual detection rules                              |
| `matches`       | Read-only view of detection matches                             |
| `alert`         | Triage fired detection alerts: ls/show/ack/close/rm              |
| `output`        | Manage alert delivery targets (webhook/Gotify): CRUD, test, deliveries |
| `exporter`      | Label discovered NetFlow exporters and trigger a rescan          |
| `enrichment`    | IP enrichment: master toggle, per-source feeds, manual refresh   |
| `user`          | Manage GUI users, groups, API tokens; reset the admin password   |
| `query`         | Run an NFQL pipeline against the daemon                         |
| `ps`            | Live database activity (in-flight ops + writer queue)           |
| `retention`     | Show the data-retention policy + last sweep, or run one now      |
| `backup`        | Snapshots: status, run, list, preview and apply a restore        |

Most read commands accept `--json` for machine output. Most `rm`
commands accept `--yes` (skip prompt) and `--dry-run` (preview only).

---

## `status`

```sh
obserae-cli status [--json]
```

Daemon liveness plus per-table counts. Useful as a smoke test or
as a monitoring datapoint.

```text
version:             v1.2.0
commit:              fe2bc84
started:             2026-04-29 08:12:33 UTC
uptime:              1h2m22s

networks:            5
hosts:               11
services:            23
groups:              6

rules:               10
expansions:          1462

flows:               1284091
templates reçus:     2
paquets en attente de template: 0

sessions active:     124
sessions half-open:  3
sessions closed:     8945

sessions open (live):  12345 / 500000 (2.5%)
sessions evicted:      0
enrich LRU:            412345 / 1000000 (41.2%)
```

`templates reçus` (`templates_received`) is the number of NetFlow v9
templates persisted to disk. obserae now keeps v9 templates in DuckDB
and reloads them at boot, so a restart no longer blacks out flow
decoding while waiting for the exporter's next template refresh.
`paquets en attente de template` (`packets_awaiting_template`) is the
running count of data packets the decoder had to drop for lack of a
template — a non-zero value **with `flows: 0`** means a brand-new
exporter the daemon has never seen; force its template with
`configctl netflow stop && configctl netflow start` on OPNsense, or
wait for the next refresh.

The last three rows are live fill gauges — entry counts against
their caps, not bytes: `sessions open (live)` is
the in-memory session map versus its `max_open_ksessions` cap,
`sessions evicted` counts sessions force-closed under capacity
pressure (`close_reason = 'capacity'`), and `enrich LRU` is the
enrichment resolver's cache versus its capacity.

---

## `config`

Bulk import / export / validate of the **whole configuration** as one
YAML bundle — the CLI pendant of the GUI's Config I/O page (same file).
One top-level key per domain: `cartography`, `flow_matrix`, `alerting`,
`outputs`, `enrichment`, `exporters`, `backup`, `retention`.

```sh
obserae-cli config validate FILE     # checks only, no write
obserae-cli config import   FILE     # apply the bundle
obserae-cli config export   [--output FILE]
```

Use `-` for `FILE` to read stdin / write stdout. A section present in the
file replaces that domain; an absent section is left untouched. The bundle
is validated fully before any write, then applied in dependency order
(`cartography` first). `import` prints what was applied / kept / warned.

> The exported file holds secrets in clear text (output tokens / HMAC
> keys) — keep it safe. The old per-domain bulk commands (`cartography`,
> `rules` import/export) were folded into this one; per-entity commands
> below remain.

---

## Per-entity CRUD: `network`, `host`, `interface`, `service`, `group`

All five entities share the same five verbs (`add`, `ls`, `show`,
`update`, `rm`).

### Networks

```sh
obserae-cli network add prod-vlan20 --cidr 10.20.0.0/16 [--vlan 20] [--description S]
obserae-cli network ls               [--json]
obserae-cli network show NAME        [--json]
obserae-cli network update NAME [--name N] [--cidr X] [--vlan V] [--description S]
obserae-cli network rm   NAME        [--yes] [--dry-run]
```

### Hosts

```sh
obserae-cli host add NAME
obserae-cli host update NAME --name NEW
obserae-cli host rm NAME             [--yes] [--dry-run]
```

### Interfaces (scoped under a host)

```sh
obserae-cli interface add eth0 --host srv-db --network prod-vlan20 --ip 10.20.0.5
obserae-cli interface ls --host srv-db
obserae-cli interface update NAME --host H [--name N] [--network NET] [--ip IP]
obserae-cli interface rm     NAME --host H [--yes] [--dry-run]
```

### Services (scoped under a host)

```sh
obserae-cli service add postgres --host srv-db \
    --protocol TCP --port 5432 --interfaces eth0,eth1 [--description S]

obserae-cli service ls --host srv-db
obserae-cli service update NAME --host H \
    [--name N] [--protocol P] [--port N] [--interfaces a,b] [--description S]
obserae-cli service rm  NAME --host H [--yes] [--dry-run]
```

### Groups

```sh
obserae-cli group add backend [--members a,b,c]
obserae-cli group ls    [--json]
obserae-cli group show backend
obserae-cli group update backend [--name N] [--members a,b]        # replace member list
obserae-cli group update backend [--add-member X] [--rm-member Y]  # incremental
obserae-cli group rm     backend [--yes] [--dry-run]
```

### Delete-with-preview

Every `rm` first asks the daemon what would cascade, prints a summary,
then prompts:

```text
$ obserae-cli network rm admin
Deleting network admin will:
  - delete 11 entities
  - modify 0 entities
Proceed? [N/y/I]
```

- **N** (default) aborts.
- **y** commits.
- **I** lists every affected entity, then re-prompts.
- **`--yes`** skips the prompt entirely (scripts).
- **`--dry-run`** prints the impact and never writes.

---

## `rule`

Per-entity CRUD on detection rules. Bulk import/export of the whole rule
set is part of `config` (the `flow_matrix:` section). See
[rules.md](rules.md) for the YAML schema.

```sh
obserae-cli rule add NAME \
    --src REF --dst REF \
    [--src-service S] [--dst-service S] \
    [--src-iface IF] [--dst-iface IF] \
    [--protocol P] [--description S] \
    [--enabled=BOOL]

obserae-cli rule ls       [--json]
obserae-cli rule show NAME [--json]
obserae-cli rule update NAME \
    [--name NEW] [--src REF] [--dst REF] \
    [--src-service S] [--dst-service S] \
    [--src-iface IF] [--dst-iface IF] \
    [--protocol P] [--description S] \
    [--enabled=BOOL]
obserae-cli rule rm NAME   [--yes] [--dry-run]

obserae-cli rule enable  NAME   [--json]
obserae-cli rule disable NAME   [--json]
obserae-cli rule bulk [--enable a,b,c] [--disable d,e]
```

`enable` / `disable` are shorthands for `update --enabled=BOOL`: a disabled
rule is kept but stops matching traffic. `bulk` toggles many rules at once
("disable these twelve false-positives"); a name in both lists resolves to
**disable**, and per-rule failures don't abort the rest.

The protocol is normally carried by `--src-service` /
`--dst-service` (`*/TCP`, `53/UDP`, or a catalogued service name).
`--protocol P` is an optional legacy override that is reconciled
with the service tokens — it must not contradict a protocol pinned
by either side. See [rules.md](rules.md#the-portservice-field).

The reference syntax for `--src` / `--dst` is described in
[cartography.md](cartography.md#references-used-by-rules-and-nfql).

---

## `matches`

Read-only view of detection matches.

```sh
obserae-cli matches ls \
    [--rule NAME]               # filter by rule
    [--since DURATION|RFC3339]  # only matches newer than this
    [--limit N]                 # cap (default 50)
    [--json]
```

Examples:

```sh
obserae-cli matches ls --since 1h
obserae-cli matches ls --rule public-https --limit 200
obserae-cli matches ls --since 2026-05-01T12:00:00Z
obserae-cli matches ls --json | jq '.[] | select(.protocol == 6)'
```

Default text output:

```
<matched_at>  <rule>  <ip_a:port_a> <-> <ip_b:port_b>  proto=<n>  server=<ip:port> (<method>/<conf>)  session=<uuid>
```

The `<->` reflects the non-orientation of a session — endpoints are
stored in canonical IP order; the inferred `server=…` recovers the
operationally-meaningful direction.

---

## `alert`

Triage fired detection alerts — the CLI image of the Detection page. Alerts
are addressed by their **UUID** (`ls` prints it). Status: `new` → `ack` →
`closed`.

```sh
obserae-cli alert ls [--severity S] [--status new|ack|closed] [--rule N] \
    [--since 1h|RFC3339] [--limit N] [--json]
obserae-cli alert show ID [--json]
obserae-cli alert ack   ID
obserae-cli alert close ID
obserae-cli alert rm ID [ID...] [--yes]
```

`--since` accepts a duration (`1h`) or an RFC3339 timestamp. `rm` accepts
several ids and reports how many were deleted (unknown ids are skipped).

---

## `output`

Manage alert delivery targets (webhook / Gotify) — the CLI image of the
Outputs page. Outputs are addressed by **name**.

```sh
obserae-cli output ls [--json]
obserae-cli output show NAME [--json]

# webhook (secret via stdin keeps it out of shell history)
printf '%s' "$SECRET" | obserae-cli output add alerts-hook \
    --type webhook --url https://hooks.example/obserae --secret - \
    [--header "X-Env: prod"]... [--min-severity high] [--rules a,b]

# gotify
obserae-cli output add pager --type gotify \
    --base-url https://gotify.example --secret APP_TOKEN

obserae-cli output update NAME [--url …] [--min-severity …] [--secret -]
obserae-cli output enable|disable NAME
obserae-cli output rm NAME [--yes]
obserae-cli output test NAME                 # send a test delivery now
obserae-cli output deliveries NAME [--limit N] [--json]
```

Secrets are write-only — `ls` / `show` only show a `has_secret` flag, never
the value. Use `--secret -` to read the secret from stdin. On `update`, a
config flag (`--url`, `--header`, …) merges onto the stored config; the
secret changes only when `--secret` is passed. `output test` sends a
synthetic alert right away and exits non-zero on failure. The full output
set is also part of the `outputs:` config-bundle section.

---

## `exporter`

Label the NetFlow exporters the daemon has observed, and trigger a rescan.

```sh
obserae-cli exporter ls [--json]
obserae-cli exporter show IP [--json]
obserae-cli exporter set IP [--name N] [--type T] [--details D]
obserae-cli exporter rescan
```

Exporters are **discovered, not created** — a row appears the first time a
device sends flows (keyed by `sampler_address`), so there is no `add`/`rm`.
`set` labels an existing exporter; only `name`, `equipment_type` and
`details` are editable (the seen/flow-count columns are daemon-owned). Labels
are also carried in the `exporters:` config-bundle section.

---

## `enrichment`

Drive IP enrichment — the master toggle and the per-source feeds (cloud CIDR
ranges, threat-intel lists, GeoIP, ASN) — the CLI image of the Connectors
enrichment pages (Cloud Attribution, Threat Intelligence, GeoIP, ASN).

```sh
obserae-cli enrichment status [--json]            # master toggle + last change
obserae-cli enrichment enable | disable           # master switch
obserae-cli enrichment sources [--json]           # every feed + its state
obserae-cli enrichment source NAME --enabled=BOOL # toggle one feed
obserae-cli enrichment refresh NAME               # force a fetch now (async)
```

`sources` shows each feed's enabled flag, fetch status, range count and last
fetch. `refresh` enqueues an immediate fetch (poll `sources` to watch
`fetching → idle`). The enabled flags are also in the `enrichment:`
config-bundle section; `refresh` is the operational action with no YAML form.

---

## `query`

Run an NFQL pipeline. See [nfql.md](nfql.md) for the full language.

```sh
obserae-cli query [--json] [--arg VALUE]... NFQL
```

| Flag       | Effect                                                      |
|------------|-------------------------------------------------------------|
| `--json`   | Emit a list of objects (one per row) instead of a table.    |
| `--arg V`  | Bind one `?` placeholder. Repeatable; left-to-right order.  |

`--arg V` coerces:

- `s:foo` → string `"foo"` (escape hatch for values that look like numbers).
- decimal → integer.
- anything else → string.

Examples:

```sh
# Plain table
obserae-cli query 'FROM flows | LIMIT 5'

# Bound parameter
obserae-cli query --arg 443 'FROM flows | WHERE dst_port == ? | LIMIT 5'

# Cartography reference as a string
obserae-cli query --arg "host:proxy:eth1" \
  'FROM flows | WHERE src_addr == ? | LIMIT 20'

# Relative time bound (negative = N seconds before now)
obserae-cli query --arg -3600 'FROM flows | BETWEEN ? AND *'

# JSON output for downstream tooling
obserae-cli query --json 'FROM flows | KEEP src_addr, bytes | SORT bytes DESC | LIMIT 10' | jq

# Pivot cascade: signal in one table, drill in another
obserae-cli query \
  'FROM session_matches | LAST 3600
   > FROM sessions | PIVOT session_id == session_id
                   | KEEP ip_a, ip_b, server_ip, role_method'
```

The default table output decodes a few well-known integer columns
into their canonical names (`protocol` → `TCP`, `tcp_flags` →
`SYN,ACK`). `--json` keeps raw numeric values so downstream filters
keep working.

---

## `ps`

A `top`-like view of what the database is doing right now — the first
thing to reach for when ingestion feels slow. obserae serialises every
write on a **single** database connection, so a stall always has one
culprit: the operation currently holding that connection. `activity` is
an accepted alias for `ps`.

```sh
obserae-cli ps                 # one snapshot
obserae-cli ps --watch 1s      # refresh every second (Ctrl-C to stop)
obserae-cli ps --json          # machine-readable
```

```text
writer pool: in_use=1 open=1  waits since start (cumulative): count=12 total=4.231s

IN-FLIGHT (2)
  POOL    ELAPSED      STATE  OP
  writer  3.120s       RUNNING sessions.correlator.assign_batch
  reader  12ms         running query.nfql

RECENT (8, slowest first)
  POOL    ELAPSED      ERR    OP
  writer  890ms               inserter.parquet
  writer  120ms               enrichment.insert_batch
```

- **IN-FLIGHT** lists operations executing now, longest first. The first
  `writer` row is flagged `RUNNING` — it is the one holding the single
  writer connection. **This is the real-time "stalling now" signal:** a
  `RUNNING` write whose `ELAPSED` keeps climbing is the operation pinning
  ingestion. `reader` rows are read-only queries (NFQL, cockpit) running
  concurrently on the reader pool.
- The `waits since start` counters are **cumulative since the daemon
  started** (`sql.DBStats`) — they only ever grow, because every
  goroutine takes its turn on the single writer connection (normal
  serialisation). A large total is **not** an alarm; judge contention
  from the `RUNNING` op's elapsed time, not from this counter. The
  Cockpit's DB-activity pane adds a per-interval `wait Δ` that *does*
  fall back to zero, and only raises a banner on real contention.
- **RECENT** is a ring of the last completed operations, slowest first,
  so a spike that already finished is still visible. `✗` marks a failure.

The same data drives the **DB activity** pane on the Cockpit page.

---

## `retention`

Read the live data-retention policy and last-sweep result, or trigger a
sweep now.

```sh
obserae-cli retention status [--json]   # live policy + last-sweep counters
obserae-cli retention run               # trigger a sweep now (async)
```

Policy changes are declarative — edit the `retention:` section and
`obserae-cli config import`, or use the [Lifecycle page](lifecycle.md).
There is no `retention set`.

---

## `backup`

Inspect the snapshot policy and files, trigger a snapshot, or run a
point-in-time restore.

```sh
obserae-cli backup status  [--json]                # policy + last snapshot + next action
obserae-cli backup run     [--full]                # snapshot now (async)
obserae-cli backup list [--json]
obserae-cli backup plan    --point-in-time RFC3339 [--json]
obserae-cli backup restore --point-in-time RFC3339 [--dry-run] --confirm [--json]
```

`backup run` lets the runner decide full-vs-delta (like the GUI "Backup
now"); `--full` forces a full. The backup *policy* is changed via the
`backup:` config section or the Lifecycle page, not a `set` verb.

- **`list`** shows every snapshot directory on disk — daily fulls and the
  chain of deltas that descend from them — with kind, timestamp, size and
  parent.
- **`plan`** previews the restore chain that lands closest to
  `--point-in-time` (the full chosen as base, the ordered deltas, the
  cumulative size) without touching anything.
- **`restore`** is **destructive** and refuses to run without `--confirm`.
  With `--dry-run` every step runs except the final swap, so you can
  validate a chain safely. On a real restore the daemon swaps the live
  database and **exits** — your supervisor (systemd, Docker, …) restarts it
  on the restored file.

```sh
# Typical workflow: list, preview, rehearse, apply.
obserae-cli backup list
obserae-cli backup plan    --point-in-time 2026-05-28T13:00:00Z
obserae-cli backup restore --point-in-time 2026-05-28T13:00:00Z --dry-run --confirm
obserae-cli backup restore --point-in-time 2026-05-28T13:00:00Z --confirm
```

Backup scheduling and retention are configured on the
[Lifecycle page](lifecycle.md); the full restore workflow and its
exit-after-swap rationale are documented there too.

---

## User & access management

The `user` group administers GUI accounts, groups, API tokens and the admin
password — the same model as the GUI [Users page](web-gui.md#users--access),
usable headless (e.g. to recover access).

> Multiple users and RBAC are a planned **Enterprise** feature — free during the
> alpha (see [Licensing & transparency](../LICENSING.md)). Single-admin recovery
> below is part of the core product.

```sh
# Recover access: generate a fresh admin password (printed once).
obserae-cli user reset-admin-password
# Or set a chosen one (also accepts the password on stdin).
obserae-cli user set-admin-password --password 's3cret'

# Users.
obserae-cli user ls
obserae-cli user add --username alice --password 's3cret' --display "Alice" --groups analyst
obserae-cli user rm alice

# Groups (built-in admin/analyst/auditor cannot be changed).
obserae-cli user group-ls
obserae-cli user group-add --name soc --perms cartography:read,sessions:read,alerts:read,alerts:ack
obserae-cli user group-rm soc          # only if it has no members

# API tokens (the secret is printed once; use it as a Bearer credential).
obserae-cli user token-add --name ci --user alice
obserae-cli user token-ls
obserae-cli user token-rm <TOKEN_ID>   # revoke
```

A token authenticates REST calls against the web API:

```sh
curl -H "Authorization: Bearer obs_…" http://127.0.0.1:8080/api/query …
```

The full permission catalogue (`cartography:read`, `rules:write`,
`nfql:execute`, `users:manage`, …) is described on the
[Users page](web-gui.md#users--access).

---

## Common errors

| Symptom                                                                          | Cause                              | Fix                                              |
|----------------------------------------------------------------------------------|------------------------------------|--------------------------------------------------|
| `dial unix /var/run/obserae.sock: connect: no such file or directory`            | Daemon not running, or wrong path  | Start the daemon, or pass `--socket`             |
| `daemon: rule "X": not found`                                                    | Typo or rule deleted               | `obserae-cli rule ls` for the current set        |
| `daemon: name "X" is used by both host and group`                                | Cartography name collision         | Pick distinct names (one global namespace)       |
| `sem: 1:18: unknown column "prtocol"`                                            | NFQL typo                          | Look at `line:column` for the offending token    |
| `sem: 1:32: host "srv-typoo": not found`                                         | Cartography reference doesn't resolve | Fix the name in the query or the cartography  |

For NFQL-specific errors, see [nfql.md](nfql.md#reading-error-messages).

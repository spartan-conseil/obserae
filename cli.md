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

## Command map

| Command         | Purpose                                                       |
|-----------------|---------------------------------------------------------------|
| `status`        | Daemon health + per-table counts                              |
| `cartography`   | Bulk YAML import / export / validate                          |
| `network`       | CRUD on networks                                              |
| `host`          | CRUD on hosts                                                 |
| `interface`     | CRUD on host interfaces (always `--host`-scoped)              |
| `service`       | CRUD on host services (always `--host`-scoped)                |
| `group`         | CRUD on groups (members are hosts and/or other groups)        |
| `rules`         | Bulk YAML import / export / validate                          |
| `rule`          | CRUD on individual detection rules                            |
| `matches`       | Read-only view of detection matches                           |
| `query`         | Run an NFQL pipeline                                          |

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

## `cartography`

Bulk operations on the full topology. See [cartography.md](cartography.md)
for the YAML schema.

```sh
obserae-cli cartography validate FILE     # checks only, no write
obserae-cli cartography import   FILE     # full atomic replacement
obserae-cli cartography export   [--output FILE]
```

Use `-` for `FILE` to read stdin / write stdout.

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

## `rules` and `rule`

`rules` (plural) handles bulk YAML; `rule` (singular) is per-entity
CRUD. See [rules.md](rules.md) for the YAML schema.

### Bulk

```sh
obserae-cli rules validate FILE
obserae-cli rules import   FILE
obserae-cli rules export   [--output FILE]
```

### Per-entity

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
```

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

## Common errors

| Symptom                                                                          | Cause                              | Fix                                              |
|----------------------------------------------------------------------------------|------------------------------------|--------------------------------------------------|
| `dial unix /var/run/obserae.sock: connect: no such file or directory`            | Daemon not running, or wrong path  | Start the daemon, or pass `--socket`             |
| `daemon: rule "X": not found`                                                    | Typo or rule deleted               | `obserae-cli rule ls` for the current set        |
| `daemon: name "X" is used by both host and group`                                | Cartography name collision         | Pick distinct names (one global namespace)       |
| `sem: 1:18: unknown column "prtocol"`                                            | NFQL typo                          | Look at `line:column` for the offending token    |
| `sem: 1:32: host "srv-typoo": not found`                                         | Cartography reference doesn't resolve | Fix the name in the query or the cartography  |

For NFQL-specific errors, see [nfql.md](nfql.md#reading-error-messages).

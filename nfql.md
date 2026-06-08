# NFQL — the query language

NFQL is the language you type into the **Query** page of the GUI
(or `obserae-cli query` on the command line) to investigate
traffic. It is a small, pipeline-oriented language designed to
read like a sentence and to integrate with your cartography.

```nfql
FROM flows | WHERE ip == "production" AND protocol == TCP | LIMIT 100
```

> Reads as: "From the flows table, keep rows whose source or
> destination IP is somewhere in the production group and whose
> protocol is TCP, then return at most 100 rows."

This page is a hands-on guide covering the syntax, the operators,
and a library of copy-able recipes.

---

## Running a query

### Web GUI

Open the **Query** page (sidebar). Type your pipeline, press
`Ctrl+Enter` (or click **Run**). Results render in a sortable table
below.

### CLI

```sh
# Plain table
obserae-cli query 'FROM flows | LIMIT 5'

# Bind values into ? placeholders
obserae-cli query --arg 443 'FROM flows | WHERE dst_port == ? | LIMIT 5'

# JSON (one object per row)
obserae-cli query --json 'FROM flows | KEEP src_addr, bytes | LIMIT 3'
```

---

## The pipeline model

Every query is a chain of stages separated by `|`. Each stage
transforms the rows produced by the previous one:

```nfql
FROM flows                       # source — always required, always first
  | WHERE protocol == TCP        # filter
  | KEEP src_addr, dst_addr      # narrow the column set
  | SORT bytes DESC              # order rows
  | LIMIT 50                     # cap row count
```

Stages run **left-to-right**, like Unix pipes. A `WHERE` after a
`KEEP` only sees the kept columns.

### Stages

| Stage         | Purpose                                                            |
|---------------|--------------------------------------------------------------------|
| `FROM`        | Source table.                                                      |
| `WHERE`       | Filter rows by a boolean predicate.                                |
| `KEEP`        | Project to the listed columns, in the listed order.                |
| `DROP`        | Remove the listed columns, keep the rest in their original order (reciprocal of `KEEP`). |
| `RENAME`      | Rename columns in place: `RENAME new = old, …` (new name on the left). |
| `SORT`        | Order rows by one or more keys (`ASC` default, `DESC` available).  |
| `LIMIT`       | Cap the number of rows.                                            |
| `LAST`        | Time window: rows from the last N seconds.                         |
| `BETWEEN`     | Time window: explicit `<from>` / `<to>` bounds.                    |
| `STATS`       | Aggregate: `STATS <alias> = <fn>(<arg>) [, …] [BY <col> …]`.       |
| `EVAL`        | Compute new columns: `EVAL <alias> = <expr>`.                      |
| `HAVING`      | Filter after `STATS` (the post-aggregation analogue of `WHERE`).   |
| `PIVOT`       | Cross-pipeline semi-join (see [Cross-pipeline lookups](#cross-pipeline-lookups)). |
| `PIVOT NOT`   | Anti-semi-join.                                                    |
| `JOIN`        | Inner equi-join.                                                   |

`SORT` and `LIMIT` may appear once each. `WHERE`, `KEEP`, `LAST`,
`BETWEEN` may appear multiple times; their effects intersect.

---

## Tables

| Table                  | Purpose                                                                              | Time column     |
|------------------------|---------------------------------------------------------------------------------------|-----------------|
| `flows`                | Append-only, one row per NetFlow record.                                              | `time_received` |
| `sessions`             | Bidirectional, role-aware consolidation, **per exporter**. Carries `correlation_id`. See [sessions.md](sessions.md). | `opened_at`     |
| `sessions_consolidated`| One row per **conversation**: the per-exporter sessions of the same 5-tuple merged. `min`/`max` volumes across exporters + `coherence_pct`. | `opened_at`     |
| `sessions_dead_letter` | Audit trail of flows rejected by the sessionizer (today: late arrivals).              | `dropped_at`    |
| `session_matches`      | One row per (session, rule) hit. JOIN with `sessions` to recover endpoints.           | `matched_at`    |
| `enrichment_ranges`        | CIDR catalogue (cloud + threat). `WITHIN`-join a flow set against `cidr`. See [enrichment.md](enrichment.md). | `fetched_at`    |
| `enrichment_ips`        | Insert-time dimension: one row per `(ip, source)` resolved at ingest. **Equi-join** on the IP — see [enrichment.md](enrichment.md#faster-the-enrichment_ips-table). | `resolved_at`   |

`LAST` and `BETWEEN` always filter on the listed time column —
syntax stays the same regardless of which table you query.

### Most-used columns

**`flows`**: `src_addr`, `dst_addr`, `src_port`, `dst_port`,
`protocol`, `bytes`, `packets`, `tcp_flags`, `time_received`,
`time_flow_start`, `time_flow_end`, `sampler_address`.

**`sessions`**: `session_id`, `ip_a`/`port_a`, `ip_b`/`port_b`,
`protocol`, `state` (`active`/`half_open`/`closed`),
`opened_at`, `closed_at`, `close_reason`, `server_ip`,
`server_port`, `role_method`, `role_conf`,
`ab_bytes`/`ba_bytes`, `ab_pkts`/`ba_pkts`, `correlation_id`
(conversation group; NULL while open).

**`sessions_consolidated`**: `correlation_id`, `client_ip`/`client_port`,
`server_ip`/`server_port`, `protocol`, `session_count`, `sampler_count`,
`samplers`, `coherence_pct` (0–100),
`min_client_to_server_bytes`/`max_client_to_server_bytes` (and `_packets`,
and the `server_to_client_` pair), `opened_at`, `closed_at`. Endpoints are
client/server oriented (not the raw sessions' canonical `a`/`b`); the
virtual `ip`/`port` cover both sides.

**`session_matches`**: `session_id`, `rule_id`, `matched_at`.

---

## Predicates in `WHERE`

### Comparisons

```nfql
FROM flows | WHERE bytes > 1000000
FROM flows | WHERE protocol == 6                # int eq
FROM flows | WHERE src_port < 1024
FROM flows | WHERE dst_port >= 5000
```

Operators: `==`, `!=`, `<`, `<=`, `>`, `>=`.

For CIDR containment on `INET` columns, use the explicit `WITHIN`
operator:

```nfql
FROM sessions | WHERE server_ip WITHIN "10.0.0.0/8"
```

Reads "left value is contained by right value". Both operands must
be `INET`. Note: `==` against a CIDR is **strict equality** (the
column must equal that exact IP/CIDR), not containment. Use
`WITHIN` for containment.

### Logical operators

```nfql
FROM flows | WHERE protocol == TCP AND dst_port == 443
FROM flows | WHERE dst_port == 80 OR dst_port == 443
FROM flows | WHERE NOT (protocol == TCP)
FROM flows | WHERE (dst_port == 80 OR dst_port == 443) AND protocol == TCP
```

Precedence (tightest first): `NOT`, comparisons, `AND`, `OR`. Use
parentheses when in doubt.

### Set membership

```nfql
FROM flows | WHERE dst_port IN (80, 443, 8080)
FROM flows | WHERE protocol IN (TCP, UDP)
```

---

## Ergonomic features

### Named protocol constants

| Constant   | Value | Meaning           |
|------------|-------|-------------------|
| `TCP`      | 6     | TCP               |
| `UDP`      | 17    | UDP               |
| `ICMP`     | 1     | ICMP (IPv4)       |
| `ICMPv6`   | 58    | ICMP (IPv6)       |
| `SCTP`     | 132   | SCTP              |
| `GRE`      | 47    | GRE               |

Case-insensitive. Resolve to their integer value:

```nfql
FROM flows | WHERE protocol == tcp           # same as protocol == 6
FROM flows | WHERE protocol IN (TCP, UDP)
FROM flows | WHERE protocol == "TCP"         # string form also works
```

### Virtual columns

Two columns expand to a disjunction over their src/dst pair:

| Virtual | Expands to                |
|---------|---------------------------|
| `ip`    | `src_addr OR dst_addr`    |
| `port`  | `src_port OR dst_port`    |

```nfql
FROM flows | WHERE ip == "10.0.0.1"
# rewritten as: src_addr == "10.0.0.1" OR dst_addr == "10.0.0.1"

FROM flows | WHERE port == 443
# rewritten as: src_port == 443 OR dst_port == 443
```

`!=` flips the connector to `AND` (De Morgan): `ip != X` means
*neither* `src_addr` nor `dst_addr` equal X. `IN` distributes over
both sides.

On `sessions`, `ip` and `port` expand to `ip_a`/`ip_b` and
`port_a`/`port_b` respectively — same syntax, same semantics.

### Cartography references

When you compare any `INET` column with a **string literal**, NFQL
picks the right interpretation:

| String                    | Meaning                                                |
|---------------------------|--------------------------------------------------------|
| `"192.168.1.1"`           | The exact IP (IPv4 or IPv6, e.g. `"2001:db8::1"`)      |
| `"10.0.0.0/8"`            | The exact CIDR (IPv4 or IPv6, e.g. `"2001:db8::/64"`; use `WITHIN` for containment) |
| `"any4"` / `"any6"`       | Reserved: every IP of one family (`0.0.0.0/0` or `::/0`) |
| `"internet4"` / `"internet6"` | Public unicast of one family (excludes RFC1918 / ULA, loopback, link-local, CGNAT, multicast, reserved) |
| `"internal4"` / `"internal6"` | Non-routable IPs of one family — the **exact complement** of `"internet4"` / `"internet6"` (RFC1918 / ULA, loopback, link-local, CGNAT, multicast, reserved, mapped) |
| `"network:NAME"`          | The named network's CIDR                               |
| `"NAME.dhcp"`             | The network's DHCP pool only (needs a [DHCP range](cartography.md#dhcp-networks)) |
| `"NAME.static"`           | The network's CIDR **minus** its DHCP pool             |
| `"host:NAME"`             | Every interface IP of the host                         |
| `"host:NAME:IFACE"`       | One specific interface IP                              |
| `"group:NAME"`            | Every IP of every member host (recursive)              |
| `"NAME"` (bare)           | Looked up across networks/hosts/groups                 |

```nfql
FROM flows | WHERE src_addr == "internet4" AND dst_addr == "loadbalancers"
FROM flows | WHERE ip IN ("10.0.0.0/8", "host:proxy", "group:backends")

FROM sessions | WHERE ip == "host:proxy" AND state == "active"
FROM sessions | WHERE server_ip == "group:databases" AND server_port == 5432

# the dynamic side vs the fixed side of a DHCP segment
FROM sessions | WHERE ip == "office.dhcp"
FROM flows    | WHERE src_addr == "office.static"
```

The lookup is **dynamic** — if the cartography changes between two
runs of the same compiled query, the next run reflects the new
state.

IPv6 addresses use the **same** quoted-string syntax as IPv4 —
there is no special form:

```nfql
FROM flows | WHERE ip == "2001:db8::1"
FROM sessions | WHERE server_ip WITHIN "2001:db8::/64"
```

The reserved keywords are **family-specific**: `"internet4"`,
`"internal4"` and `"any4"` only match IPv4 addresses; `"internet6"`,
`"internal6"` and `"any6"` only IPv6. To match both families in one
query, combine them — e.g. `WHERE ip == "internet4" OR ip == "internet6"`.

`"internal4"` / `"internal6"` are the exact complement of their
`internet` twin: every routable v4 IP satisfies `"internet4"`, every
non-routable v4 IP satisfies `"internal4"`, and the two never overlap.
Use it to write "anything on the LAN" without spelling out every
RFC1918 / loopback / link-local CIDR.

---

## Time windows

### `LAST N` — last N seconds

```nfql
FROM flows | LAST 60          # last minute
FROM flows | LAST 3600        # last hour
FROM flows | LAST 86400       # last day
```

### `BETWEEN <from> AND <to>`

Both sides accept:

| Form              | Meaning                                                |
|-------------------|--------------------------------------------------------|
| Positive integer  | Absolute Unix timestamp in seconds                     |
| Negative integer  | `-N` = N seconds before now                            |
| RFC 3339 string   | `"2026-05-01T12:00:00Z"`, with TZ offsets allowed      |
| `"YYYY-MM-DD"`    | Date-only, midnight UTC                                |
| `*`               | Open: no constraint on this side                       |
| `now`             | Right-side alias for `*`                               |
| `?`               | Bound at run time, sign-based dispatch                 |

```nfql
FROM flows | BETWEEN -3600 AND -60          # 1h ago to 1min ago
FROM flows | BETWEEN -3600 AND *            # last hour
FROM flows | BETWEEN "2026-05-01" AND "2026-05-02"
```

Time stages compose by intersection — mixing `LAST` with `BETWEEN`,
or several `BETWEEN`s, narrows the window.

---

## Parameters (`?`)

Use `?` placeholders for runtime values. They are positional,
left-to-right. The CLI binds them via `--arg`:

```sh
obserae-cli query \
  --arg 443 \
  --arg "10.0.0.0/8" \
  'FROM flows | WHERE dst_port == ? AND src_addr == ?'
```

Why use them?

- **Safety** — values never become part of the SQL string. User
  input can't change the query's structure.
- **Reuse** — the same compiled query runs with different inputs
  without recompilation.

---

## Aggregation: `STATS`, `EVAL`, `HAVING`

`STATS` folds rows into groups and applies aggregate functions:

```
STATS <alias> = <fn>(<arg>) [, <alias> = <fn>(<arg>)]* [BY <col> [, <col>]*]
```

- `<alias>` is **mandatory** — the output column is named after it.
- `<fn>` is one of `COUNT`, `COUNT_DISTINCT`, `SUM`, `AVG`, `MIN`, `MAX`.
- The output schema is the `BY` columns followed by the aliases.
  **Original columns are dropped** — downstream sees the new shape.

```nfql
# Top 20 talker pairs by volume, last hour
FROM flows
  | LAST 3600
  | STATS bytes_total = SUM(bytes), n = COUNT(*) BY src_addr, dst_addr
  | SORT bytes_total DESC
  | LIMIT 20

# Overall traffic in one row
FROM flows
  | LAST 3600
  | STATS total_bytes = SUM(bytes),
          n_flows     = COUNT(*),
          uniq_srcs   = COUNT_DISTINCT(src_addr)
```

`HAVING` filters the aggregated rows:

```nfql
FROM flows
  | LAST 3600
  | STATS n = COUNT(*) BY src_addr
  | HAVING n > 1000
  | SORT n DESC
```

`EVAL` adds computed columns before or after `STATS`:

```nfql
FROM flows
  | LAST 3600
  | STATS bytes = SUM(bytes), pkts = SUM(packets) BY dst_addr
  | EVAL bytes_per_pkt = bytes / pkts
  | SORT bytes_per_pkt DESC
```

---

## Cross-pipeline lookups

The `>` operator chains two pipelines. The right pipeline can
filter (or extend) its rows against a column of the left pipeline.
Use this whenever you have a signal in one table and want to look
up the matching rows in another.

| Keyword       | Result keeps              | Use it for…                                       |
|---------------|---------------------------|----------------------------------------------------|
| `PIVOT`       | current columns only      | "rows of B that match a row of A"                 |
| `PIVOT NOT`   | current columns only      | "rows of B that match *no* row of A"              |
| `JOIN`        | current columns + `prev_*` | "rows of B paired with their A row, both visible" |

Either side of the predicate can be a **virtual column** (`ip`, `port`):
it matches *any* of its real columns. So `… > FROM flows | JOIN ip == ip`
pairs a flow whose **source or destination** equals the other pipeline's
`ip` — handy to find every flow touching a threat IP regardless of
direction.

### Examples

**Top 10 sessions by volume → which rules they matched**

```nfql
FROM sessions          | LAST 3600 | SORT ab_bytes DESC | LIMIT 10
> FROM session_matches | PIVOT session_id == session_id
                       | KEEP rule_id, matched_at
```

**Sessions that matched NO rule** — the canonical anomaly query:

```nfql
FROM session_matches | LAST 3600
> FROM sessions      | LAST 3600 | WHERE state == "closed"
                     | PIVOT NOT session_id == session_id
                     | KEEP ip_a, ip_b, server_ip, role_method
```

**Drill all the way down: matches → sessions → raw flows**

```nfql
FROM session_matches | LAST 3600
> FROM sessions      | PIVOT session_id == session_id
> FROM flows         | PIVOT last_flow_id == flow_id
                     | KEEP src_addr, dst_addr, bytes, packets
                     | LIMIT 100
```

> **Note.** `sessions.last_flow_id` is present for this contract but
> always NULL under the in-memory sessionizer (a flow's id is
> assigned when it is stored, after it has been folded), so the last
> PIVOT step currently returns no rows. To reach the raw flows
> behind a session today, pivot on the endpoints and the session's
> time window instead.

**Sessions whose server is in an AWS range** (CIDR catalogue, `WITHIN`):

```nfql
FROM enrichment_ranges | WHERE source == "aws" | KEEP cidr
> FROM sessions    | PIVOT server_ip WITHIN cidr
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, ab_bytes
```

**Sessions talking to a known threat IP** (insert-time table, `==`) —
an equi-join, so it stays fast on large result sets:

```nfql
FROM enrichment_ips | WHERE nature == "threat" | KEEP ip
> FROM sessions    | PIVOT ip == server_ip
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, ab_bytes
```

---

## Recipes

The recipes below assume you have imported a typical cartography
with `loadbalancers`, `backends`, `databases`, `bastion`, `proxy`
entities.

### Recent traffic to the load balancers on HTTPS

```nfql
FROM flows
  | LAST 3600
  | WHERE ip == "loadbalancers" AND port == 443 AND protocol == TCP
  | KEEP src_addr, dst_addr, bytes
```

### Backends reaching the internet *without* the proxy

```nfql
FROM flows
  | WHERE src_addr == "backends"
        AND (dst_addr == "internet4" OR dst_addr == "internet6")
        AND dst_addr != "host:proxy:eth1"
```

### Top 10 talkers to the database tier

```nfql
FROM flows
  | LAST 3600
  | WHERE dst_addr == "databases"
  | STATS bytes = SUM(bytes) BY src_addr
  | SORT bytes DESC
  | LIMIT 10
```

### SSH attempts that bypassed the bastion

```nfql
FROM flows
  | WHERE port == 22
        AND src_addr != "bastion"
        AND dst_addr != "bastion"
        AND protocol == TCP
```

### Postgres traffic outside the data network

```nfql
FROM flows
  | WHERE port == 5432
        AND ip != "network:data"
        AND protocol == TCP
```

### TCP scans surfaced by the half-open detector

```nfql
FROM sessions
  | WHERE close_reason == "no_reply" AND protocol == TCP
  | KEEP ip_a, ip_b, port_b, opened_at
  | SORT opened_at DESC
```

### Currently active sessions to the database tier

```nfql
FROM sessions
  | WHERE state == "active" AND ip == "databases" AND port == 5432
  | KEEP ip_a, ip_b, ab_pkts, ba_pkts, opened_at
  | SORT opened_at DESC
```

### Closed sessions in an incident window

```nfql
FROM sessions
  | BETWEEN "2026-05-01T12:00:00Z" AND "2026-05-01T12:30:00Z"
  | WHERE ip == "production" AND state == "closed"
  | KEEP ip_a, ip_b, server_ip, server_port, role_method
  | SORT ab_bytes DESC
  | LIMIT 200
```

### Conversations seen by more than one exporter

```nfql
FROM sessions_consolidated
  | WHERE sampler_count > 1
  | KEEP client_ip, server_ip, samplers, min_client_to_server_bytes, max_client_to_server_bytes, coherence_pct
  | SORT coherence_pct ASC
```

A low `coherence_pct` means the exporters disagree on volume —
expected under sampling, drops, or partial visibility on one side.

---

## Reading error messages

NFQL errors carry a `line:column` position pointing at the faulty
token in your source.

| Stage  | Example                                              | Fix                                          |
|--------|------------------------------------------------------|----------------------------------------------|
| `lex`  | `lex: 1:14: unexpected character '@'`                | Drop the stray byte.                         |
| `parse`| `parse: 1:18: expected an expression, got "AND"`     | Missing operand before `AND`.                |
| `sem`  | `sem: 1:18: unknown column "prtocol"`                | Typo on a column name.                       |
| `sem`  | `sem: 1:32: host "srv-typoo": not found`             | Cartography typo, fix in query or topology.  |
| `sem`  | `sem: 1:18: virtual column "ip" does not support <`  | Use `src_addr` / `dst_addr` explicitly.      |

In the GUI, errors are shown inline under the offending token; in
the CLI, they print to stderr with the `line:column` prefix.

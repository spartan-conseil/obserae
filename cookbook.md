# NFQL Cookbook

_Generated from `internal/web/cookbook/cookbook.yaml`. Do not edit by hand — run `make docs`._

## Investigation

### Sessions touching a host (15 min)

**Intent.** Every conversation involving a given host in the recent window.

**When to use.** An external feed flags an IP, or you spotted one in another tool — confirm whether you saw it.

```nfql
FROM sessions
| LAST 900
| WHERE ip == "host:srv-db-01"
| SORT opened_at DESC
| LIMIT 100
```

Cartography refs resolve symbolic names to IP sets at compile time, so the query survives a host renumbering. Forms: `host:NAME` (every interface IP), `group:NAME` (every member host), `network:NAME` (the CIDR).
The virtual `ip` column matches either side of the conversation (`ip_a` OR `ip_b`) — direction does not matter.

**Variants:**

- *By raw IP literal (if the host is not in cartography)*

  ```nfql
  FROM sessions | LAST 900 | WHERE ip == "10.0.0.42" | SORT opened_at DESC
  ```

- *Anywhere inside a CIDR (WITHIN, IPv6-friendly)*

  ```nfql
  FROM sessions | LAST 900 | WHERE ip WITHIN "10.0.0.0/24" | SORT opened_at DESC
  ```

- *Every host in a cartography group*

  ```nfql
  FROM sessions | LAST 3600 | WHERE ip == "group:databases" | SORT opened_at DESC
  ```

- *One of several hosts (set membership)*

  ```nfql
  FROM sessions | LAST 3600 | WHERE ip IN ("host:srv-db-01", "host:srv-db-02") | SORT opened_at DESC
  ```

### Outbound sessions toward the public internet (1h)

**Intent.** Internal hosts that reached external services in the last hour.

**When to use.** Spot exfiltration candidates or unexpected outbound traffic.

```nfql
FROM sessions
| LAST 3600
| WHERE server_ip == "internet4"
| KEEP ip_a, ip_b, server_ip, server_port, ab_bytes, ba_bytes
| SORT ab_bytes DESC
| LIMIT 100
```

`internet4` is a carto-reserved token: every routable IPv4 (everything NOT in RFC1918, loopback, link-local, multicast, reserved). Companions: `internet6`, `internal4`, `internal6`, `any4`, `any6`.
Pair the token with `server_ip` to keep the server-side endpoint — that is the address the operator actually wants to investigate.

**Variants:**

- *From one specific host*

  ```nfql
  FROM sessions | LAST 3600 | WHERE ip == "host:proxy" AND server_ip == "internet4" | KEEP server_ip, server_port, ab_bytes
  ```

- *From the internal network only*

  ```nfql
  FROM sessions | LAST 3600 | WHERE ip == "internal4" AND server_ip == "internet4" | SORT ab_bytes DESC
  ```

- *Toward HTTPS (port + protocol filter together)*

  ```nfql
  FROM sessions | LAST 3600 | WHERE server_ip == "internet4" AND server_port == 443 AND protocol == TCP | SORT ab_bytes DESC
  ```

### Server ports active on the network (1h)

**Intent.** Discover which ports hosts are actually accepting connections on.

**When to use.** Verify that observed services match what is declared in cartography — anything else is an open question.

```nfql
FROM sessions
| LAST 3600
| EVAL total_bytes = ab_bytes + ba_bytes
| STATS n = COUNT(*), bytes = SUM(total_bytes) BY server_ip, server_port
| SORT n DESC
| LIMIT 50
```

`server_ip` is the side the sessionizer inferred as the server; `server_port` is its listening port.
A surprise row (a port you did not declare in cartography) deserves a look. EVAL builds the bidirectional byte total before STATS aggregates it — aggregate functions take a single column, not an expression.

**Variants:**

- *Restrict to one server host*

  ```nfql
  FROM sessions | LAST 3600 | WHERE server_ip == "host:srv-db-01" | STATS n = COUNT(*) BY server_port | SORT n DESC
  ```

### SYN-only TCP flows — connection attempts that never advanced (1h)

**Intent.** TCP flows whose flag set is exactly SYN (no ACK, FIN, RST) — connection openings that did not progress.

**When to use.** Hint at TCP scans, refused connections, or unreachable hosts.

```nfql
FROM flows
| LAST 3600
| WHERE protocol == TCP AND tcp_flags == 2
| STATS n = COUNT(*) BY src_addr, dst_addr, dst_port
| SORT n DESC
| LIMIT 50
```

`tcp_flags` is the cumulative OR of every TCP flag seen during the flow window. The canonical bits are SYN = 2, ACK = 16, FIN = 1, RST = 4, PSH = 8, URG = 32. `tcp_flags == 2` matches flows that ONLY carry SYN — the initial packet of a handshake with no follow-up.
`flows` is the raw surface; for the full conversation use `sessions.ab_flags` / `ba_flags`, where the SYN+ACK pair lives on the opposite side.

### Sessions during a precise time window (incident timeline)

**Intent.** Replay the conversations seen during a 10-minute incident.

**When to use.** Post-mortem or incident response: you know the exact time range and want what happened then.

```nfql
FROM sessions
| BETWEEN "2026-05-27T08:00:00Z" AND "2026-05-27T08:10:00Z"
| WHERE server_ip == "host:srv-db-01"
| SORT opened_at ASC
```

`BETWEEN` accepts ISO-8601 strings (UTC), Unix epoch numbers, `-N` (seconds ago), `now`, or `?` for a bind parameter. Both bounds are inclusive on the lower side, exclusive on the upper.
For a sliding window prefer `LAST <seconds>`; for a fixed forensic window use `BETWEEN`.

## Aggregation

### Top talkers by total bytes (1h)

**Intent.** Rank sources by outbound volume — the primary 'who is heavy on the network' lens.

```nfql
FROM flows
| LAST 3600
| STATS total = SUM(bytes), n = COUNT(*) BY src_addr
| SORT total DESC
| LIMIT 10
```

`STATS` rewrites the row set to one row per group (here `src_addr`) with the aggregate aliases as new columns; the original columns disappear.
Combine `SORT … DESC | LIMIT N` for top-N — the canonical pattern.

**Variants:**

- *Group by pair (source, destination)*

  ```nfql
  FROM flows | LAST 3600 | STATS bytes = SUM(bytes) BY src_addr, dst_addr | SORT bytes DESC | LIMIT 20
  ```

- *Only between hosts inside one network (CIDR scope)*

  ```nfql
  FROM flows | LAST 3600 | WHERE src_addr WITHIN "10.0.0.0/24" AND dst_addr WITHIN "10.0.0.0/24" | STATS bytes = SUM(bytes) BY src_addr | SORT bytes DESC
  ```

### Sessions touching a cloud provider (CIDR-join)

**Intent.** Sessions whose server-side IP falls inside any prefix the enrichment workers have collected for a given source (cloud, threat-intel).

**When to use.** You suspect a host is reaching AWS / Azure / a known-bad IOC range, but you do not want to maintain the CIDR list manually.

```nfql
FROM sessions | LAST 3600 | KEEP server_ip
> FROM enrichment_ranges | WHERE source == "aws" | PIVOT server_ip WITHIN cidr | KEEP cidr, source, details
```

`PIVOT a WITHIN b` is a CIDR-aware semi-join: keep rows of the right pipeline whose `cidr` contains any value of `a` in the left. NFQL uses DuckDB's `<<=` containment operator under the hood, so it is fast even on hundreds of thousands of prefixes.
Swap to `JOIN server_ip WITHIN cidr` if you want the left columns surfaced as `prev_*` (useful to attribute each match back to its session).

### Possible port scan (distinct dst ports per source)

**Intent.** Sources contacting many distinct destination ports — the classic horizontal scan signal.

**When to use.** Triage suspicious activity; tune the `> 20` threshold to your environment.

```nfql
FROM flows
| LAST 3600
| STATS uniq_dst_ports = COUNT_DISTINCT(dst_port) BY src_addr
| HAVING uniq_dst_ports > 20
| SORT uniq_dst_ports DESC
| LIMIT 20
```

`COUNT_DISTINCT` counts unique values inside a group — heavier than `COUNT(*)`, use it only when uniqueness matters.
`HAVING` filters after `STATS` (raw-row filters use `WHERE`).

### Flows per minute (time histogram, 1h)

**Intent.** Flow rate over time — drives anomaly detection and shift baselines.

```nfql
FROM flows
| LAST 3600
| EVAL minute = BUCKET(time_received, 60)
| STATS n = COUNT(*), bytes_total = SUM(bytes) BY minute
| SORT minute ASC
```

`BUCKET(col, secs)` truncates a timestamp to its bucket of width `secs`.
Append `EVAL` then `STATS BY` on the bucket alias to build any histogram.

**Variants:**

- *Hourly instead of per-minute*

  ```nfql
  FROM flows | LAST 86400 | EVAL hour = BUCKET(time_received, 3600) | STATS n = COUNT(*) BY hour | SORT hour ASC
  ```

### Possible exfiltration: high bytes-per-packet ratio

**Intent.** Sources whose flows are unusually large per packet — bulk transfer signature.

```nfql
FROM flows
| LAST 3600
| EVAL bpp = bytes / packets
| STATS avg_bpp = AVG(bpp), total = SUM(bytes) BY src_addr
| HAVING avg_bpp > 1000
| SORT total DESC
| LIMIT 20
```

Division is null-safe in NFQL: `a / b` rewrites to `a / NULLIF(b, 0)`, no divide-by-zero crash.
`AVG` truncates fractional results — for precision, use `SUM(x) / COUNT(*)` instead.

## Detection

### Recent rule matches with rule name (1h)

**Intent.** Every detection that fired in the last hour, with the rule name resolved.

**When to use.** Triage: which detections are active right now, and which sessions did they hit.

```nfql
FROM session_matches | LAST 3600
> FROM rules | PIVOT rule_id == rule_id | KEEP name, description, tags
```

`session_matches` carries `rule_id` only (UUID); the `rules` table holds the human name.
The cascade pivots the match set into the rules catalogue and projects the readable columns.

**Variants:**

- *Count matches per rule (top-N noisiest)*

  ```nfql
  FROM session_matches | LAST 3600 | STATS n = COUNT(*) BY rule_id | SORT n DESC | LIMIT 10
  ```

- *Match + session detail via inner JOIN (prev_* columns)*

  ```nfql
  FROM session_matches | LAST 3600 | KEEP session_id, rule_id
  > FROM sessions | LAST 3600 | KEEP session_id, server_ip, server_port
  | JOIN session_id == session_id | KEEP prev_rule_id, server_ip, server_port
  ```

### Sessions that triggered a specific rule (by name)

**Intent.** Find every session matched by a rule, given the human name (not the UUID).

**When to use.** A detection name appeared in an alert and you want the underlying traffic.

```nfql
FROM rules | WHERE name == "prod-ssh-allow" | KEEP rule_id
> FROM session_matches | LAST 86400 | PIVOT rule_id == rule_id
> FROM sessions | PIVOT session_id == session_id | KEEP opened_at, ip_a, ip_b, server_ip, server_port
```

Three-pipeline cascade: filter `rules` by name, pivot the surviving `rule_id`s into `session_matches`, then pivot the resulting `session_id`s into `sessions` to recover the traffic.
Each `>` introduces a new pipeline whose PIVOT references the previous pipeline's terminal CTE — efficient single semi-joins all the way down.

### Closed sessions that matched no rule (1h)

**Intent.** Conversations the rules do NOT cover — the detection-gap surface.

**When to use.** Looking for traffic that bypasses every detection: the typical 'shadow IT' or undeclared service hunt.

```nfql
FROM session_matches | LAST 3600
> FROM sessions | LAST 3600 | PIVOT NOT session_id == session_id | KEEP ip_a, ip_b, server_ip, server_port
```

`PIVOT NOT` is an anti-semi-join: keep right rows whose key is NOT in the left.
Both sides must filter on the same time window or the anti-join slides under it.

**Variants:**

- *Same, restricted to one network (CIDR + anti-join)*

  ```nfql
  FROM session_matches | LAST 3600
  > FROM sessions | LAST 3600 | WHERE server_ip WITHIN "10.0.0.0/24" | PIVOT NOT session_id == session_id | KEEP server_ip, server_port
  ```

## Aide-Mémoire

### FROM <table>

**Intent.** Open a pipeline on a table. Tables: flows, sessions, session_matches, sessions_consolidated, sessions_dead_letter, enrichment_ranges, enrichment_ips, rules.

```nfql
FROM <table>
```

Every pipeline starts with FROM. Chain with `|` for filters/projection, or `>` for a cross-pipeline cascade.

### WHERE <pred>

**Intent.** Filter rows by a boolean predicate, before any aggregation.

```nfql
FROM <table> | WHERE <pred>
```

Comparators: `==` `!=` (any type); `<` `<=` `>` `>=` (numeric, timestamp, varchar).
Set membership: `col IN (a, b, …)`.
Combinators: `AND` `OR` `NOT`, with standard precedence — parenthesise to disambiguate.
INET: `col WITHIN "CIDR"` for containment; `==` on a CIDR literal becomes containment too.
Integer fields (e.g. `tcp_flags`) support equality and ordering only — no bitwise operators yet.

### LAST / BETWEEN

**Intent.** Filter on the table's time column. `LAST N` keeps the last N seconds; `BETWEEN a AND b` is an explicit window.

```nfql
FROM <table> | LAST 3600   -- last hour
```

Bounds accept Unix epoch, -N (seconds ago), ISO strings, `now`, or `?` for a bind parameter.

### KEEP / SORT / LIMIT

**Intent.** Project, order and cap. Place these near the end of the pipeline; together they form the top-N idiom.

```nfql
… | KEEP col1, col2 | SORT col1 DESC | LIMIT 50
```

`SORT` defaults to ASC. `LIMIT` without `SORT` returns an arbitrary slice — pair them.

### STATS <alias> = <fn>(<col>) BY <col>, …

**Intent.** Aggregate. Produces a NEW schema = the BY columns + the aggregate aliases; original columns are dropped.

```nfql
FROM flows | STATS total = SUM(bytes), n = COUNT(*) BY src_addr
```

Functions: `COUNT(*)`, `COUNT(col)`, `COUNT_DISTINCT(col)`, `SUM`, `AVG`, `MIN`, `MAX`. Filter aggregates with `HAVING` (not `WHERE`).

### EVAL <alias> = <expr>

**Intent.** Append computed columns. Aliases must not collide with existing column names.

```nfql
… | EVAL bpp = bytes / packets, minute = BUCKET(time_received, 60)
```

Division is null-safe: `a / b` rewrites to `a / NULLIF(b, 0)`. `BUCKET(timestamp, secs)` truncates to a fixed-width bucket — the building block of histograms.

### PIVOT / JOIN cascades (with `>`)

**Intent.** Chain two pipelines: the second references the first via a key. PIVOT is semi-join (rows survive), JOIN is inner equi-join (left columns surface as `prev_*`).

```nfql
<pipe1> > <pipe2> | PIVOT <col_b> == <col_a>
```

Five connector forms after `>`:
`PIVOT a == b` — semi-join (right rows whose `b` is in left's `a`).
`PIVOT NOT a == b` — anti-semi-join (right rows whose `b` is NOT in left).
`PIVOT a WITHIN cidr_col` — CIDR containment semi-join (left IP inside right CIDR).
`JOIN a == b` — inner equi-join, left columns surface as `prev_*`.
`JOIN a WITHIN cidr` — inner CIDR-join, same `prev_*` convention.
Chain N pipelines: each `>` references its immediate predecessor only.

### Cartography references inside `WHERE`

**Intent.** Resolve symbolic names to IP sets at compile time — no need to know the IPs.

```nfql
FROM sessions | WHERE ip == "host:srv-db-01"
```

Symbolic name forms (always quoted, always with the `kind:` prefix):
`host:NAME` — every interface IP of the host.
`host:NAME:IFACE` — one specific interface (when a host has several).
`group:NAME` — every IP of every member host (recursive).
`network:NAME` — the network's CIDR.
`NAME` — bare name, resolved by lookup across hosts/groups/networks.
Reserved tokens (unquoted, no prefix): `any4`, `any6` (everything); `internet4`, `internet6` (routable public); `internal4`, `internal6` (private space).
All forms also work with `WITHIN`, `IN (…)`, `!=`.

### Keyboard shortcuts

**Intent.** Make the editor fast.

```nfql
Ctrl+Enter run • Ctrl+Space force autocomplete • Tab/Enter accept • ↑↓ navigate • Esc dismiss
```

Click on a result cell to append a `WHERE` filter at the caret. Right-click for ==, !=, sort, copy.


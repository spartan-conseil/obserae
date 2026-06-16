# Configuration

obserae reads configuration from three sources, in increasing priority:

1. **Built-in defaults** — sane values for every key.
2. **YAML file** — passed with `--config <path>`.
3. **CLI flags** — override the corresponding YAML key.

A missing YAML key falls back to the default. A missing file is not
an error — defaults apply.

---

## The simplest config

```yaml
listen:
  netflow:
    enabled: true
    address: "0.0.0.0:2055"
  ipfix:
    enabled: true
    address: "0.0.0.0:4739"

storage:
  data_dir: "./data"
  duckdb_path: "./data/obserae.duckdb"

buffer:
  max_records: 10000
  max_age: 5s

control:
  socket: "./data/obserae.sock"

web:
  enabled: true
  address: "127.0.0.1:8080"
```

Everything else uses defaults. Read on for the full reference and
tuning recipes.

---

## Full YAML reference

```yaml
listen:
  # One UDP socket per flow protocol, each enabled/disabled and bound
  # independently. Run a NetFlow-only or IPFIX-only collector by toggling
  # 'enabled'. At least one protocol must stay enabled.
  netflow:                    # NetFlow v5 and v9
    enabled: true
    address: "0.0.0.0:2055"   # NetFlow commonly uses 2055
  ipfix:                      # IPFIX ("NetFlow v10")
    enabled: true
    address: "0.0.0.0:4739"   # IPFIX commonly uses 4739

decoder:
  # Reserved for future per-exporter sharding. Set to 0 (default).
  workers: 0

buffer:
  # Flush a parquet file when EITHER threshold is reached.
  max_records: 10000          # records accumulated in memory
  max_age: 5s                 # time since the first record of the batch

storage:
  # Root directory for on-disk table data. Each parquet-backed table gets its
  # own directory under this root, named after the table (<data_dir>/flows,
  # <data_dir>/ip_enrichment, …). Only this root is configurable.
  data_dir: "./data"
  # Path to the DuckDB database file (created on first run).
  duckdb_path: "./data/obserae.duckdb"

  # Size of the read-only connection pool used by the web GUI and
  # the NFQL query handler. Increase if heavy queries slow the GUI.
  reader_conns: 4

  # Cap DuckDB's memory (MB). 0 = its default of ≈80% of RAM. The key
  # knob for bounding memory on a small host — see operations.md
  # "Memory usage keeps climbing". Pair with retention.
  memory_limit_mb: 0
  max_threads: 0      # DuckDB worker threads; 0 = one per core

control:
  # Unix socket for obserae-cli. /var/run/obserae.sock needs root or
  # a writable /var/run; for development point it inside the project.
  socket: "/var/run/obserae.sock"

web:
  # HTTP server that serves the GUI to a browser. Distinct from the
  # control socket: the socket is the privileged admin API; this is
  # the read surface for the web UI.
  enabled: true

  # Bind address. 127.0.0.1 keeps the GUI on the loopback only.
  # ONLY switch to 0.0.0.0 behind a reverse proxy doing TLS + auth.
  address: "127.0.0.1:8080"

  # How often the cockpit health snapshot is pushed.
  health_interval: 2s

  # Hosts with no session activity newer than this are greyed out
  # on the cartography graph.
  carto_inactivity_threshold: 24h

  # Secure flag on the session cookie. Leave unset (auto): a non-loopback
  # bind (0.0.0.0, e.g. Docker) marks the cookie Secure, as does a proxy's
  # X-Forwarded-Proto: https. Set true to force it always.
  #
  # Set FALSE only for a deliberate plain-HTTP deployment. Symptom if you
  # don't: reaching the GUI over plain http:// from a remote IP makes the
  # login loop back to itself (the browser drops the Secure cookie; only
  # localhost is exempt). With false, login works over HTTP but the cookie
  # travels unprotected — trusted networks only.
  # secure_cookies: false

matcher:
  # Cadence of the rule-matcher engine. Each tick is a single
  # transaction (join closed sessions × rule expansions).
  interval: 30s

alerts:
  # NFQL-based alerting. Each rule runs on its own cadence; poll_interval
  # is just how often obserae checks which rules are due. See alerting.md.
  poll_interval: 10s
  tick_timeout: 120s
  eval_max_rows: 10000
  runs_per_rule: 50
  budget_factor: 0.8

outputs:
  # Delivery of alerts to webhook / Gotify destinations. The destinations
  # are managed on the Outputs page; these knobs tune how the background
  # dispatcher retries. See outputs.md.
  dispatch_interval: 5s
  attempt_timeout: 10s
  max_attempts: 10
  backoff_base: 5s
  backoff_max: 1h
  delivery_retention: 168h   # forget delivered/dead rows after 7 days
  # SSRF guard: by default the daemon refuses to deliver to internal
  # destinations (loopback, 10/172.16/192.168, 169.254.x cloud metadata,
  # IPv6 ULA, multicast). Allowlist a legitimate internal target by CIDR.
  egress_block_internal: true
  egress_allow_cidrs: []     # e.g. ["10.0.0.0/8"] for a LAN Gotify

sessions:
  # Cadence of the session-consolidation engine.
  interval: 10s

  # GRACE_PERIOD: a flow whose `time_received` is younger than
  # `now - grace` is held back, assuming more records may still
  # arrive for the same conversation.
  grace: 30s

  # HARD_TIMEOUT: a still-active session becomes visible to
  # operators after this delay even if it hasn't closed yet.
  # Keeps long sessions as ONE row.
  hard_timeout: 15m

  # Cap on how many sessions may be open at once, in THOUSANDS
  # (500 = 500_000). Open sessions live in memory; when the cap is
  # reached the oldest are force-closed (close_reason='capacity')
  # so memory stays bounded under a scan or flood.
  max_open_ksessions: 500

  # Idle timeouts — when an open session closes for lack of new
  # packets. Tuned per protocol.
  idle:
    tcp_established: 60s
    tcp_half_open: 5s          # short on purpose: scans surface fast
    udp: 30s
    icmp: 10s
    other: 60s

correlation:
  # Groups the per-exporter sessions of one conversation (the same
  # 5-tuple seen by a switch AND a firewall) under a shared
  # correlation_id, exposed via the sessions_consolidated table. Pure
  # overlay — per-exporter rows are untouched, so no double-counting.
  enabled: true
  # Slack on the conversation-time overlap test. Matched on the FLOW
  # clock (when the conversation happened), not record reception: two
  # exporters flush the same conversation tens of seconds apart, so this
  # absorbs inter-exporter clock skew. 0 requires a strict overlap.
  window: 60s
  # How far back the correlator looks for an already-closed peer. A peer
  # closed before (batch flow start − window − horizon) cannot overlap,
  # so it is skipped — this is what keeps the correlation step's cost
  # bounded (independent of how many sessions the table holds) instead of
  # scanning all history. Default 16m (≈ hard_timeout + grace + margin).
  # Raise it only if exporters flush the SAME conversation more than this
  # far apart and you see groups fragmenting; lower it on a very busy,
  # tightly-synchronised fleet to scan even less.
  horizon: 16m

enrichment:
  # Number of distinct IPs the insert-time enrichment resolver
  # remembers (LRU). ~32 B each, so 1_000_000 ≈ 32 MB. Higher = fewer
  # repeat lookups on high-cardinality traffic; lower = less memory.
  cache_size: 1000000
  # Refresh stale / never-fetched sources at boot instead of waiting
  # for the first hourly tick. Default true.
  fetch_on_startup: true

retention:
  # Periodic purge of stale rows from `flows` and `sessions`. Off by
  # default — the daemon never auto-evicts data unless you opt in.
  # See lifecycle.md for the full guide; the GUI's Lifecycle page can
  # also flip these knobs at runtime without restarting the daemon.
  # Those GUI edits are PERSISTED (in the app_settings table) and
  # survive a restart — at boot the daemon layers app_settings over
  # the values below, so this YAML is only the initial default.
  enabled: false
  flows_max_age: 720h       # 30 days; 0 = do not purge flows
  sessions_max_age: 2160h   # 90 days; 0 = do not purge sessions
  interval: 1h              # sweep cadence
  # Rows deleted per statement. The runner loops until the set is
  # drained, so this never caps the purge — it only bounds how long any
  # single DELETE holds the writer connection (shared with ingestion).
  # Purging sessions also cascades to sessions_correlation (orphans).
  batch_size: 50000

backup:
  # Periodic native DuckDB snapshot of the whole database. Off by
  # default. Files land under `directory`. Both rotation knobs
  # (max_age, max_files) can apply together. As with retention, GUI
  # edits to these knobs persist in app_settings across restarts.
  enabled: false
  directory: "./data/backups"
  interval: 24h             # cadence; runtime-immutable
  max_age: 720h             # rotation by age; 0 = keep forever
  max_files: 0              # rotation by count; 0 = no count cap

logging:
  # 0 = INFO   (default — daemon-level events)
  # 1 = DEBUG  (per-flush, per-insert, per-tick)
  # 2 = DEBUG + file:line in every record
  # 3 = TRACE  (per-packet, very chatty — diagnostics only)
  verbosity: 0

debug:
  # Long-run memory diagnostics. See operations.md → "Memory usage
  # keeps climbing". pprof is OFF by default (unauthenticated, keep it
  # on localhost); the memstats log line is ON every 5 minutes.
  pprof_enabled: false
  pprof_address: "127.0.0.1:6060"
  memstats_interval: 5m         # 0 disables the periodic memory log
```

---

## CLI flags

`./obserae -h` accepts the following flags. Each one overrides the
corresponding YAML key.

| Flag                       | Type         | Overrides              | Default                  |
|----------------------------|--------------|------------------------|--------------------------|
| `--config FILE`            | path         | —                      | empty                    |
| `--listen ADDR`            | host:port    | `listen.netflow.address` | `0.0.0.0:2055`         |
| `--listen-ipfix ADDR`      | host:port    | `listen.ipfix.address` | `0.0.0.0:4739`           |
| `--disable-netflow`        | bool         | `listen.netflow.enabled` | enabled                |
| `--disable-ipfix`          | bool         | `listen.ipfix.enabled` | enabled                  |
| `--buffer-max-records N`   | int (>0)     | `buffer.max_records`   | 10000                    |
| `--buffer-max-age D`       | Go duration  | `buffer.max_age`       | `5s`                     |
| `--data-dir DIR`           | path         | `storage.data_dir`     | `./data`                 |
| `--duckdb PATH`            | path         | `storage.duckdb_path`  | `./data/obserae.duckdb`  |
| `--control-socket PATH`    | path         | `control.socket`       | `/var/run/obserae.sock`  |
| `--workers N`              | int          | `decoder.workers`      | 0                        |
| `-v` / `-vv` / `-vvv`      | counter      | `logging.verbosity`    | 0                        |

Durations follow Go conventions: `30s`, `2m`, `1h30m`, etc.

---

## Validation

The daemon refuses to start if any of these fails:

- No listener is enabled (`listen.netflow` and `listen.ipfix` both disabled), or an enabled protocol's `address` is empty.
- `buffer.max_records` or `buffer.max_age` ≤ 0.
- `storage.data_dir` is empty.
- `storage.duckdb_path` is empty.
- `storage.memory_limit_mb` or `storage.max_threads` < 0.
- `control.socket` is empty.
- `matcher.interval` ≤ 0.
- `sessions.interval`, `sessions.grace`, `sessions.hard_timeout` ≤ 0.
- `sessions.max_open_ksessions` ≤ 0.
- Any `sessions.idle.*` value ≤ 0.
- `correlation.window` < 0 or `correlation.horizon` < 0 (when `correlation.enabled`).
- `enrichment.cache_size` ≤ 0.
- `logging.verbosity` < 0.
- `debug.pprof_address` is empty while `debug.pprof_enabled` is true.
- `debug.memstats_interval` < 0.

Better to fail loud at startup than to ingest data with a
half-configured pipeline.

---

## Configuration recipes

### Production — unprivileged service

```yaml
listen:
  netflow:
    enabled: true
    address: "0.0.0.0:2055"
control:
  socket: "/var/lib/obserae/run/obserae.sock"
storage:
  data_dir: "/var/lib/obserae/data"
  duckdb_path: "/var/lib/obserae/db/obserae.duckdb"
web:
  address: "127.0.0.1:8080"
logging:
  verbosity: 0
```

Make `/var/lib/obserae` owned by an `obserae` system user, run the
daemon under that user, and front the web GUI with nginx/Caddy if
you need TLS or remote access. See [operations.md](operations.md)
for the systemd unit.

### High-traffic site

```yaml
buffer:
  max_records: 100000          # bigger parquet files, fewer INSERTs
  max_age: 10s                 # accept up to 10s of latency
matcher:
  interval: 1m                 # detection once per minute is plenty
storage:
  reader_conns: 8              # more parallel read queries
```

### Low-latency detection

```yaml
buffer:
  max_records: 1000            # smaller files, more frequent INSERTs
  max_age: 1s
matcher:
  interval: 5s                 # near-real-time matches
sessions:
  interval: 3s
  grace: 10s                   # tighter — some late arrivals will be dropped
```

This trades throughput and disk churn for sub-10s detection latency.

### Fast scan / probe detection

```yaml
sessions:
  idle:
    tcp_half_open: 2s          # scans surface faster
```

2s is aggressive but useful when scan detection is the priority.
The trade-off: slow-handshake legitimate connections may be marked
as half-open closures.

### Expose the web GUI on the network

The default `127.0.0.1:8080` keeps the GUI on the loopback. To
reach it from another machine:

```yaml
web:
  address: "0.0.0.0:8080"
```

**Then put a reverse proxy doing TLS in front.** obserae serves plain
HTTP and has no built-in TLS. Without a proxy terminating HTTPS, the
GUI travels in clear over the network.

A minimal Caddy config (terminates TLS, forwards the scheme):

```caddyfile
obserae.example.com {
    reverse_proxy localhost:8080
}
```

Caddy automatically sends `X-Forwarded-Proto: https`, so obserae marks
the session cookie `Secure` and login works.

> **Login loops back to itself over plain HTTP?** When the bind is
> non-loopback (`0.0.0.0`), obserae marks the session cookie `Secure` by
> default — and browsers **drop** a `Secure` cookie received over plain
> `http://` from a remote IP, so the login silently loops (localhost is
> exempt, which is why it works locally). Either front it with TLS as
> above, or, for a trusted plain-HTTP LAN deployment, set
> `web.secure_cookies: false` (the cookie is then sent unprotected).

### Quiet vs verbose logs

```yaml
logging:
  verbosity: 0                 # INFO — production default
```

For triage, bump per-run with `-v` flags:

```sh
./obserae --config obserae.yaml -vv
```

The `-v*` flags only ever raise the floor; they never silence
something the YAML enabled.

---

## Where each setting takes effect

| Setting                 | Read at startup | Hot-reloadable | Notes                                                           |
|-------------------------|-----------------|----------------|-----------------------------------------------------------------|
| `listen.netflow.*`, `listen.ipfix.*` | yes | no | Daemon must restart to rebind. |
| `buffer.*`              | yes             | no             | Flush thresholds fixed at startup.                              |
| `storage.duckdb_path`   | yes             | no             | Changing it on a live install starts a new empty database.      |
| `control.socket`        | yes             | no             | Recreated on every start.                                       |
| `web.*`                 | yes             | no             | Restart to rebind.                                              |
| `matcher.interval`      | yes             | no             | Restart applies the new cadence.                                |
| `sessions.*`            | yes             | no             | Restart applies new cadence / cutoffs.                          |
| `enrichment.cache_size` | yes             | no             | Sizes the resolver LRU at startup.                              |
| `logging.verbosity`     | yes             | no             | Use `-v*` flags for an ad-hoc bump.                             |

There is no SIGHUP-driven reload yet — restart for configuration
changes. **Cartography and rules mutate live** via the CLI or the
GUI; no daemon restart needed for those.

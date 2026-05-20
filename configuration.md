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
  address: "0.0.0.0:2055"

storage:
  duckdb_path: "./data/obserae.duckdb"

buffer:
  directory: "./data/parquet"

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
  # UDP socket the collector binds. NetFlow v5/v9 commonly use 2055.
  address: "0.0.0.0:2055"

decoder:
  # Reserved for future per-exporter sharding. Set to 0 (default).
  workers: 0

buffer:
  # Flush a parquet file when EITHER threshold is reached.
  max_records: 10000          # records accumulated in memory
  max_age: 5s                 # time since the first record of the batch

  # Where short-lived parquet files queue up before insertion.
  # They are deleted immediately after a successful INSERT.
  directory: "./data/parquet"

storage:
  # Path to the DuckDB database file (created on first run).
  duckdb_path: "./data/obserae.duckdb"

  # Size of the read-only connection pool used by the web GUI and
  # the NFQL query handler. Increase if heavy queries slow the GUI.
  reader_conns: 4

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

matcher:
  # Cadence of the rule-matcher engine. Each tick is a single
  # transaction (join closed sessions × rule expansions).
  interval: 30s

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

  # Idle timeouts — when an open session closes for lack of new
  # packets. Tuned per protocol.
  idle:
    tcp_established: 60s
    tcp_half_open: 5s          # short on purpose: scans surface fast
    udp: 30s
    icmp: 10s
    other: 60s

logging:
  # 0 = INFO   (default — daemon-level events)
  # 1 = DEBUG  (per-flush, per-insert, per-tick)
  # 2 = DEBUG + file:line in every record
  # 3 = TRACE  (per-packet, very chatty — diagnostics only)
  verbosity: 0
```

---

## CLI flags

`./obserae -h` accepts the following flags. Each one overrides the
corresponding YAML key.

| Flag                       | Type         | Overrides              | Default                  |
|----------------------------|--------------|------------------------|--------------------------|
| `--config FILE`            | path         | —                      | empty                    |
| `--listen ADDR`            | host:port    | `listen.address`       | `0.0.0.0:2055`           |
| `--buffer-max-records N`   | int (>0)     | `buffer.max_records`   | 10000                    |
| `--buffer-max-age D`       | Go duration  | `buffer.max_age`       | `5s`                     |
| `--buffer-dir DIR`         | path         | `buffer.directory`     | `./data/parquet`         |
| `--duckdb PATH`            | path         | `storage.duckdb_path`  | `./data/obserae.duckdb`  |
| `--control-socket PATH`    | path         | `control.socket`       | `/var/run/obserae.sock`  |
| `--workers N`              | int          | `decoder.workers`      | 0                        |
| `-v` / `-vv` / `-vvv`      | counter      | `logging.verbosity`    | 0                        |

Durations follow Go conventions: `30s`, `2m`, `1h30m`, etc.

---

## Validation

The daemon refuses to start if any of these fails:

- `listen.address` is empty.
- `buffer.max_records` or `buffer.max_age` ≤ 0.
- `buffer.directory` is empty.
- `storage.duckdb_path` is empty.
- `control.socket` is empty.
- `matcher.interval` ≤ 0.
- `sessions.interval`, `sessions.grace`, `sessions.hard_timeout` ≤ 0.
- Any `sessions.idle.*` value ≤ 0.
- `logging.verbosity` < 0.

Better to fail loud at startup than to ingest data with a
half-configured pipeline.

---

## Configuration recipes

### Production — unprivileged service

```yaml
listen:
  address: "0.0.0.0:2055"
control:
  socket: "/var/lib/obserae/run/obserae.sock"
storage:
  duckdb_path: "/var/lib/obserae/db/obserae.duckdb"
buffer:
  directory: "/var/lib/obserae/parquet"
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

**Then put a reverse proxy in front.** obserae has no built-in
authentication or TLS. Without a proxy doing both, the GUI is open
to anyone who can reach the port.

A minimal Caddy config:

```caddyfile
obserae.example.com {
    reverse_proxy localhost:8080
    basicauth /* {
        admin <htpasswd-hash>
    }
}
```

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
| `listen.address`        | yes             | no             | Daemon must restart to rebind.                                  |
| `buffer.*`              | yes             | no             | Flush thresholds fixed at startup.                              |
| `storage.duckdb_path`   | yes             | no             | Changing it on a live install starts a new empty database.      |
| `control.socket`        | yes             | no             | Recreated on every start.                                       |
| `web.*`                 | yes             | no             | Restart to rebind.                                              |
| `matcher.interval`      | yes             | no             | Restart applies the new cadence.                                |
| `sessions.*`            | yes             | no             | Restart applies new cadence / cutoffs.                          |
| `logging.verbosity`     | yes             | no             | Use `-v*` flags for an ad-hoc bump.                             |

There is no SIGHUP-driven reload yet — restart for configuration
changes. **Cartography and rules mutate live** via the CLI or the
GUI; no daemon restart needed for those.

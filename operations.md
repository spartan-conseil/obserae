# Running obserae in production

This page is for the person running obserae as a service: where
files live, how to deploy, what to monitor, what to back up, what
to do when something looks wrong.

For interactive use and learning, start with
[quickstart.md](quickstart.md). For installation alone, see
[installation.md](installation.md).

---

## Filesystem layout

obserae owns three areas of disk in a production install:

```
/etc/obserae/obserae.yaml          # configuration (you author this)

/var/lib/obserae/                  # the daemon owns everything below
   db/obserae.duckdb               # the database file
   parquet/                        # short-lived parquet buffer
   run/obserae.sock                # the control socket (mode 0600)
```

`parquet/` grows under load and shrinks again as files get
inserted. Empty there is the steady state — files accumulate when
the inserter is behind.

---

## Deploying as a systemd service

### 1. Install the binaries

If you extracted the release tarball:

```sh
sudo install -m 0755 obserae      /usr/local/bin/
sudo install -m 0755 obserae-cli  /usr/local/bin/
```

### 2. Create a system user and the data area

```sh
sudo useradd --system --home /var/lib/obserae --shell /usr/sbin/nologin obserae
sudo install -d -o obserae -g obserae -m 0750 \
    /var/lib/obserae \
    /var/lib/obserae/db \
    /var/lib/obserae/parquet \
    /var/lib/obserae/run
```

### 3. Drop a config

```sh
sudo install -d -m 0755 /etc/obserae
sudo tee /etc/obserae/obserae.yaml > /dev/null <<'YAML'
listen:
  address: "0.0.0.0:2055"
control:
  socket: "/var/lib/obserae/run/obserae.sock"
storage:
  duckdb_path: "/var/lib/obserae/db/obserae.duckdb"
buffer:
  directory: "/var/lib/obserae/parquet"
web:
  enabled: true
  address: "127.0.0.1:8080"        # behind a reverse proxy for TLS+auth
matcher:
  interval: 30s
logging:
  verbosity: 0
YAML
```

See [configuration.md](configuration.md) for the full reference.

### 4. Install the unit

```sh
sudo tee /etc/systemd/system/obserae.service > /dev/null <<'EOF'
[Unit]
Description=obserae NetFlow collector
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=obserae
Group=obserae
ExecStart=/usr/local/bin/obserae --config /etc/obserae/obserae.yaml
Restart=on-failure
RestartSec=5

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/obserae
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now obserae
sudo journalctl -u obserae -f
```

The daemon listens on UDP/2055. If you must use a privileged port,
grant `CAP_NET_BIND_SERVICE` in the unit (`AmbientCapabilities=…`,
`CapabilityBoundingSet=…`).

---

## Exposing the web GUI

The default `web.address: 127.0.0.1:8080` keeps the GUI on the
loopback. **obserae has no built-in authentication or TLS.** To
let operators reach it from the network, put a reverse proxy in
front.

Minimal Caddy example:

```caddyfile
obserae.example.com {
    reverse_proxy localhost:8080
    basicauth /* {
        admin <htpasswd-hash>
    }
}
```

Minimal nginx example:

```nginx
server {
    listen 443 ssl;
    server_name obserae.example.com;
    ssl_certificate     /etc/letsencrypt/live/obserae.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/obserae.example.com/privkey.pem;

    auth_basic           "obserae";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";    # WebSocket support
        proxy_set_header   Host       $host;
    }
}
```

The `Upgrade` / `Connection` headers are required — the cockpit and
cartography pages stream live data via WebSocket.

---

## Granting CLI access to operators

The CLI dials the same Unix socket as the daemon owns. Either add
operators to the `obserae` group:

```sh
sudo usermod -aG obserae alice
# log out / log in for the group to take effect

obserae-cli --socket /var/lib/obserae/run/obserae.sock status
```

…or set a shell alias they can copy into their shell rc:

```sh
alias obserae-cli='/usr/local/bin/obserae-cli --socket /var/lib/obserae/run/obserae.sock'
```

---

## Monitoring

`obserae-cli status --json` is the canonical health datapoint. Plug
it into your metrics stack:

```sh
obserae-cli --socket /var/lib/obserae/run/obserae.sock status --json
```

```json
{
  "version": "v1.2.0",
  "commit":  "fe2bc84",
  "started_at":     "2026-04-29T08:12:33Z",
  "uptime_seconds": 3742,
  "flow_count":     1284091,
  "networks": 5, "hosts": 11, "services": 23, "groups": 6,
  "rules":    10, "expansions": 1462,
  "sessions_active":     124,
  "sessions_half_open":  3,
  "sessions_closed":     8945
}
```

Useful checks to script:

| Check                                                                 | Signal                                                                            |
|-----------------------------------------------------------------------|------------------------------------------------------------------------------------|
| `flow_count` not increasing                                           | Exporter not sending, port firewalled, or pipeline stuck                          |
| Parquet files older than 1 minute in `buffer.directory`               | Inserter is stuck (DuckDB or disk problem)                                        |
| Any rule with non-empty `last_compile_error`                          | Cartography mutation broke a rule reference                                       |
| Steady growth in matches for an alert rule                            | Detection actually firing                                                         |
| `sessions_active + sessions_half_open` climbing across many ticks     | Sessions opening but never closing — check FIN/RST observability or timeouts      |
| `sessions_half_open` ≫ `sessions_active`                              | Asymmetric capture (firewall drops?) or scan storm — both worth alerting          |
| Non-zero `sessions_dead_letter` count in the last hour                | Late arrivals — typically exporter clock drift or `grace` tuned too short         |

A simple parquet-backlog check:

```sh
find /var/lib/obserae/parquet -name '*.parquet' -mmin +1 -print | wc -l
```

---

## Backups

Two things to back up:

1. **The DuckDB file** at `storage.duckdb_path`. It carries
   `flows`, `sessions`, `session_matches`, the cartography, the
   rules, and the enrichment ranges. For a hot backup, rely on
   DuckDB's WAL — `cp obserae.duckdb obserae-YYYYMMDD.duckdb` while
   the daemon is idle is safe. For maximum safety, stop the daemon,
   copy, restart.

2. **Your authored content** — the cartography and the rules:

   ```sh
   obserae-cli cartography export > /var/backups/obserae/$(date +%F).carto.yml
   obserae-cli rules export       > /var/backups/obserae/$(date +%F).rules.yml
   ```

   These two YAMLs are enough to rebuild the topology and the rule
   set on a fresh daemon. The `flows` history itself is only in the
   DuckDB file.

A daily cron job that exports both YAMLs is the operator's safety
net for the symbolic state.

---

## Troubleshooting

### `no such file or directory: /var/run/obserae.sock`

Daemon not running, or the configured socket path differs from the
CLI's. Check `sudo systemctl status obserae` and the
`control.socket` setting.

### Parquet files pile up

The inserter is behind. Most likely cause: the DuckDB file is on a
slow or full disk, or another process holds it open.

```sh
lsof | grep obserae.duckdb
df -h /var/lib/obserae
```

The buffer directory is uncapped — operators are expected to
monitor disk usage. A `df` threshold alert is the right tool.

### A rule fires too much / too little

Drill down before you change the rule:

```sh
obserae-cli matches ls --rule X --since 1h           # what's it catching?
obserae-cli rule show X                              # what does it expand to?
obserae-cli query 'FROM flows | LAST 3600 | WHERE …' # what's actually arriving?
```

- Rule **not expansive enough** → enrich the cartography (add hosts
  to the group), not the rule.
- Rule **too expansive** → scope it (`dst_iface`, narrow
  `dst_service`, switch from `group:` to `host:`).

### `rule X: not a known host, group or network`

A cartography mutation removed an entity the rule references. The
rule is now quarantined: its `last_compile_error` is populated, its
matcher cursor is paused. To clear:

- Restore the missing entity (e.g. re-add the host).
- Update the rule's `src` / `dst` to a still-existing reference.
- Delete the rule.

### `another obserae instance is already listening`

The control socket is held by a live daemon. Either stop the other
instance, or change `control.socket` in the YAML.

### Daemon logs are too noisy / too quiet

YAML `logging.verbosity` is the long-term setting; `-v`, `-vv`,
`-vvv` flags only ever bump *up* from the YAML floor — intended for
ad-hoc triage.

### The matcher seems frozen

The matcher is one goroutine on a ticker. If the daemon is
otherwise healthy (status responds, flows ingest), check the logs
for `matcher tick failed`. The matcher catches its own errors and
retries on the next tick; a sustained stream of failures points to
a database-level problem.

### Session count is 0 even though flows are coming in

The sessionizer logs once per tick at INFO. Look for these patterns
in `journalctl -u obserae`:

| Log line                                                          | Diagnosis                                                                  |
|-------------------------------------------------------------------|----------------------------------------------------------------------------|
| `sessionizer tick flows=N closed=M …`                             | Healthy. N flows consumed, M sessions closed.                              |
| `sessionizer tick (no flows in delta) watermark=…`                | The flows table has nothing past the cursor — ingestion is idle.           |
| `sessionizer tick (all flows still in grace window) …`            | Flows present but younger than `sessions.grace`. Picked up on a later tick.|
| `sessionizer saw eligible flows but processed none — likely bug`  | Real anomaly. The line includes `cutoff_utc`, `now_utc`, etc. — compare them. The most common historical cause was a non-UTC database session, fixed in the daemon since v1.0. |

---

## Upgrading

The storage layer is forward-compatible by design. Upgrading is a
binary swap:

```sh
sudo systemctl stop obserae
sudo install -m 0755 obserae /usr/local/bin/
sudo systemctl start obserae
```

Re-importing your authored YAMLs is **not** required across
upgrades — existing rows live through any schema migration. The
release notes will explicitly call out the rare cases where a
recompile is needed.

For container deployments, pull the new image and restart:

```sh
docker pull ghcr.io/spartan-conseil/obserae:latest
docker restart obserae
```

---

## Where to next

- [configuration.md](configuration.md) — every YAML key with its
  defaults and tuning recipes.
- [cli.md](cli.md) — the `obserae-cli` reference.
- [web-gui.md](web-gui.md) — what every page in the browser
  interface does.

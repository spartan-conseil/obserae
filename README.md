# obserae

**A NetFlow collector with a built-in network map, detection rules, and
a friendly query language — all in one self-contained binary.**

obserae captures NetFlow v5/v9 exports from your routers, switches and
hosts, stores them in DuckDB, and lets you investigate traffic by
*name* (`src: backends, dst: postgres`) instead of by IP address. It
ships with a web GUI for day-to-day work and a CLI for automation.

---

obserae runs on **Linux, amd64 and arm64** — including modern
Raspberry Pi (4 / 5) and ARM servers.

## Quick install

### Option 1 — Docker (recommended)

The image is multi-arch: Docker automatically pulls the right build
for your CPU (amd64 or arm64), so the same command works on a server
or a Raspberry Pi.

```sh
docker run -d \
  --name obserae \
  --restart unless-stopped \
  -p 2055:2055/udp \
  -p 127.0.0.1:8080:8080/tcp \
  -v obserae-data:/var/lib/obserae \
  ghcr.io/spartan-conseil/obserae:latest
```

- **UDP 2055** — NetFlow v5/v9 ingest port (point your exporters here).
- **TCP 8080** — Web GUI; open <http://localhost:8080> in your browser.
- **`obserae-data` volume** — holds the database and the
  parquet buffer, so your data survives container restarts.

To run as a non-root host user (recommended), add
`--user $(id -u):$(id -g)` and bind-mount a directory you own instead
of a named volume. See
[installation.md](installation.md#run-as-a-non-root-host-user) for
the details.

### Option 2 — Pre-built binaries

Download the tarball for your architecture from the
[latest release](https://github.com/spartan-conseil/obserae/releases/latest):

```sh
# amd64 — most servers, desktops, mini-PCs
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_amd64.tar.gz

# arm64 — Raspberry Pi 4/5, ARM servers
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_arm64.tar.gz

tar xzf obserae.tar.gz
cd obserae_linux_*

# Run with the bundled minimal config
mkdir -p data/parquet
./obserae --config obserae.yaml
```

Each tarball contains the `obserae` daemon, the `obserae-cli` admin
tool, a ready-to-use `obserae.yaml`, the EULA, and the full
documentation under `docs/`.

> **Not sure which architecture?** Run `uname -m`: `x86_64` → amd64,
> `aarch64` → arm64.

---

## Simplest config

The minimal `obserae.yaml` needed to run looks like this:

```yaml
listen:
  address: "0.0.0.0:2055"     # NetFlow ingest port

storage:
  duckdb_path: "./data/obserae.duckdb"

buffer:
  directory: "./data/parquet"

control:
  socket: "./data/obserae.sock"

web:
  enabled: true
  address: "127.0.0.1:8080"   # Web GUI bound to localhost only
```

That's it. Everything else uses sensible defaults. The full reference
with every tunable lives in [configuration.md](configuration.md).

> **About the web GUI:** it binds to `127.0.0.1` by default — only
> the local machine can reach it. To expose it on the network, put it
> behind a reverse proxy that does TLS and authentication, then
> change the address to `0.0.0.0:8080`. There is no built-in auth.

---

## Verify it works

Once the daemon is running, point one or more devices at UDP 2055
and watch the counters move:

```sh
./obserae-cli --socket ./data/obserae.sock status
```

Open the web GUI at <http://localhost:8080> to see the cockpit.

---

## Documentation map

### Getting started

| Page                                    | What it covers                                                    |
|-----------------------------------------|-------------------------------------------------------------------|
| [installation.md](installation.md)      | All install methods, system requirements, NetFlow exporter hints  |
| [quickstart.md](quickstart.md)          | First flows ingested, first map, first query — in 10 minutes      |
| [configuration.md](configuration.md)    | Every YAML key and CLI flag, with recipes                         |

### Using obserae day-to-day

| Page                                    | What it covers                                                     |
|-----------------------------------------|--------------------------------------------------------------------|
| [web-gui.md](web-gui.md)                | Tour of every page in the web interface                            |
| [cli.md](cli.md)                        | `obserae-cli` subcommand reference                                 |
| [cartography.md](cartography.md)        | Describe your network so traffic shows up by name                  |
| [rules.md](rules.md)                    | Write detection rules and inspect what they catch                  |
| [nfql.md](nfql.md)                      | The NFQL query language — investigate traffic interactively        |
| [alerting.md](alerting.md)              | Turn NFQL queries into alerts (Investigation → Rules → Detection)  |
| [outputs.md](outputs.md)                | Export alerts to webhooks / Gotify (the Outputs page)              |
| [sessions.md](sessions.md)              | How raw flows are folded into bidirectional, role-aware sessions   |
| [enrichment.md](enrichment.md)          | Tag IPs with cloud-provider ranges (AWS / Azure / GCP)             |
| [sources.md](sources.md)                | Label NetFlow exporters; manage cloud / threat-intel sources       |
| [lifecycle.md](lifecycle.md)            | Storage usage, retention policy, periodic backups, manual I/O      |

### Running in production

| Page                                    | What it covers                                                     |
|-----------------------------------------|--------------------------------------------------------------------|
| [operations.md](operations.md)          | Deploy with systemd, monitor, back up, troubleshoot                |

---

## What obserae is — and is not

**obserae is** a NetFlow collector for teams that already have NetFlow
exporters and want a self-hosted way to understand and detect what
those exporters see, without spinning up Elasticsearch or buying a
commercial NDR.

**obserae is not** a packet capture tool, an SIEM, or a SOAR. It works
exclusively on NetFlow records (v5 and v9) — it never sees raw
packets. There is no log ingestion, no alerting integration (yet),
and no commercial threat-intel.

---

## License & support

obserae is **proprietary, free-to-use software**. The terms are in
the `EULA.txt` bundled with every release tarball and Docker image.
The source code is not public.

Bug reports and questions: open an issue at
<https://github.com/spartan-conseil/obserae>.

For installation help, see [installation.md](installation.md);
for production deployments, see [operations.md](operations.md).

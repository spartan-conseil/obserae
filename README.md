# obserae

obserae is a self-hosted NetFlow/IPFIX collector for people who need to
understand real network traffic without building a whole data platform first.
It receives exports from routers, firewalls and hosts, stores them locally, and 
lets you investigate traffic by name: `src: backends, dst: postgres` instead of 
memorising addresses.

It ships as one daemon plus a small admin CLI. The browser UI is there for
daily work: cartography, sessions, NFQL queries, detection rules, alerting,
outputs, users, retention and backups.

obserae runs on Linux `amd64` and `arm64`, including Raspberry Pi 4/5 and ARM
servers.

> **Closed source, free to use.** obserae ships as proprietary binaries and
> Docker images — the source code is not public. It is **free** for personal use
> and for small businesses, and it is currently **in alpha**, so every feature is
> open while it stabilises. **No telemetry, no license server, runs fully
> offline.** Details: [Licensing & transparency](LICENSING.md).

## Quick Install

### Docker

This starts obserae with persistent storage and exposes the GUI only on the
local machine:

```sh
docker run -d \
  --name obserae \
  --restart unless-stopped \
  -p 2055:2055/udp \
  -p 4739:4739/udp \
  -p 127.0.0.1:8080:8080/tcp \
  -v obserae-data:/var/lib/obserae \
  ghcr.io/spartan-conseil/obserae:latest
```

Open <http://localhost:8080>. On first boot, the daemon creates the `admin`
user and prints a generated password once in the container logs:

```sh
docker logs obserae | grep "generated admin password"
```

For a LAN or internet-facing GUI, do not publish plain HTTP directly. Put TLS in
front; the ready-to-run Caddy example lives in
[docker-compose/](docker-compose/).

### Release Tarball

Download the latest Linux tarball for your CPU:

```sh
# amd64: most servers, desktops, mini-PCs
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_amd64.tar.gz

# arm64: Raspberry Pi 4/5, ARM servers
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_arm64.tar.gz

tar xzf obserae.tar.gz
cd obserae_linux_*
mkdir -p data
./obserae --config obserae.yaml
```

Not sure which architecture you need? `uname -m` prints `x86_64` for amd64 and
`aarch64` for arm64.

## Minimal Config

This is enough for a local first run:

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

control:
  socket: "./data/obserae.sock"

web:
  enabled: true
  address: "127.0.0.1:8080"
```

The GUI always requires a login. The `127.0.0.1` bind keeps it local; if you
change it to `0.0.0.0:8080`, put a reverse proxy with TLS in front. The session
cookie is marked `Secure` automatically for non-loopback deployments, so remote
plain-HTTP access usually looks like a login loop. That is a browser protecting
the cookie, not a bad password.

## First Checks

[Point a NetFlow exporter at UDP 2055 or an IPFIX exporter at UDP 4739](docs/exporters.md), then
check the daemon:

```sh
./obserae-cli --socket ./data/obserae.sock status
```

From there, open the GUI and start with the Cockpit, Cartography and Query
pages. The [quickstart](docs/quickstart.md) walks through a small end-to-end
setup.

## Documentation

### Getting Started

| Page | Start here when you want to... |
|------|--------------------------------|
| [Installation](docs/installation.md) | Install with Docker or binaries and get the daemon running. |
| [Configuring Exporters](docs/exporters.md) | Configure routers, firewalls and host probes to send NetFlow/IPFIX to obserae. |
| [Quickstart](docs/quickstart.md) | Build a tiny cartography, add rules, send traffic and run the first queries. |
| [Configuration](docs/configuration.md) | Understand every YAML key and the practical tuning recipes. |

### Daily Use

| Page | What it helps with |
|------|--------------------|
| [Web GUI](docs/web-gui.md) | Know what each screen is for and where to click next. |
| [CLI](docs/cli.md) | Automate admin tasks and recover access from the terminal. |
| [Cartography](docs/cartography.md) | Describe networks, hosts, groups and services by name. |
| [Sessions](docs/sessions.md) | Understand the bidirectional conversations built from raw flows. |
| [NFQL](docs/nfql.md) | Query flows, sessions, enrichment and rule matches. |
| [NFQL Cookbook](docs/cookbook.md) | Copy practical query patterns into the Investigation page. |
| [Detection Rules](docs/rules.md) | Model allowed connectivity and inspect what matched. |
| [Alerting](docs/alerting.md) | Turn saved NFQL queries into alerts. |
| [Outputs](docs/outputs.md) | Send alerts to webhooks or Gotify. |
| [Connectors](docs/sources.md) | Label exporters, manage cloud/threat-intel/GeoIP/ASN sources — what each one is for and its limits. |
| [IP Enrichment](docs/enrichment.md) | Use cloud, threat-intel, GeoIP and ASN ranges in queries. |
| [Audit log](docs/web-gui.md#audit-log) | Track who changed what, and verify the tamper-evident trail. |
| [Lifecycle](docs/lifecycle.md) | Manage retention, storage and backups. |

### Production

| Page | What it covers |
|------|----------------|
| [Operations](docs/operations.md) | systemd deployment, monitoring, backups, upgrades and troubleshooting. |
| [Docker Compose TLS](docker-compose/) | Turnkey obserae + Caddy setup for HTTPS login. |

## What obserae Is Not

obserae is not packet capture, a SIEM, or a SOAR. It never sees raw packets and
does not ingest arbitrary logs. It works from NetFlow v5/v9 and IPFIX records,
then gives you cartography, sessions, NFQL, connectivity rules and alert
delivery on top.

## License and transparency

obserae is **closed-source, free-to-use** software published by Spartan Conseil;
the binaries and Docker images are proprietary and the source is not public. The
project is currently **in alpha** (pre-1.0): every feature is open and free while
it stabilises.

What that means in practice — and what the bundled EULA commits to in writing:

- **Free for you.** Free for personal use and for small businesses (a group of
  **≤ 20 people and ≤ €2,000,000** revenue). Larger organisations, managed
  service providers and paid services built on obserae need a commercial license
  (<licensing@spartan-conseil.fr>) — everything stays freely usable during the alpha.
- **No telemetry, no phone-home, no license server.** The EULA commits to it: no
  usage telemetry, no outbound contact with the publisher's (or anyone's) servers,
  no online license verification. obserae runs fully air-gapped.
- **Your data is yours.** Flows, cartography, rules, sessions and reports are your
  sole property; the publisher has no access and claims no rights over them.
- **No remote kill-switch.** If the project ever stopped, your install keeps
  working — there is no license check to fail and nothing to phone home to.
- **Versioned, never retroactive.** The terms that ship with your version are
  yours to keep — any future change applies only to future versions.

A few features — **user management & RBAC**, the **audit log**, **connectors to
major commercial platforms** (e.g. a SIEM such as QRadar) and **premium
IP-enrichment sources** — are planned **Enterprise** features. They are **free
and open during the alpha**; we flag them now so their future licensing is no
surprise.

Full terms: `EULA.txt` (French, binding) / `EULA.en.txt` (English courtesy
translation), bundled with every release and Docker image. Plain-language
answers: **[Licensing & transparency FAQ](LICENSING.md)**.

Bug reports and questions: <https://github.com/spartan-conseil/obserae>.

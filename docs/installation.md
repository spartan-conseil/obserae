# Installation

obserae is a self-contained daemon plus a small admin CLI. This page
covers the two supported install paths (Docker and pre-built
binaries), plus the basics of pointing your NetFlow exporters at it.

---

## System requirements

| Resource | Recommended                                                          |
|----------|----------------------------------------------------------------------|
| OS / CPU | Linux, **amd64 or arm64** (incl. Raspberry Pi 4/5 and ARM servers)   |
| Memory   | 1GB minimum, 2 GB+ for production                                 |
| Disk     | Sized for your retention — DuckDB stores flows compactly (~50–200 bytes per flow record) |
| CPU load | 1 core is enough for most homelabs; 2–4 cores for production         |
| Network  | UDP ports for NetFlow (default 2055) and IPFIX (default 4739), TCP port for the GUI (default 8080) |

obserae runs entirely on disk — no Elasticsearch, no Kafka, no Redis.
The only external dependency at runtime is the IP-enrichment HTTPS
fetcher (AWS / Azure / GCP), and it can be disabled.

---

## Option 1 — Docker (recommended)

The image is published to GitHub Container Registry as a **multi-arch
manifest**: Docker automatically pulls the amd64 or arm64 build to
match your CPU, so the same command works on a server, a desktop, or
a Raspberry Pi.

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

What that does:

- Forwards **UDP 2055** (NetFlow ingest), **UDP 4739** (IPFIX ingest)
  and **TCP 8080** (web GUI, localhost) from the host to the container.
- Mounts a named volume at `/var/lib/obserae` for the DuckDB file
  and the parquet buffer, so data survives container restarts.
- Loads the image's default `obserae.yaml`, pre-configured for
  container paths.

Open <http://localhost:8080> to reach the web GUI.

> **The login keeps bouncing back to the login page (remote / plain HTTP)?**
> This is the single most common Docker gotcha. The container binds the GUI on
> all interfaces, so the session cookie is marked **`Secure`** by default — and a
> browser silently **drops** a `Secure` cookie received over plain `http://` from
> a remote IP. So your password is accepted but the session never sticks and you
> loop. (It works from `http://localhost:8080` only because browsers treat
> *localhost* as a secure context.) Two fixes:
>
> - **Recommended — put TLS in front.** Front obserae with a reverse proxy
>   (Caddy, nginx, Traefik) terminating HTTPS and forwarding
>   `X-Forwarded-Proto: https`. The cookie stays `Secure` and login works.
> - **Plain-HTTP LAN deployment** (no TLS, trusted network): mount a config with
>   `web.secure_cookies: false`. The login then works over plain HTTP, but the
>   session cookie travels **unprotected** — only do this on a trusted network.
>   See [configuration.md](configuration.md#expose-the-web-gui-on-the-network).

### Run as a non-root host user

By default the container runs as a built-in non-root user
(UID 65532). To make the files in the data volume owned by *your*
host user instead, run with `--user` and bind-mount a directory you
own:

```sh
mkdir -p ./obserae-data
docker run -d \
  --name obserae \
  --restart unless-stopped \
  --user "$(id -u):$(id -g)" \
  -p 2055:2055/udp \
  -p 4739:4739/udp \
  -p 127.0.0.1:8080:8080/tcp \
  -v "$(pwd)/obserae-data:/var/lib/obserae" \
  ghcr.io/spartan-conseil/obserae:latest
```

### Override the config

```sh
docker run -d \
  --name obserae \
  -p 2055:2055/udp \
  -p 4739:4739/udp \
  -p 127.0.0.1:8080:8080/tcp \
  -v "$(pwd)/obserae.yaml:/etc/obserae/obserae.yaml:ro" \
  -v obserae-data:/var/lib/obserae \
  ghcr.io/spartan-conseil/obserae:latest \
  --config /etc/obserae/obserae.yaml
```

### Docker Compose with TLS (Caddy) — recommended for remote access

For anything beyond `http://localhost`, run obserae behind a TLS reverse proxy so
the GUI login works (see the login-loop note above). A turnkey
**obserae + [Caddy](https://caddyserver.com/)** stack ships in the
[`docker-compose/`](../docker-compose/) directory — it brings up HTTPS on `:443`
with a self-signed certificate, **no domain or DNS required**:

```sh
cd docker-compose
docker compose up -d

# first-boot admin password (printed once)
docker compose logs obserae | grep "generated admin password"
```

Open **<https://ip>** and click through the one-time "not trusted" warning
(self-signed CA). Caddy terminates TLS and forwards `X-Forwarded-Proto: https`, so
obserae keeps the session cookie `Secure` and the login sticks.

What the stack runs:

- **obserae** — publishes only the flow-ingest ports (`2055/udp`, `4739/udp`) to
  the host; the GUI (`8080`) is reachable **only** through Caddy, never as plain
  HTTP.
- **caddy** — serves the GUI over HTTPS on `:443` (and `:80`, used only when you
  switch to a real domain).

**Real domain + browser-trusted certificate.** Edit the bundled `Caddyfile`:
swap the self-signed block for the commented production block (your domain →
`reverse_proxy obserae:8080`), point the domain's DNS at this host, and make ports
80 and 443 reachable from the internet. Caddy then provisions and auto-renews a
Let's Encrypt certificate — no more warnings.

### Run the admin CLI against the container

```sh
docker exec -it obserae obserae-cli status
```

---

## Option 2 — Pre-built binaries

Download the tarball for your architecture. The URLs below always
resolve to the newest release.

```sh
# amd64 — most servers, desktops, mini-PCs
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_amd64.tar.gz

# arm64 — Raspberry Pi 4/5, ARM servers
curl -L -o obserae.tar.gz \
  https://github.com/spartan-conseil/obserae/releases/latest/download/obserae_linux_arm64.tar.gz
```

> **Which architecture?** Run `uname -m`: `x86_64` → amd64,
> `aarch64` → arm64.

Extract and run:

```sh
tar xzf obserae.tar.gz
cd obserae_linux_*

mkdir -p data
./obserae --config obserae.yaml
```

What's inside the tarball:

```
obserae_linux_<arch>/
├── obserae               # daemon (collects NetFlow, hosts DuckDB)
├── obserae-cli           # admin CLI
├── obserae.yaml          # minimal config (edit before production use)
├── EULA.txt              # license / terms of use
└── docs/                 # the full user documentation
```

The daemon prints `INFO control api listening` and
`INFO collector listening` once it is ready. Open
<http://localhost:8080> to reach the web GUI. To stop, press `Ctrl+C`.

For a long-running install, see
[operations.md](operations.md) for the systemd unit.

---

## After installing — send flows to obserae

obserae listens on **UDP 2055** (NetFlow v5/v9) and **UDP 4739** (IPFIX). Point
each device or software probe at `<obserae-host>` on the matching port.

Per-device setup for Cisco, Juniper, MikroTik, FortiGate, Palo Alto,
pfSense/OPNsense, Open vSwitch, host probes and many more — and how to confirm
flows are arriving — has its own page: **[Configuring Exporters](exporters.md)**.

---

## Next steps

- [exporters.md](exporters.md) — configure your devices and probes to send flows.
- [quickstart.md](quickstart.md) — your first cartography, first
  rules, and first query.
- [configuration.md](configuration.md) — full configuration reference.
- [operations.md](operations.md) — running obserae as a systemd
  service, backups, troubleshooting.

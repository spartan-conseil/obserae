# Installation

obserae is a self-contained daemon plus a small admin CLI. This page
covers the two supported install paths (Docker and pre-built
binaries), plus the basics of pointing your NetFlow exporters at it.

> obserae is **proprietary, free-to-use software**. Use the published Docker image or the
> release binaries below.

---

## System requirements

| Resource | Recommended                                                          |
|----------|----------------------------------------------------------------------|
| OS / CPU | Linux, **amd64 or arm64** (incl. Raspberry Pi 4/5 and ARM servers)   |
| Memory   | 512 MB minimum, 2 GB+ for production                                 |
| Disk     | Sized for your retention — DuckDB stores flows compactly (~50–200 bytes per flow record) |
| CPU load | 1 core is enough for most homelabs; 2–4 cores for production         |
| Network  | UDP port for NetFlow (default 2055), TCP port for the GUI (default 8080) |

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
  -p 8080:8080/tcp \
  -v obserae-data:/var/lib/obserae \
  ghcr.io/spartan-conseil/obserae:latest
```

What that does:

- Forwards **UDP 2055** (NetFlow ingest) and **TCP 8080** (web GUI)
  from the host to the container.
- Mounts a named volume at `/var/lib/obserae` for the DuckDB file
  and the parquet buffer, so data survives container restarts.
- Loads the image's default `obserae.yaml`, pre-configured for
  container paths.

Open <http://localhost:8080> to reach the web GUI.

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
  -p 8080:8080/tcp \
  -v "$(pwd)/obserae-data:/var/lib/obserae" \
  ghcr.io/spartan-conseil/obserae:latest
```

### Override the config

```sh
docker run -d \
  --name obserae \
  -p 2055:2055/udp \
  -p 8080:8080/tcp \
  -v "$(pwd)/obserae.yaml:/etc/obserae/obserae.yaml:ro" \
  -v obserae-data:/var/lib/obserae \
  ghcr.io/spartan-conseil/obserae:latest \
  --config /etc/obserae/obserae.yaml
```

### Run the admin CLI against the container

```sh
docker exec -it obserae obserae-cli status
```

### docker-compose

```yaml
# docker-compose.yml
services:
  obserae:
    image: ghcr.io/spartan-conseil/obserae:latest
    container_name: obserae
    restart: unless-stopped
    ports:
      - "2055:2055/udp"
      - "8080:8080/tcp"
    volumes:
      - obserae-data:/var/lib/obserae
      # Optional: mount your own config
      # - ./obserae.yaml:/etc/obserae/obserae.yaml:ro
    # command: ["--config", "/etc/obserae/obserae.yaml"]

volumes:
  obserae-data:
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

mkdir -p data/parquet
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

## After installing — point NetFlow at obserae

obserae listens on UDP 2055 by default. Configure each exporter to
send v5 or v9 flows to `<obserae-host>:2055`.

### MikroTik / RouterOS

```routeros
/ip traffic-flow
set enabled=yes
/ip traffic-flow target
add address=<obserae-host>:2055 version=9
```

### Cisco IOS / IOS-XE

```cisco
flow exporter OBSERAE
 destination <obserae-host>
 transport udp 2055
 export-protocol netflow-v9

flow monitor MONITOR
 exporter OBSERAE
 record netflow ipv4 original-input

interface GigabitEthernet0/1
 ip flow monitor MONITOR input
```

### pfSense / OPNsense

Install the `softflowd` package, then in the GUI: *Services →
softflowd* → set host to `<obserae-host>`, port to `2055`, version
to `9`.

### Linux host (via `softflowd`)

```sh
sudo apt install softflowd
sudo softflowd -i <if>> -n <obserae-host>:2055 -v 9
```

### Verifying it works

Run obserae's status command and watch the `flows` counter grow:

```sh
./obserae-cli --socket ./data/obserae.sock status
```

If after a couple of minutes the counter stays at 0:

- Is UDP 2055 open on the obserae host?
  `sudo ss -ulnp | grep 2055`
- Is anything actually being sent?
  `sudo tcpdump -ni any udp port 2055 -c 5`

If `tcpdump` shows traffic but the counter stays at 0, look at the
daemon log — it prints decode errors at the default verbosity.

---

## Next steps

- [quickstart.md](quickstart.md) — your first cartography, first
  rules, and first query.
- [configuration.md](configuration.md) — full configuration reference.
- [operations.md](operations.md) — running obserae as a systemd
  service, backups, troubleshooting.

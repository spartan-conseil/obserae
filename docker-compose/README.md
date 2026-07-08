# obserae — turnkey Docker Compose (HTTPS via Caddy)

A minimal, production-oriented way to run **obserae** with Docker Compose behind a
**Caddy** reverse proxy that terminates **TLS out of the box** — HTTPS login works
immediately, with no certificate setup, no domain and no DNS.

This is the single-node deployment: the real obserae image collecting your own
flows. If instead you want a full **simulated enterprise network** to explore the
product without any hardware, use the [demo lab](../obserae-demo/) — that one
spins up fake workstations, servers and a NetFlow sensor.

---

## What's in here

| File | Role |
|------|------|
| `docker-compose.yml` | Two services: `obserae` (collector + GUI) and `caddy` (TLS reverse proxy). |
| `Caddyfile` | Caddy config. Default: self-signed HTTPS for any host/IP. Commented block: real domain + Let's Encrypt. |

```
          UDP 2055 / 4739  (NetFlow / IPFIX from your routers & firewalls)
                     │
                     ▼
            ┌─────────────────┐        :443 (HTTPS)      ┌──────────┐
   flows ──►│     obserae      │◄─────  reverse_proxy  ───│  caddy   │◄── browser
            │  GUI :8080 (int) │        obserae:8080      │  TLS     │   https://…
            └─────────────────┘                          └──────────┘
```

The GUI port (`8080`) is **not** published to the host — it is reachable only
through Caddy on `443`, so plain HTTP is never exposed. Caddy also forwards
`X-Forwarded-Proto: https`, which lets obserae keep its session cookie `Secure`
(no login loop).

---

## Requirements

- Docker Engine + Docker Compose v2 (`docker compose version`).
- Ports **443/tcp** (+ **443/udp** for HTTP/3) free on the host, and **80/tcp**
  only if you later switch to a real domain (ACME).
- Flow exporters (routers, firewalls, hosts) able to reach this host on
  **UDP 2055** (NetFlow v5/v9) or **UDP 4739** (IPFIX).

---

## Quick start

```bash
cd docs-github/docker-compose
docker compose up -d
```

Then open **https://localhost** (or `https://<this-host-ip>`).

> Your browser shows a one-time **"not trusted"** warning because the certificate
> is issued by Caddy's built-in self-signed CA — click through. Connecting by bare
> IP also raises a name-mismatch notice; that is expected. The connection is still
> encrypted. To get rid of the warnings entirely, use a real domain (see below).

Get the **first-boot admin password** (printed once, on the very first start):

```bash
docker compose logs obserae | grep "generated admin password"
```

Stop / start / update:

```bash
docker compose stop            # stop, keep data
docker compose up -d           # start again
docker compose pull && docker compose up -d   # upgrade to the latest image
docker compose down            # stop and remove containers (volumes kept)
docker compose down -v         # + delete volumes (obserae DB and Caddy certs) — destructive
```

---

## Point your exporters at obserae

obserae ingests **NetFlow v5/v9 on UDP 2055** and **IPFIX on UDP 4739** only (it
does not do packet capture). Configure your routers / firewalls / vSwitches to
export flows to this host:

- NetFlow → `udp://<this-host>:2055`
- IPFIX → `udp://<this-host>:4739`

Allow it 2–5 minutes after the first traffic for the templates to arrive, then
flows fill in. From there, model your network on the **Cartography** and **Flow
Matrix** pages so obserae can flag what does not belong.

---

## Ports

| Port | Proto | Service | Purpose |
|------|-------|---------|---------|
| 443 | tcp | caddy | HTTPS GUI |
| 443 | udp | caddy | HTTP/3 (optional, same GUI) |
| 80 | tcp | caddy | ACME challenge — only used with a real domain |
| 2055 | udp | obserae | NetFlow v5/v9 ingest |
| 4739 | udp | obserae | IPFIX ingest |

---

## Data & persistence

Three named volumes survive restarts and upgrades:

- `obserae-data` → `/var/lib/obserae` — the obserae database, config, at-rest
  master key and secrets. **Back this up.**
- `caddy-data` → Caddy's internal CA and issued certificates (so the self-signed
  cert stays stable across restarts instead of changing every boot).
- `caddy-config` → Caddy's runtime config.

`docker compose down -v` deletes all three — you lose the obserae DB and have to
start over. Use plain `down` to keep them.

---

## Production: real domain, browser-trusted certificate

To serve obserae on a real domain with an automatically provisioned and renewed
**Let's Encrypt** certificate (no browser warnings), edit `Caddyfile` and replace
the default `:443 { … }` block with:

```caddyfile
obserae.example.com {
	reverse_proxy obserae:8080
}
```

Requirements for ACME to succeed:

1. Point the domain's DNS **A/AAAA** record at this host.
2. Make ports **80** and **443** reachable from the internet (Caddy uses port 80
   for the ACME HTTP challenge, then serves 443).

Then `docker compose up -d` — Caddy obtains and auto-renews the certificate. See
`Caddyfile` for the full explanation of the default directives (`issuer internal`,
`on_demand`, `default_sni`) and why they are needed for the self-signed mode.

---

## Notes

- The obserae image is pinned to `:latest`; pin a specific tag (e.g.
  `ghcr.io/spartan-conseil/obserae:v0.27.0`) in `docker-compose.yml` for a
  reproducible deployment.
- Rotate the first-boot admin password before exposing the UI, and consider
  wiring LDAP or OIDC for real user sign-in.
- Most administration is done from the GUI. Privileged/CLI operations use
  `obserae-cli` inside the container (`docker compose exec obserae obserae-cli …`),
  pointing `--socket` at obserae's control socket as configured in the image.

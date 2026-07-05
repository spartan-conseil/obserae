# obserae demo lab

A Docker Compose environment that simulates a **small enterprise** (DMZ,
production, pre-production, workstations) **plus obserae** and a **NetFlow
sensor**, with **realistic activity generated continuously**. Goal: run a
credible technical demo of obserae without any network hardware.

---

## Quick start (one command)

On a Linux host with Docker + Compose v2, deploy the whole lab in a single
command:

```bash
curl -fsSL https://demo.obserae.com | sh
```

The installer downloads the demo files from GitHub, builds the images and starts
the stack in `./obserae-demo`, then prints the next steps. Open the UI at
**http://127.0.0.1:8081** (login `admin` / `admin`) and give it 2–5 minutes for
the first NetFlow templates to arrive.

The same script doubles as a lifecycle tool — pass a command (and options) after
`-s --`:

```bash
# also demo LDAP sign-in (FreeIPA, slower first boot)
curl -fsSL https://demo.obserae.com | sh -s -- --with-ldap

# follow logs / check status / tear everything down (volumes included)
curl -fsSL https://demo.obserae.com | sh -s -- logs sensor
curl -fsSL https://demo.obserae.com | sh -s -- status
curl -fsSL https://demo.obserae.com | sh -s -- uninstall --yes
```

Prefer to read the script first? `curl -fsSL https://demo.obserae.com -o install.sh`,
inspect it, then `sh install.sh`. Useful options: `--dir <path>` (default
`./obserae-demo`), `--ref <branch|tag>`, `--no-start` (fetch + validate the
compose file only). It just automates the manual steps in §3.

> The installer starts the stack **empty**: it does not import the ready-made
> configuration (§4 shows the one-liner for that) and leaves FreeIPA off until
> you pass `--with-ldap`. The rest of this README is the manual, step-by-step
> path and explains what each piece does.

---

## 1. Topology

```
                                 ┌───────────────────────────────┐
                                 │  mgmt  10.0.0.0/24  (obs-mgmt) │
                                 │   obserae  10.0.0.10           │
                                 │   UI: http://127.0.0.1:8081    │
                                 └───────────────▲───────────────┘
                                                 │ NetFlow v9 (UDP/2055)
                                     ┌───────────┴───────────┐
                                     │  sensor (softflowd)    │  network_mode: host
                                     │  captures obs-dmz/prod/│  → passive probe (SPAN)
                                     │  preprod/work          │
                                     └───────────┬───────────┘
                                                 │ bridge capture
   ┌───────────────┐   ┌───────────────┐   ┌─────┴─────────┐   ┌────────────────┐
   │ DMZ 10.0.10/24│   │ PROD 10.0.20/24│  │ PREPROD 10.0.30│   │ WORK 10.0.40/24│
   │ (obs-dmz)     │   │ (obs-prod)     │  │ (obs-preprod)  │   │ (obs-work)     │
   │               │   │                │  │                │   │                │
   │ dns  .10      │   │ caddy   .10    │  │ caddy    .10   │   │ ws1-dev   .11  │
   │ (dnsmasq)     │   │ backend .20    │  │ backend  .20   │   │ ws2-ops   .12  │
   │ ipa  .20      │   │ db      .30    │  │ db       .30   │   │ ws3-finance .13│
   │ (FreeIPA)     │   │                │  │                │   │ ws4-hr    .14  │
   │               │   │                │  │                │   │ ws5-mkt   .15  │
   └───────┬───────┘   └───────┬────────┘  └───────┬────────┘   └───────┬────────┘
           │ .2               │ .2               │ .2                 │ .2
           └──────────────────┴──────┬───────────┴────────────────────┘
                                      │
                         ┌────────────┴────────────┐
                         │  lab router / firewall   │  ip_forward=1, NO east-west NAT
                         │  (interconnects the 4     │  → real source IPs preserved
                         │   segments)               │
                         └──────────────────────────┘
```

**Key ideas**

- Each segment is a Docker bridge network with a **fixed bridge name**
  (`obs-dmz`, `obs-prod`, …) so the sensor can capture it.
- The **`softflowd` sensor** runs in `network_mode: host`, observes the bridges
  like a **SPAN/TAP port**, rebuilds bidirectional flows and **exports NetFlow
  v9** to obserae. This is the equivalent of a NetFlow exporter (router,
  firewall, vSwitch).
- A **central router** links the segments **without internal NAT**, so obserae
  sees the **real source IPs** (essential for "which workstation talked to
  production?").

> **obserae ingest:** obserae consumes **NetFlow v5/v9 on UDP 2055 only** — it
> does not process IPFIX or raw packets. The sensor is configured for NetFlow
> v9 accordingly.

---

## 2. Requirements

- Docker Engine + Docker Compose v2 plugin (`docker compose version`).
- Linux preferred: the sensor's `network_mode: host` assumes the Docker bridges
  are host interfaces (true on Linux). On Docker Desktop (macOS/Windows) host
  capture of the bridges does not work the same way — see §8.
- Internet access to pull images and resolve public DNS.

---

## 3. Getting started

```bash
cd obserae-demo
docker compose build
docker compose up -d
```

Then open the obserae UI: **http://127.0.0.1:8081**

Check that it is alive:

```bash
docker compose logs -f sensor        # "softflowd started on obs-work ..."
docker compose logs -f ws1           # actions: web / dns / app / DRIFT ...
docker compose logs -f dns           # resolved DNS queries
```

Let it run for **2–5 minutes**: the NetFlow v9 templates must arrive first,
then the flows fill in. Full stop:

```bash
docker compose down          # keeps images and the obserae-data volume
docker compose down -v       # + removes volumes (obserae DB and Postgres data)
```

> **FreeIPA is not started by default.** It sits behind the `ldap` compose
> profile (its first boot is heavy — systemd + a CA), so a plain
> `docker compose up -d` brings up everything *except* FreeIPA. Start it only
> when you want to demo LDAP sign-in — see §5, or use the installer's
> `--with-ldap`.

---

## 4. Load the ready-to-use configuration

Prefer a fully populated obserae over building it by hand? The repo root ships
two files that give you everything at once:

- **`obserae-config.yaml`** — the complete consolidated bundle: cartography
  (networks, hosts, groups, layout), the flow matrix (expected communications),
  enrichment sources, retention, the rule sets, the local **admin** user and the
  LDAP block.
- **`obserae-masterkey.txt`** — the master key the encrypted secrets in that
  bundle were sealed with (e.g. the LDAP bind password). Import it **first**, or
  those secrets import but stay undecryptable.

Load both over obserae's control socket — **master key before config**:

```bash
SOCK=/var/lib/obserae/run/obserae.sock

# 1. Load the demo master key FIRST (rotation) so the bundle's secrets decrypt.
docker compose exec -T obserae obserae-cli --socket "$SOCK" masterkey import - < obserae-masterkey.txt

# 2. Validate, then import the full configuration bundle.
docker compose exec -T obserae obserae-cli --socket "$SOCK" config validate - < obserae-config.yaml
docker compose exec -T obserae obserae-cli --socket "$SOCK" config import  - < obserae-config.yaml
```

Prefer clicking? The UI does the same from **Config I/O**: the **Master key**
modal → *Import*, then **Import config**. Either way, once it finishes the
**Cartography**, **Flow Matrix** and **Rules** pages are already populated — every
rule and NFQL query can refer to assets by name (`host:prod-db`, `group:work-grp`,
`network:PROD`, `internet4`, …). The bundle also carries the LDAP settings, so with
the master key in place the bind password works out of the box (§5 only has to
provision FreeIPA itself).

> **Demo login — `admin` / `admin`.** Yes, both. 🙈 It's the password a
> brute-forcer cracks before its coffee cools — and that's the point: this lab is
> built to live on your laptop and get `docker compose down -v`'d afterwards. Ship
> `admin`/`admin` to production and obserae will cheerfully flag *your own* login as
> the shadiest thing on the wire. Rotate it (or wire up LDAP, §5) before anyone else
> can reach the UI.

---

## 5. Authenticate users (LDAP via FreeIPA)

Out of the box obserae only has the local **admin** account. The lab also ships a
**FreeIPA** directory in the DMZ (`ipa.corp.lan`, `10.0.10.20`) so you can
demonstrate signing in with **LDAP** accounts — the same integration a customer
would use for Active Directory (see `authentication.md`), here with FreeIPA's
`uid=%s` login attribute.

obserae normally sits alone on the isolated `mgmt` segment; for LDAP it is given a
second interface on the `dmz` network (`10.0.10.5`) so it can reach FreeIPA
directly over **LDAPS**.

```bash
# 1. Bring the stack up WITH the ldap profile so FreeIPA starts, and let its
#    (slow) first boot finish. (The installer does this for you: --with-ldap.)
docker compose --profile ldap up -d
docker compose logs -f freeipa      # wait for "FreeIPA server configured"

# 2. Provision the directory and point obserae at it (idempotent).
./scripts/setup-ldap.sh
```

The script creates a read-only bind account, the obserae role groups and three
demo users, exports the FreeIPA CA, then configures obserae (LDAPS, `uid=%s`,
group mappings) and runs `obserae-cli ldap test`. Once it finishes, sign in to
the UI (http://127.0.0.1:8081) with:

| User | Password | obserae role |
|-------|-----------|--------------|
| `alice` | `Demo12345` | admin |
| `bob` | `Demo12345` | analyst |
| `carol` | `Demo12345` | auditor |

The local **admin** account keeps working as a break-glass login even if FreeIPA
is unreachable. LDAP users appear on the **Users** page marked as LDAP accounts;
their roles come from FreeIPA group membership and refresh on every login.

> FreeIPA is heavy: it runs systemd and provisions a CA on first boot, which can
> take several minutes. If the container refuses to start, see the cgroup note in
> `docker-compose.yml` and §8.

---

## 6. Flows generated (what the sensor sends to obserae)

| Type | Example flow | Origin |
|------|--------------|--------|
| Internal DNS resolution | `work → dmz` UDP/53 | every workstation web access |
| Outbound DNS | `dmz → internet` UDP/53 | dnsmasq forwards to 1.1.1.1 / 9.9.9.9 |
| Web browsing | `work → internet` TCP/443 | `curl` to public sites |
| Production app access | `work → prod` TCP/443 (Caddy) | workstations |
| Pre-production app access | `work → preprod` TCP/443 | workstations |
| Application chain | `caddy → backend` TCP/8000, `backend → db` TCP/5432 | reverse-proxy requests |
| LDAP authentication | `obserae → ipa` TCP/636 (LDAPS) | user sign-in via FreeIPA |
| **Drift: direct DB** | `work → prod/preprod` **TCP/5432** | ws-dev (east-west violation) |
| **Drift: scan** | `work → prod` multi-port fan-out | ws-ops (`nmap`) |
| **Drift: external beacon** | `work → 203.0.113.66 / 198.51.100.13` | ws (known-bad destinations) |

The "suspicious" external IPs use **RFC 5737 documentation ranges**
(`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`): the SYN creates a flow to
investigate without actually reaching anything on the internet.

---

## 7. Suggested demo flow (in obserae)

**a) Cartography — the network by name.** The cartography loaded in §4 is already
there — open the **Cartography** page and show the graph. Use the **Orphan IPs**
drawer to show discovery proposing undocumented hosts/subnets from observed
traffic.

**b) Flow Matrix / Rules — declare intent.** The expected communications are
already declared in the bundle from §4, so everything else stands out — open the
**Flow Matrix** page to walk through them. In obserae, detection rules use
`src:` / `dst:` with the cartography grammar (`host:NAME`, `group:NAME`,
`network:NAME`, `internet4`, `internal4`, …). The baseline loaded for this lab:

| Source | Destination | Service |
|--------|-------------|---------|
| `group:workstations` | `host:dns` | DNS 53/udp |
| `host:dns` | `internet4` | DNS 53/udp |
| `group:workstations` | `group:web-frontends` | HTTPS 443/tcp |
| `group:web-frontends` | `backend-*` | 8000/tcp |
| `backend-*` | `group:databases` | PostgreSQL 5432/tcp |
| `group:workstations` | `internet4` | HTTPS 443/tcp |

**c) Investigation (NFQL) & Detection — surface the drift.** obserae's NFQL is
pipeline-style (`FROM … | WHERE …`) and understands cartography names. Examples
to run live (adapt to the exact NFQL reference in `nfql.md`):

```
# A workstation talking DIRECTLY to a database (the "postgres-present" case)
FROM sessions | WHERE src_addr == "workstations" AND dst_addr == "databases"

# Workstations reaching the public IPv4 internet
FROM sessions | WHERE src_addr == "workstations" AND dst_addr == "internet4"

# Sessions toward our simulated known-bad ranges
FROM sessions | WHERE dst_addr == "203.0.113.0/24"
```

The three drift scenarios map directly onto obserae's advertised use cases:
unexpected east-west (`workstations → databases`), known-bad destinations
(beacons), and scans/volume patterns (ops workstation).

Tip: lower `ACTIVITY_MIN_SLEEP` / `ACTIVITY_MAX_SLEEP` in `.env` then
`docker compose up -d` to densify the traffic for a livelier demo.

---

## 8. Troubleshooting

**No flows in obserae.**
1. NetFlow v9 templates: wait 2–3 minutes after the first traffic.
2. Does the sensor see the bridges? `docker compose logs sensor` should list
   `obs-dmz/prod/preprod/work`. Otherwise check bridge names:
   `ip -br link | grep obs-`.
3. Can the sensor reach obserae? From the host: `nc -uzv 10.0.0.10 2055`
   (or check `docker compose logs obserae`).
4. obserae ingests **NetFlow v5/v9 on UDP 2055 only** — do not switch the sensor
   to IPFIX/4739 (it would not be ingested).

**Inter-segment traffic does not pass (prod apps unreachable).**
- The router must have `ip_forward=1`:
  `docker exec router sysctl net.ipv4.ip_forward`.
- Containers must have the internal route:
  `docker exec caddy-prod ip route | grep 10.0.0.0/8`.

**Too much / too little traffic.** Adjust `.env` (intensity) or the workstation
`ROLE` values in the compose file.

**FreeIPA won't start / LDAP sign-in fails.**
- First boot is slow: `docker compose logs -f freeipa` until "FreeIPA server
  configured", then run `./scripts/setup-ldap.sh` (it is idempotent).
- If the container exits immediately, your host may need the `privileged: true`
  cgroup fallback noted in `docker-compose.yml` (typically cgroup v1 hosts).
- Inspect obserae's view (the control socket lives under the data volume):
  `docker compose exec obserae obserae-cli --socket /var/lib/obserae/run/obserae.sock ldap show`
  (password hidden) and the same with `ldap test` (should report success).
- The local `admin` account always works as a break-glass login if the
  directory is unreachable.

**Imported config, but LDAP / secrets don't work.**
- The master key was applied after the config, or skipped. Re-run §4 in order:
  `masterkey import` **first**, then `config import`. A missing key makes
  `config import` warn about "a different master key" and leaves the LDAP bind
  password undecryptable.

---

## 9. Design choices & limitations

- **Passive host sensor** rather than per-container: on a Docker bridge, a
  passive observer does not see traffic between two other hosts (no port
  mirroring). The host's view of the bridge does see all forwarded traffic —
  hence `network_mode: host`.
- **No east-west NAT** on the router, to preserve source IPs. Internal routing
  is injected via a `10.0.0.0/8 → router` route in each container (the connected
  /24 stays higher-priority for intra-segment, the Docker default route stays
  for internet).
- The **mgmt** segment is intentionally isolated (obserae only); the sensor
  sends flows to it via the host, so `obs-mgmt` is not captured to avoid
  self-referential noise.
- For **LDAP authentication**, obserae is given a second interface on the `dmz`
  segment (`10.0.10.5`) — the one deliberate exception to mgmt isolation. That
  path crosses `obs-dmz` and is captured, so the sign-in flow to FreeIPA appears
  in the cartography (obserae is declared there, so it is named, not an orphan).

---

## 10. Tree

```
obserae-demo/
├── install.sh                 # one-command installer (also on demo.obserae.com); fetches these files
├── manifest.txt               # list of files install.sh downloads (single source of truth)
├── docker-compose.yml         # full infrastructure
├── .env                       # optional: create to override defaults (obserae image, activity intensity)
├── images/
│   ├── labtools/Dockerfile     # Ubuntu + softflowd + tools (router, sensor, dns, backend, ws)
│   ├── caddy/Dockerfile        # Caddy + iproute2
│   └── postgres/Dockerfile     # PostgreSQL + iproute2
├── sensor/run-softflowd.sh     # launches one softflowd probe per bridge (NetFlow v9)
├── scripts/setup-ldap.sh      # provision FreeIPA + configure obserae LDAP
├── dns/dnsmasq.conf            # internal DNS (corp.lan) + internet forwarding
├── freeipa/ca.crt             # exported FreeIPA CA -- generated by setup-ldap.sh
├── backend/app.py              # Flask backend -> PostgreSQL
├── caddy/Caddyfile.prod        # production reverse proxy (internal HTTPS)
├── caddy/Caddyfile.preprod     # pre-production reverse proxy
├── obserae-masterkey.txt       # reference master key -- import first (§4)
├── obserae-config.yaml         # full ready-to-use config (cartography + flow matrix + rules + users)
├── postgres/init.sql           # demo data
└── workstations/user-activity.sh  # user activity simulator
```

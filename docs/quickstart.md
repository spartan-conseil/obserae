# Quickstart

This walkthrough takes a sysadmin from a running obserae to a working
homelab setup — a network map, an allowed-traffic baseline, two
detections, and your first queries — in about 10 minutes.

It assumes obserae is already **installed** ([installation.md](installation.md))
and that at least one **exporter is sending flows** to it
([exporters.md](exporters.md)). Every step uses the **web GUI** by default, with
a CLI equivalent for the terminal (the CLI snippets assume the binary install
with the control socket at `./data/obserae.sock`).

---

## 1. Make sure obserae is running

We pick up once obserae is **installed and running**
([installation.md](installation.md)) and at least one **exporter is sending
flows** to it ([exporters.md](exporters.md)). The GUI requires a login — the
generated `admin` password is printed once at first boot (reset it any time with
`obserae-cli user reset-admin-password`).

Open the GUI at <http://localhost:8080> and sign in. The **Cockpit** landing page
is your health check: the daemon's version and uptime, and a flow counter that
climbs as your exporters send data.

> **Prefer the terminal?** `./obserae-cli --socket ./data/obserae.sock status`
> prints the same liveness and per-table counts. An alias saves typing —
> `alias obserae-cli='./obserae-cli --socket ./data/obserae.sock'` — and the CLI
> snippets later on assume it.

---

## 2. Describe everything in one config

obserae is driven by **one consolidated YAML bundle** — cartography, the flow
matrix, alerting, outputs, retention and the rest all live in a single file.
Importing it **replaces each section it contains** and leaves the others
untouched, so the file is also a complete, version-controllable description of
your setup.

Save this as `config.yml`. It models a classic homelab: a **home** network (DHCP
clients), a **lab** network (self-hosted servers), a group of known **public DNS**
resolvers, an allowed-traffic baseline, and two detections.

```yaml
cartography:
  networks:
    - name: home
      cidr: 192.168.0.0/24
      description: Home / client devices (DHCP)
      dhcp_start: 192.168.0.100
      dhcp_end: 192.168.0.150
    - name: lab
      cidr: 192.168.10.0/24
      description: Lab / self-hosted servers

  hosts:
    # Known public DNS resolvers — modelled on the built-in `internet4` network.
    - name: dns-cloudflare
      interfaces: [{ name: eth0, network: internet4, ip: 1.1.1.1 }]
      services:   [{ name: dns, protocol: UDP, port: 53, interfaces: [eth0] }]
    - name: dns-google
      interfaces: [{ name: eth0, network: internet4, ip: 8.8.8.8 }]
      services:   [{ name: dns, protocol: UDP, port: 53, interfaces: [eth0] }]
    - name: dns-quad9
      interfaces: [{ name: eth0, network: internet4, ip: 9.9.9.9 }]
      services:   [{ name: dns, protocol: UDP, port: 53, interfaces: [eth0] }]

    # One lab server, so rules and queries have a concrete target.
    - name: lab-web
      interfaces:
        - { name: eth0, network: lab, ip: 192.168.10.10 }
      services:
        - { name: http,  protocol: TCP, port: 80,  interfaces: [eth0] }
        - { name: https, protocol: TCP, port: 443, interfaces: [eth0] }
        - { name: ssh,   protocol: TCP, port: 22,  interfaces: [eth0] }

  groups:
    - name: public-dns
      members: [dns-cloudflare, dns-google, dns-quad9]

flow_matrix:
  rules:
    # Egress — what internal hosts (home + lab) may do outbound.
    # `internal4` matches all your private IPv4 space; here that is home + lab.
    - { name: dns-to-known-resolvers, src: internal4, src_service: '*', dst: group:public-dns, dst_service: dns,     protocol: UDP }
    - { name: web-egress-http,        src: internal4, src_service: '*', dst: internet4,         dst_service: 80/tcp,  protocol: TCP }
    - { name: web-egress-https,       src: internal4, src_service: '*', dst: internet4,         dst_service: 443/tcp, protocol: TCP }
    - { name: web-egress-quic,        src: internal4, src_service: '*', dst: internet4,         dst_service: 443/udp, protocol: UDP }
    - { name: ntp-egress,             src: internal4, src_service: '*', dst: internet4,         dst_service: 123/udp, protocol: UDP }
    # East-west — the only home -> lab traffic we expect.
    - { name: home-to-lab-http,       src: network:home, src_service: '*', dst: network:lab, dst_service: 80/tcp,  protocol: TCP }
    - { name: home-to-lab-https,      src: network:home, src_service: '*', dst: network:lab, dst_service: 443/tcp, protocol: TCP }

alerting:
  queries:
    - name: ssh-home-to-lab
      description: SSH initiated from home into the lab
      query_text: |-
        FROM sessions
        | LAST 300
        | WHERE protocol == TCP AND server_port == 22 AND server_ip == "network:lab" AND ip == "network:home"
        | KEEP ip_a, ip_b, server_ip, server_port, opened_at
      tags: [ssh, lateral]
    - name: tcp-lab-to-home
      description: TCP initiated from the lab back toward home
      query_text: |-
        FROM sessions
        | LAST 300
        | WHERE protocol == TCP AND server_ip == "network:home" AND ip == "network:lab"
        | KEEP ip_a, ip_b, server_ip, server_port, opened_at
      tags: [lateral]
  rules:
    - { name: ssh-home-to-lab, query: ssh-home-to-lab, condition_type: presence, severity: medium, interval_secs: 60, cooldown_secs: 1800 }
    - { name: tcp-lab-to-home, query: tcp-lab-to-home, condition_type: presence, severity: high,   interval_secs: 60, cooldown_secs: 1800 }
```

Apply it from the **web GUI** — the default path. Open **⇄ Config I/O**
(`/config-io`), click **Validate file…** to check it, then **Import file…** to
apply it; the page reports which sections were applied. (You can also build the
same cartography, flow matrix and alerting interactively from their own pages and
**Export** them back to this single file.)

> **Prefer the terminal?** The CLI works on the exact same bundle:
>
> ```sh
> obserae-cli config validate config.yml     # parse + validate, no changes
> obserae-cli config import   config.yml      # apply it
> obserae-cli config export                   # round-trip the live config to stdout
> ```

The full references are in [configuration.md](configuration.md),
[cartography.md](cartography.md) and [rules.md](rules.md); the Config I/O page is
documented in [web-gui.md](web-gui.md#config-io).

---

## 3. The flow matrix is your allowed baseline

A flow-matrix rule describes **legitimate** connectivity. obserae matches every
session against the matrix; anything that matches is expected, and **anything
that doesn't is the signal** worth investigating. You didn't list "lab may SSH
into home" or "home may RDP the lab" — so the day that happens, it stands out.

Open the **Flow Matrix** page (sidebar → *Flow Matrix*) to see the rules you just
imported, and to toggle or edit them. They say: internal hosts may resolve DNS
*only* against the three known resolvers, reach the internet on HTTP/HTTPS/QUIC/NTP,
and home may reach the lab's web ports. Everything else is unaccounted-for.
(Step 7 shows how to list it.)

> **Prefer the terminal?** `obserae-cli rule ls` prints the same matrix.

> **Service names vs. literal ports.** A catalogued service name (`dns`,
> `https`…) only works when the destination is a **host or group that declares
> that service** — like `public-dns` above. For a `network:` or `internet4`
> destination there is no declared service to resolve, so pin the port directly:
> `80/tcp`, `443/tcp`, `123/udp`.

References: [rules.md](rules.md), and how ports/services and the `internet4` /
`internal4` keywords work in [rules.md](rules.md#the-portservice-field).

---

## 4. Two detections, on top of the baseline

The `alerting` section turns saved NFQL queries into alert rules. The two above
fire on **lateral movement** that a homelab should never see:

- **`ssh-home-to-lab`** — an SSH session whose server side is in `lab` and whose
  other endpoint is in `home`.
- **`tcp-lab-to-home`** — any TCP connection initiated *from* the lab back toward
  home (servers shouldn't be reaching into client space).

Both use `condition_type: presence` — the rule fires whenever its query returns a
row — with a 30-minute cooldown so one noisy host doesn't spam you. In the GUI,
the **Rules** page (sidebar → *Rules*) lists the alerting rules, and the
**Detection** page shows the alerts they raise.

> **Prefer the terminal?** `obserae-cli alert ls` lists raised alerts.

(These patterns also surface in step 7, because they aren't in the allowed
baseline — the matrix and the explicit detections reinforce each other.)
Reference: [alerting.md](alerting.md). Deliver alerts to a webhook or Gotify via
the `outputs` section — see [outputs.md](outputs.md).

---

## 5. Look at what's happening

### From the web GUI

Open <http://localhost:8080>. The **Cockpit** shows live counters; **Cartography**
draws your `home`/`lab`/DNS map with live link activity; and the **Investigation**
page runs any NFQL query interactively. See [web-gui.md](web-gui.md).

### …or from the CLI

```sh
# What's been ingested?
obserae-cli status

# Last 60 seconds of raw flows
obserae-cli query 'FROM flows | LAST 60 | LIMIT 10'

# Which internal hosts are talking to the internet right now?
obserae-cli query 'FROM sessions | LAST 3600 | WHERE ip == "internal4" AND server_ip == "internet4" | KEEP ip_a, ip_b, server_ip, server_port | LIMIT 20'

# What did the matcher confirm as allowed in the last 5 minutes?
obserae-cli matches ls --since 5m
```

The full query language reference is in [nfql.md](nfql.md), with copy-paste
patterns in the [cookbook](cookbook.md).

---

## 6. Drill into a session

A "session" is the consolidation of all flows belonging to the same conversation
(both directions, same protocol, same endpoints). One TCP connection produces one
session row, regardless of how many NetFlow records described it. See
[sessions.md](sessions.md) for the model.

The **Sessions** page (sidebar → *Sessions*) is the fastest way to see *who is
talking to whom*: a filterable table of every session. Set the **destination**
chip to `lab-web`, then click a row — a drawer shows both directions, the inferred
**server** side and how it was inferred (`tcp_handshake`, `cartography`,
`iana_port`…), and the raw flows behind it.

> **Prefer a query?** The same data via NFQL — on the **Investigation** page, or
> from the CLI:
>
> ```sh
> obserae-cli query \
>   'FROM sessions
>      | LAST 3600
>      | WHERE state == "closed" AND server_ip == "host:lab-web"
>      | KEEP ip_a, ip_b, server_ip, server_port, role_method, ab_bytes, ba_bytes
>      | SORT ab_bytes DESC
>      | LIMIT 20'
> ```

---

## 7. Find traffic that matched no rule

The payoff — the closed sessions that **no flow-matrix rule accounted for**, your
"what shouldn't be happening?" view.

On the **Sessions** page, turn on the **Unmatched only** filter: it lists exactly
those sessions. This is where the SSH-into-lab and lab-to-home patterns from step
4 surface, even before an alert fires.

> **Prefer a query?** The same set via NFQL — on the **Investigation** page, or
> from the CLI:
>
> ```sh
> obserae-cli query \
>   'FROM session_matches | LAST 3600
>    > FROM sessions      | LAST 3600 | WHERE state == "closed"
>                         | PIVOT NOT session_id == session_id
>                         | KEEP ip_a, ip_b, server_ip, server_port, role_method'
> ```

---

## Where to next

- [web-gui.md](web-gui.md) — tour of every screen in the browser interface.
- [nfql.md](nfql.md) — the full query language, with recipes.
- [cartography.md](cartography.md) — describe a real network.
- [rules.md](rules.md) — write effective flow-matrix rules.
- [alerting.md](alerting.md) — build detections from saved queries.
- [operations.md](operations.md) — run obserae as a systemd service.

---

## Tear-down

If this was a throwaway trial, stop the daemon the way you started it
(`Ctrl+C`, `systemctl stop obserae`, or `docker rm -f obserae`) and remove its
data directory (`./data` for the binary, or the `obserae-data` volume for
Docker). obserae never writes outside its data directory, so cleanup is that
single step.

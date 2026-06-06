# Quickstart

This walkthrough takes you from a freshly-extracted obserae to a
running daemon, a small network map, a couple of detection rules,
and your first query — all in about 10 minutes.

We assume you have already installed obserae following
[installation.md](installation.md) and that the daemon binds to
`./data/obserae.sock`.

---

## 1. Start the daemon

```sh
mkdir -p data/parquet
./obserae --config obserae.yaml &
```

Wait until you see `INFO collector listening` and `INFO web server
listening`. The daemon is now accepting NetFlow on UDP 2055 and
serving the GUI at <http://localhost:8080>.

Check it is healthy:

```sh
./obserae-cli --socket ./data/obserae.sock status
```

You should see a version, an uptime, and zero flows (or the count
of whatever your exporters have already sent).

> **Tip.** Set a shell alias so you don't repeat `--socket` every time:
>
> ```sh
> alias obserae-cli='./obserae-cli --socket ./data/obserae.sock'
> ```

---

## 2. Describe your network (cartography)

The cartography is obserae's model of *your* infrastructure. Once
you describe networks, hosts and services, rules and queries can
refer to them by name — `dst: postgres` instead of `10.0.3.50/32`.

Save this minimal example as `cartography.yml`:

```yaml
networks:
  - name: "lan"
    cidr: "192.168.1.0/24"
    description: "Office LAN"
  - name: "dmz"
    cidr: "10.0.0.0/24"

hosts:
  - name: "webserver"
    interfaces:
      - name: "eth0"
        network: "dmz"
        ip: "10.0.0.10"
    services:
      - name: "https"
        protocol: TCP
        port: 443
        interfaces: ["eth0"]

  - name: "database"
    interfaces:
      - name: "eth0"
        network: "lan"
        ip: "192.168.1.50"
    services:
      - name: "postgres"
        protocol: TCP
        port: 5432
        interfaces: ["eth0"]

groups:
  - name: "production"
    members: ["webserver", "database"]
```

Import it. The CLI (and the GUI's Config I/O page) work on **one
consolidated bundle**, so put the block above under a top-level
`cartography:` key in a `config.yml` and import that:

```yaml
# config.yml
cartography:
  networks: [...]
  hosts: [...]
  groups: [...]
```

```sh
obserae-cli config import config.yml
obserae-cli config export                # round-trip to verify
```

The full cartography reference is in [cartography.md](cartography.md).
You can also edit the topology interactively from the **Cartography**
page of the web GUI — see [web-gui.md](web-gui.md#cartography).

---

## 3. Write your first detection rule

A rule is one *legitimate* pattern of traffic. Anything that doesn't
match a rule shows up as unaccounted traffic — that's the signal an
analyst wants to investigate.

Save this as `rules.yml`:

```yaml
rules:
  - name: webserver-to-database
    description: "Webserver opens PostgreSQL connections to the database"
    src: webserver
    src_service: "*"
    dst: database
    dst_service: postgres        # service name pins port + protocol

  - name: public-https
    description: "Anyone on the IPv4 internet can reach the webserver on HTTPS"
    src: internet4               # family-specific keyword; add a twin rule with internet6 for v6
    src_service: "*"
    dst: webserver
    dst_service: https           # service name pins port + protocol
```

> The `internet4` / `internet6` keywords are **family-specific**:
> there is no bare `internet` token that spans both. If your
> webserver is dual-stack, add a second rule with `src: internet6`
> — same structure, different family.

> The protocol is derived from the `src_service` / `dst_service`
> values — there is no separate `protocol:` field. A catalogued
> service name (`postgres`, `https`) carries its own port and
> protocol; otherwise pin it explicitly with `*/TCP` or `53/UDP`.
> See [rules.md](rules.md#the-portservice-field).

Import: add these rules under a top-level `flow_matrix:` key in the same
`config.yml` (alongside `cartography:`) and re-import the bundle:

```yaml
# config.yml
cartography: { ... }
flow_matrix:
  rules:
    - name: webserver-to-database
      ...
```

```sh
obserae-cli config import config.yml
obserae-cli rule ls
```

The full rules reference is in [rules.md](rules.md).

---

## 4. Send some traffic

If your NetFlow exporters are already pointing at obserae, traffic
will start showing up after the next export cycle (every 30–60s on
most exporters).

If you just want to play with the product end-to-end without real
traffic, open the web GUI at <http://localhost:8080> and use the
built-in **Flow Simulator** page (under *Simulation*) to generate
synthetic flows that match your cartography. See
[web-gui.md](web-gui.md#simulation) for details.

---

## 5. Look at what's happening

### From the web GUI

Open <http://localhost:8080>. The Cockpit landing page shows live
counters; the Cartography page shows your network as a graph with
live link activity. See [web-gui.md](web-gui.md).

### From the CLI

```sh
# What's been ingested?
obserae-cli status

# Last 60 seconds of traffic
obserae-cli query 'FROM flows | LAST 60 | LIMIT 10'

# Anything from outside that hit the webserver?
obserae-cli query 'FROM flows | WHERE src_addr == "internet4" AND dst_addr == "webserver"'

# What did the matcher catch?
obserae-cli matches ls --since 5m
```

The full query language reference is in [nfql.md](nfql.md).

---

## 6. Drill into a session

A "session" is the consolidation of all flows belonging to the same
conversation (both directions, same protocol, same endpoints). One
TCP connection produces one session row, regardless of how many
NetFlow records described it. See [sessions.md](sessions.md) for the
model.

```sh
# Recent closed sessions to the database tier
obserae-cli query \
  'FROM sessions
     | LAST 3600
     | WHERE state == "closed" AND ip == "database"
     | KEEP ip_a, ip_b, server_ip, role_method, ab_bytes, ba_bytes
     | SORT ab_bytes DESC
     | LIMIT 20'
```

The output names the server IP (inferred at close time) and labels
the inference method (`tcp_handshake`, `cartography`, `iana_port`…).

---

## 7. Find traffic that matched no rule

The canonical "what shouldn't be happening?" query — closed sessions
in the last hour that weren't caught by any rule:

```sh
obserae-cli query \
  'FROM session_matches | LAST 3600
   > FROM sessions      | LAST 3600 | WHERE state == "closed"
                        | PIVOT NOT session_id == session_id
                        | KEEP ip_a, ip_b, server_ip, server_port, role_method'
```

In the web GUI, the *Sessions* page has a built-in "unmatched"
filter that runs the same query for you.

---

## Where to next

- [web-gui.md](web-gui.md) — tour of every screen in the browser interface.
- [nfql.md](nfql.md) — the full query language, with recipes.
- [cartography.md](cartography.md) — describe a real network.
- [rules.md](rules.md) — write effective detection rules.
- [operations.md](operations.md) — run obserae as a systemd service.

---

## Tear-down

If you were just kicking the tires:

```sh
kill %1                # the backgrounded daemon
rm -rf data/           # database + parquet buffer + socket
```

obserae never writes outside its data directory, so a single
`rm -rf` is enough to clean up.

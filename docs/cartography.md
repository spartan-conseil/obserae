# Cartography — your network, by name

The cartography is obserae's model of *your* infrastructure. You
describe networks, hosts, services and groups **once**, and from
then on every rule and every query can refer to them by name:

```nfql
FROM flows | WHERE src_addr == "backends" AND dst_addr == "postgres"
```

instead of dragging IPs and CIDRs around.

---

## The five entities

| Entity        | What it is                                                                       |
|---------------|-----------------------------------------------------------------------------------|
| **Network**   | A CIDR block with a name, an optional VLAN id, and an optional [DHCP range](#dhcp-networks). |
| **Host**      | A machine, identified by name. Carries interfaces and services.                  |
| **Interface** | A `(host, name, network, IP)` tuple. The IP must belong to the network's CIDR.   |
| **Service**   | A `(host, name, protocol, port, [interfaces])` tuple — a port on a host's interface(s). |
| **Group**     | A named collection of hosts and/or other groups. Groups can nest, and a host can belong to several groups at once (its node sits where the plates overlap). |

### One global namespace

Networks, hosts and groups share **one** namespace. A name used
for a network cannot be reused for a host or a group. This is what
lets you write `ip == "production"` without disambiguating syntax —
the lookup is unambiguous.

Service names live in a *per-host* namespace, so every host can
declare a `ssh` service.

---

## YAML format

The canonical way to describe your topology is one YAML file. You
can import it from the CLI or drop it onto the **Data** page in the
GUI.

```yaml
networks:
  - name: "admin"
    cidr: "192.168.0.0/24"
    vlan: 10                       # optional, 1..4094
    description: "Out-of-band management"
  - name: "data"
    cidr: "192.168.3.0/24"
    vlan: 40
  - name: "office"
    cidr: "192.168.10.0/24"
    dhcp_start: "192.168.10.100"   # optional DHCP pool (see below)
    dhcp_end: "192.168.10.200"

hosts:
  - name: "pg-01"
    documentation: |               # optional free-form markdown (see below)
      # pg-01
      Primary **PostgreSQL** node. Nightly backup at 02:00.
    interfaces:
      - name: "eth0"
        network: "admin"
        ip: "192.168.0.50"
      - name: "eth1"
        network: "data"
        ip: "192.168.3.50"
    services:
      - name: "ssh"
        protocol: TCP
        port: 22
        interfaces: ["eth0"]
      - name: "postgres"
        protocol: TCP
        port: 5432
        interfaces: ["eth1"]
        description: "Primary"

groups:
  - name: "postgres"
    members: ["pg-01", "pg-02"]
  - name: "databases"
    members: ["postgres", "redis"]   # groups can nest
```

### Validation rules

The daemon refuses any import that violates one of:

- Names are unique across networks/hosts/groups.
- The names `internet4`, `internet6`, `internal4`, `internal6`,
  `any4` and `any6` are reserved keywords and cannot be redeclared.
- A network's `cidr` parses to a canonical form (no host bits set).
  Any prefix length is accepted, including the default route
  `0.0.0.0/0` and `::/0`.
- VLAN id is in `1..4094` (or omitted).
- A DHCP range, if present, sets **both** `dhcp_start` and `dhcp_end`,
  with both inside the network's CIDR and `dhcp_start <= dhcp_end`.
- Interface name is non-empty and unique on its host.
- An interface's `ip` parses and lies inside its network's CIDR.
  IPv4 and IPv6 are both accepted. The reserved networks have
  their own per-family routability rule: `internet4` only accepts
  a publicly-routable IPv4 (no RFC1918, loopback, link-local,
  CGNAT, multicast, reserved); `internet6` only accepts a global
  unicast IPv6 (no ULA, loopback, link-local, multicast).
  `internal4` / `internal6` are the **exact complement** — they
  only accept the non-routable addresses of their family (RFC1918 /
  ULA, loopback, link-local, etc.). `any4` / `any6` accept any
  address of the matching family.
- Service name is non-empty and unique on its host.
- A service's `protocol` is one of: `TCP`, `UDP`, `ICMP`, `IGMP`,
  `GRE`, `AH`, `ESP`, `OSPF`, `SCTP`, `ICMPv6`. Names are
  case-insensitive.
- `TCP`, `UDP` and `SCTP` services declare a port in `1..65535`.
  Every other protocol (the layer-3 ones — ICMP, IGMP, GRE, AH,
  ESP, OSPF, ICMPv6) must **not** declare a port.
- A service binds to at least one interface that exists on the same
  host.
- Group members exist as hosts or as previously-declared groups.
- Group nesting is acyclic.

A failed import never mutates the database — the operation is
atomic. Use `cartography validate FILE` to dry-run the checks.

---

## Editing the cartography

### Bulk (YAML)

The topology is the `cartography:` section of the single consolidated
config bundle (CLI `obserae-cli config …`, or the GUI's Config I/O page):

```sh
obserae-cli config validate config.yml      # checks only
obserae-cli config import   config.yml      # apply (cartography section replaces the topology)
obserae-cli config export   --output a.yml  # pull the whole config, cartography included
```

### Per-entity (CLI)

```sh
# Create
obserae-cli network add prod-vlan20 --cidr 10.20.0.0/16 --vlan 20
obserae-cli host add srv-db-01

# Scoped under a host
obserae-cli interface add eth0 --host srv-db-01 \
    --network prod-vlan20 --ip 10.20.0.5
obserae-cli service add postgres --host srv-db-01 \
    --protocol TCP --port 5432 --interfaces eth0

# Groups
obserae-cli group add backend --members srv-db-01,srv-web-01
obserae-cli group update backend --add-member srv-monitoring
obserae-cli group update backend --rm-member srv-web-01

# Read
obserae-cli network ls
obserae-cli host show srv-db-01
obserae-cli group ls --json

# Rename
obserae-cli host update srv-db-01 --name srv-db
```

### In the web GUI

The **Cartography** page is a live interactive graph. Right-click
any node for create / rename / delete actions, or right-click the
empty canvas to create a new entity. See
[web-gui.md](web-gui.md#cartography).

#### One editor at a time (edit lock)

To stop two admins from silently overwriting each other's changes, the
cartography page is **read-only by default**. To make changes you click
**Edit**: this takes the **edit lease** and turns the badge green
(*Editing*). Your create / rename / delete / move actions then work
normally and each is saved as you go. Click **Done** to leave edit mode
and release the lease — there is nothing to "save", changes persist
immediately.

While you hold the lease, **everyone else is read-only**: a banner names
the current editor (*"Cartography is being edited by …"*), the mutation
controls are disabled, and dragging a node snaps it back. They can still
pan, zoom, search and inspect everything, and a **Request edit** button
takes over the moment the lease is free.

**Only one editing session can be open at a time** — including the *same*
admin in two browser windows. Clicking Edit in a second window is refused
until the first clicks Done, so it is impossible to reproduce the
double-edit problem by opening two tabs.

The lease is held while the editing tab stays on the page, released when
you click Done or leave the page, and — as a safety net — it **expires on
its own after 90 seconds** if a tab crashes or loses connectivity (the
banner shows a live countdown). The lock is also enforced on the server,
so a cartography change from anyone who does not hold the lease is
rejected even outside the GUI. It is an in-memory lease — restarting the
daemon clears it. (It guards *interactive* editing; a YAML re-import from
[Config I/O](configuration.md) is a separate, atomic operation.)

#### Cloning a host

A host's drawer has a **Clone** button — handy for a cluster of
machines that share the same interfaces and services and differ only
by name and IP. It opens a small form **pre-filled** with:

- a **suggested name**: the trailing number is incremented keeping its
  padding (`web-01` → `web-02`), or `-01`, `-02`… is appended when the
  name has no number (`proxy` → `proxy-01`);
- for each interface, the **next free IP** above the source's, within
  the same network.

Adjust the name or any IP if you like, then **Clone**. The copy carries
over every interface, service, interface binding, group membership and
the source's colour/icon, and is selected on the graph once created.

#### Documenting an entity

Every host, network and group can carry a **documentation** note written
in **markdown** — a place for ownership, runbooks, or any context that
belongs next to the topology (the short *description* on a network is a
one-line summary; documentation is for the longer story).

Click any node and the drawer shows a **Documentation** section with your
markdown **nicely rendered** — headings, lists, tables, code blocks and
links, not raw text. Two buttons sit there:

- **Expand** opens the documentation full-size in a modal for comfortable
  reading;
- **Edit** (in both the drawer and the modal) opens a plain-text editor on
  the raw markdown. Type, **Save**, and the rendered note refreshes.

Documentation is part of your topology, so it is included whenever you
export the cartography or the consolidated configuration — back it up and
move it between instances like everything else.

### Building the map from your traffic: the discovery funnel

Two toolbar buttons turn observed flows into a cartography in two steps —
first your networks, then your machines.

**Network Discovery** (stage 1) looks at the traffic and proposes the
**subnets** behind it. It works **only on non-routable (private) space**
— RFC1918 (`10/8`, `172.16/12`, `192.168/16`), CGNAT (`100.64/10`) and
IPv6 ULA (`fc00::/7`) — because those are the addresses that describe
*your* segments; routable peers are external and handled by IP Discovery
below. It clusters the private IPs it sees into candidate networks (a
`/24` per LAN by default, widening to `/23`, `/22`… when it detects a
contiguous, properly-aligned range), and lists each one with the number
of distinct IPs and the traffic volume behind it. Click **+ Declare** to
open the **+ Network** form pre-filled with the candidate's CIDR and a
suggested name — review the name (you can change anything), then submit.
The new network appears on the map and the candidate drops off the list.
Subnets you have already declared are never proposed again.

**IP Discovery** (stage 2, formerly *Orphan IPs*) lists every individual
IP seen in traffic over the last 24 hours that has no interface yet —
the machines to add as hosts. A switch in the drawer header — **All
IPs** / **Declared only** — hides the rows tagged `outside known CIDRs`
so you can focus on the IPs that already fall inside one of your declared
networks (the easiest to adopt). Each row offers **+ Add** (create a new
`?<ip>` host with its inferred services) or **⇢ Merge** (attach the IP as
a new interface on an existing host). The filter is session-only:
leaving the page resets it to "All IPs".

Typical flow: open **Network Discovery**, declare the subnets it finds,
then open **IP Discovery** — the IPs inside those new networks are now
ready to adopt as hosts.

### Colours and icons

Colour, icon and OS badge are chosen in the entity's **configuration
form** — open it from the **Edit** button in the entity's drawer, or
right-click the node and pick *Edit* (when creating a new
host/network/group you can set them straight away). In the form you can:

- **Pick a colour** — choose a swatch to tint the node. Related hosts
  get a shared auto-colour by default; a custom swatch overrides it.
- **Set an icon** — give the node an icon so the map reads at a glance
  (a server, a firewall, a database…). In the **Icon** section, type a
  search term to browse matching icons and click one to apply it, or
  type an id directly in the form `mdi:server`. Icons come from the
  [Iconify](https://icon-sets.iconify.design/) collections, so the id
  is `set:name` (e.g. `mdi:router`, `logos:docker`). Use **Clear** to
  remove it.
- **Set an OS badge** *(hosts only)* — a small second icon shown at the
  **bottom-left** of the host, to mark its operating system
  (`logos:ubuntu`, `logos:microsoft-windows-icon`, `simple-icons:apple`…).
  It keeps the logo's own colours. Search by name (try "ubuntu",
  "windows", "linux") in the **OS badge** section.

Everything takes effect when you **Save** the form. These are visual
only — they don't change how rules or NFQL match — and all are undoable
with **Ctrl+Z**. They are saved with the cartography, so exporting and
re-importing your YAML keeps every colour, icon and OS badge.

---

### Alert & enrichment indicators

The map tells you, at a glance, which hosts need attention. A small badge
appears at the **bottom-right** of a host:

- 🔺 **Red triangle** — the host has one or more **active alerts**
  (a detection rule fired on it). This is the strongest signal.
- 🔶 **Orange triangle** — the host has no alert, but one of its IPs is
  listed in a **threat-intelligence** feed. Worth a look.
- 🔵 **Blue info dot** — the host has no alert and no threat, but one of
  its IPs is known to **IP enrichment** (e.g. a cloud provider range), or
  it only has low-importance `info` alerts.

**Hover** a badged host to see a quick summary of its alerts and
enrichment. **Click** the host to open its drawer, which now shows:

- an **Active alerts** list — each row links to the rule that fired
  (*opens the Detection page filtered to that rule*) and a **Triggers**
  link that opens Detection filtered to *this host*;
- an **IP enrichment** table — the source (AWS, a threat feed…), what it
  says, and the matching network range.

The badges update live: they refresh whenever the cartography changes and
whenever a new alert fires, so you never have to reload the page.

> Hosts with only private (internal) IPs won't get an enrichment badge —
> IP enrichment only classifies public addresses. Alerts, however, light
> up any host regardless of its addressing.

---

## DHCP networks

Some segments — office LANs, Wi-Fi, guest networks — hand out
addresses dynamically with DHCP. You can't model each lease as a
host: they rotate constantly, and they'd flood the IP Discovery list with
hundreds of `192.168.10.x` you'll never name.

Instead, tell obserae which slice of the network is the DHCP pool.
Set a **start** and **end** address on the network:

```yaml
networks:
  - name: "office"
    cidr: "192.168.10.0/24"
    dhcp_start: "192.168.10.100"
    dhcp_end: "192.168.10.200"
```

or, in the GUI, open the network's edit form and fill the **DHCP
range** fields (both or neither). The per-entity CLI does not have a
flag for it — use the YAML or the GUI.

Once a network has a DHCP range:

- **Dynamic IPs stop being discovered.** An address seen in the pool
  shows up as `office · 192.168.10.142` across the Sessions and
  Riverview views — attached to the network, not flagged as unknown.
- **Static reservations keep their name.** If you *do* declare an
  interface inside the pool (a printer, the gateway), it keeps its
  host name — the exact match always wins over the pool label.
- **The IP Discovery list stays clean.** Pool addresses no longer appear
  there. (Network and broadcast addresses — the `.0` and `.255` of a
  `/24`, for instance — are filtered from IP Discovery too: they're never
  real machines.)
- **The graph shows the pool.** On the Cartography page each network
  with a DHCP range gets a **hexagonal companion node** tethered to it
  by a dashed edge. The hexagon's label is `DHCP · N`, where N is the
  count of distinct in-range IPs seen over the last 24 hours — so the
  pool's activity is visible at a glance, even dezoomed. Clicking the
  hexagon opens a **dedicated DHCP drawer** showing the bounds and the
  live leases. The network's own drawer still carries the same DHCP
  row and lease list, so either path works. The hexagon is purely a
  view of the network: it has no Edit / Delete actions of its own —
  the range itself is edited via the parent network's form.

You can also **query** the two halves of the network by name —
`office.dhcp` (the pool) and `office.static` (everything else) — in
both NFQL and detection rules:

```nfql
# who is active on the DHCP pool right now?
FROM sessions | LAST 3600 | WHERE ip == "office.dhcp"

# a dynamic client talking to the IPv4 internet (use internet6 for v6)
FROM sessions | WHERE ip == "office.dhcp" AND ip == "internet4"
```

See [nfql.md](nfql.md#cartography-references) and
[rules.md](rules.md) for more.

---

## Deleting things — impact preview

Every `rm` first asks the daemon what will cascade, prints a
summary, then prompts:

```text
$ obserae-cli network rm admin
Deleting network admin will:
  - delete 11 entities
  - modify 0 entities
Proceed? [N/y/I] I
Deletes:
  - network admin
  - interface bastion:eth0
  - interface proxy:eth0
  …
Proceed? [N/y/I] y
deleted 11 entities.
```

- `N` (default) aborts.
- `y` commits.
- `I` lists every affected entity, then re-prompts.
- `--yes` skips the prompt entirely (scripts).
- `--dry-run` shows the impact without ever calling delete.

The GUI shows the same impact preview as a side drawer.

---

## Live rule recompilation

Every cartography mutation triggers a recompile of every detection
rule that references the touched entity (directly or via a group).
Practical consequences:

- **Add a host to `group:backends`** → every rule that mentions
  `backends` immediately applies to the new host's interfaces.
- **Rename a network** → every rule that referenced it by
  `network:OLD` atomically updates.
- **Delete a host referenced by a rule** → the rule is *quarantined*
  (its `last_compile_error` is populated, its matcher cursor is
  paused). Fix the cartography or the rule to clear it.

There is **no manual "recompile" command** — every supported edit
triggers it.

---

## References used by rules and NFQL

Both detection rules (`src:`, `dst:`) and NFQL string literals
compared to `INET` columns accept the same grammar:

| Form                       | Meaning                                                      |
|----------------------------|--------------------------------------------------------------|
| `any4`                     | Reserved keyword: every IPv4 address (`0.0.0.0/0`)            |
| `any6`                     | Reserved keyword: every IPv6 address (`::/0`)                 |
| `internet4`                | Public unicast IPv4 — `0.0.0.0/0` minus RFC1918, loopback, link-local, CGNAT, multicast and reserved ranges |
| `internet6`                | Public unicast IPv6 — `::/0` minus ULA (`fc00::/7`), loopback, link-local (`fe80::/10`), multicast and IPv4-mapped ranges |
| `internal4`                | Non-routable IPv4 — the **exact complement** of `internet4` (RFC1918, loopback, link-local, CGNAT, multicast, reserved) |
| `internal6`                | Non-routable IPv6 — the **exact complement** of `internet6` (ULA, loopback, link-local, multicast, mapped) |
| `host:NAME`                | Every interface IP of the named host                         |
| `host:NAME:IFACE`          | One specific interface IP                                    |
| `group:NAME`               | Every interface IP of every member host (recursive)          |
| `network:NAME`             | The whole CIDR of the named network                          |
| `NAME.dhcp`                | Just the network's DHCP pool (needs a [DHCP range](#dhcp-networks)) |
| `NAME.static`              | The network's CIDR **minus** its DHCP pool                   |
| `NAME` (bare)              | Looked up across networks / hosts / groups                   |
| `NAME:IFACE` (bare)        | Same as `host:NAME:IFACE`                                    |

The reserved keywords are **family-specific**: `internet4` /
`internet6`, `internal4` / `internal6` and `any4` / `any6` each
expand to one IP family only. There is no bare `internet` /
`internal` / `any` keyword that spans both — if you need both
families, declare two rules (or two NFQL clauses) using the v4 and
v6 variants side by side. The keyword definitions are evaluated by
the same code path in the rule engine and the NFQL planner, so a
rule and a query that both reference `internet4` (or `internal4`)
see the exact same CIDR set.

`internal4` / `internal6` are the **exact complement** of `internet4`
/ `internet6` within their family: every routable address satisfies
one, every non-routable address satisfies the other, never both. Use
`internal4` to say "anything on the LAN" without spelling out the
RFC1918 / loopback / link-local CIDRs.

---

## Complete example

The [quickstart](quickstart.md#2-describe-your-network-cartography)
walks through a minimal topology you can copy and adapt. A realistic
three-tier setup looks like this:

- 5 VLANs (public, admin, egress, frontend, data).
- Edge hosts (DNS, bastion, proxy).
- Load balancers, backend tier, database tier (Postgres + Redis).
- Composite groups so you can write `ip == "production"` or
  `ip == "databases"` and get the obvious answer.

Build it incrementally with the CLI (`network add`, `host add`, …) or
author one YAML file and `cartography import` it in one shot.

Adapt it to your own infrastructure as a starting point.

---

## Where to next

- [rules.md](rules.md) — write detection rules against the entities
  you just declared.
- [nfql.md](nfql.md) — query your traffic using the same names.
- [web-gui.md](web-gui.md#cartography) — visual editor for the
  topology.

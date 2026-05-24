# Detection rules

A rule is one **legitimate** (or one **forbidden**) pattern of
traffic that obserae's matcher looks for in your sessions. Each
rule is authored symbolically — `src: backends, dst: postgres,
dst_service: postgres` — and the engine takes care of turning it
into the underlying IP/port comparisons.

The interesting signals are:

- a session that **matches no rule** at all (unexpected traffic);
- a session that matches a rule it **shouldn't** (policy violation).

The GUI's *Sessions* page can filter directly on the first case
("unmatched only"). The CLI uses an NFQL anti-pivot — see
[nfql.md](nfql.md#cross-pipeline-lookups).

---

## Why sessions, not flows?

obserae folds raw NetFlow records into bidirectional **sessions**
before the matcher runs. One conversation = one session row,
regardless of how many flow records described it. That means:

- The matcher inspects 10×–100× fewer rows per tick.
- Each match already carries the inferred role
  (`server_ip`, `role_method`, `role_conf`) — see [sessions.md](sessions.md).

The trade-off: a match fires only after the session has **closed**
(FIN / RST / idle timeout), so worst-case detection latency is
`matcher.interval` plus the protocol's idle window. Default tuning
puts that around 1 minute.

---

## YAML format

```yaml
rules:
  - name: backends-to-postgres
    description: "Backends opening PostgreSQL connections"
    src: backends                  # any cartography reference
    src_iface: eth1                # optional — only valid for host refs
    src_service: "*"               # port/service on src side (see below)
    dst: postgres
    dst_iface: eth1
    dst_service: postgres
    enabled: true                  # default true; matcher skips disabled rules
    tags: [critical, datastore]    # optional — free-form labels, searchable
```

There is **no separate `protocol:` field**. The protocol is derived
from the `src_service` / `dst_service` values (see
[The port/service field](#the-portservice-field) below).

A rule has **no orientation** field. Sessions are non-oriented
(endpoints are folded into canonical IP order), so the matcher's
predicate is symmetric: a rule `src=A, dst=B` matches a session
whether A is on the `ip_a` side or the `ip_b` side. If you need to
know which side initiated, look at the session's `server_ip` and
`role_method`.

### Required fields

- **`name`** — unique across rules.
- **`src`**, **`dst`** — both required; either can be `any4` / `any6` or `internet4` / `internet6` (family-specific keywords — see [cartography.md](cartography.md#reference-syntax-used-by-rules-and-nfql)).
- **`src_service`**, **`dst_service`** — required; use `"*"` for "any port". See [The port/service field](#the-portservice-field).

### Optional fields

| Field           | Type     | Default | Behavior                                                              |
|-----------------|----------|---------|------------------------------------------------------------------------|
| `description`   | string   | empty   | Free-form, shown in the GUI and `rule show`.                          |
| `src_iface`     | string   | none    | Restrict a host reference to a single interface. Cannot mix with non-host kinds. |
| `dst_iface`     | string   | none    | Same on the dst side.                                                  |
| `enabled`       | bool     | `true`  | When false, the rule lives in the DB but the matcher skips it. Use to stage a rule before turning it on. |
| `tags`          | []string | `[]`    | Free-form labels for grouping rules. Searchable in the Flow Matrix via `tag:foo`. Lowercased, deduplicated, and stored sorted. |

### The port/service field

`src_service` and `dst_service` carry **both** the port and the
protocol — there is no longer a separate `protocol:` field. Each
side accepts one of:

| Value           | Meaning                                                |
|-----------------|--------------------------------------------------------|
| `*`             | Any port (protocol unconstrained on this side)         |
| `*/TCP`         | Any port, protocol pinned (see list below)             |
| `53/UDP`        | A specific port **and** protocol                       |
| `https`         | A catalogued service name — resolves to its port + protocol from the cartography |

Supported protocol names (case-insensitive): `TCP`, `UDP`, `ICMP`,
`IGMP`, `GRE`, `AH`, `ESP`, `OSPF`, `SCTP`, `ICMPv6`. A port is
only meaningful for `TCP`, `UDP` and `SCTP` — a form like `80/IGMP`
is rejected because IGMP does not carry an L4 port. Use `*/IGMP`,
`*/GRE`, … to match those protocols.

A **bare port without a protocol** (`53`) and **port ranges** are
rejected.

The protocol is **derived** from the two sides:

- You must pin the protocol on **at least one** side, otherwise the
  rule is rejected (there is no `ANY` protocol any more).
- If both sides pin a protocol and they **conflict** (`*/TCP` on one
  side, `53/UDP` on the other), the rule is rejected.

`internet4` / `internet6`, `any4` / `any6` and `network` references
accept `*`, `*/PROTO` and `PORT/PROTO` (so `internet4 -> 53/UDP`
works), but **not** a service name — service names are reserved for
`host` / `group` references. With `*/PROTO` (or `*`), the compiler
does **not** restrict the destination IPs to interfaces that bind a
matching service, since there is no service name to look up: every
CIDR in the endpoint is emitted as-is.

### Reference syntax for `src` / `dst`

Same as NFQL — bare names (looked up across hosts/groups/networks),
`host:NAME[:IFACE]`, `group:NAME`, `network:NAME`, the DHCP
projections `network:NAME.dhcp` / `network:NAME.static` (when the
network has a [DHCP range](cartography.md#dhcp-networks)), and the
family-specific reserved keywords `any4` / `any6` and `internet4` /
`internet6`. See
[cartography.md](cartography.md#reference-syntax-used-by-rules-and-nfql)
for the full table.

For example, "office DHCP clients may only reach internal DNS":

```yaml
rules:
  - name: office-dhcp-dns-only
    src: "office.dhcp"
    src_service: "*"
    dst: "network:dns-servers"
    dst_service: 53/UDP
```

In the **Flow Matrix** page (`/rules`) the source / destination
picker is autocomplete-driven — you click a suggestion, you don't
type free text. The DHCP projections show up on demand: type a dot
(`office.`) or the keyword `dhcp` / `static` and the picker offers
`network:office.dhcp` and `network:office.static` for every network
that has a declared range. Typing just `office` keeps the picker
focused on the bare network, so the common case stays uncluttered.

---

## Reading a rule

```sh
obserae-cli rule show backends-to-postgres
```

```
name:            backends-to-postgres
description:     Backends opening PostgreSQL connections
src:             backends
src_service:     *
dst:             postgres
dst_iface:       eth1
dst_service:     postgres
enabled:         true
expansions:      24
tags:            [critical, datastore]
last_compile_error:
```

The `expansions` count is the number of concrete IP/port tuples the
rule compiled to. A high count is fine — each row is a 5-tuple of
integers / INETs that DuckDB joins through very fast.

`last_compile_error` is empty for a healthy rule. A non-empty value
means the rule is **quarantined** (see below).

---

## Managing rules

### Bulk YAML

```sh
obserae-cli rules validate rules.yml
obserae-cli rules import   rules.yml
obserae-cli rules export   --output rules.yml
```

`rules import` is a **full atomic replacement** — every rule not in
the YAML is removed. Use per-entity commands for incremental edits.

### Per-entity

```sh
obserae-cli rule add backends-to-redis \
    --src backends --dst redis \
    --src-service '*' --dst-service redis \
    --description "Backends caching to Redis"

obserae-cli rule ls
obserae-cli rule update backends-to-redis --enabled=false
obserae-cli rule rm     backends-to-redis [--yes] [--dry-run]
```

### In the GUI

The **Rules** page offers create / edit / enable-disable / delete
actions with chip pickers for `src`, `dst` and `tags`. See
[web-gui.md](web-gui.md#rules).

---

## Searching rules

The Flow Matrix search box understands a small set of operators.
Multiple terms are AND-ed together; a term without a known prefix
is a free-text search.

| Term            | Matches a rule when…                                                                                          |
|-----------------|---------------------------------------------------------------------------------------------------------------|
| `tag:critical`  | …it carries the tag `critical`.                                                                               |
| `proto:tcp`     | …its derived protocol is TCP (also `udp`, `icmp`, etc.).                                                      |
| `port:443`      | …any of its expansions has source or destination port 443.                                                    |
| `host:web-01`   | …its `src` or `dst` references `host:web-01`, **or** references a group / network whose membership contains `web-01`. |
| `group:lan`     | …its `src` or `dst` literally references `group:lan`.                                                         |
| `network:dmz`   | …its `src` or `dst` literally references `network:dmz`.                                                       |
| `service:ssh`   | …`src_service` or `dst_service` contains `ssh` (substring, before catalogue resolution).                      |
| `https`         | Free-text — matches name, description, src/dst refs, services, tags, **and** any resolved host name (so `web-01` finds rules that target `group:web` if `web-01` is a member). |

Examples:

```
tag:critical                    # every rule tagged critical
proto:tcp port:5432             # TCP rules touching port 5432
host:srv-web service:https      # rules covering srv-web on https
tag:edge tag:external           # rules tagged both edge AND external
```

Typing in the search input debounces 200 ms before re-querying,
so the table follows your typing smoothly.

---

## Spotting redundant rules

When two rules cover overlapping traffic — for example
`group:web → internet4:443` (wide) and
`host:web-01 → internet4:443` (narrow, a member of the group) —
the daemon detects it and exposes it in the GUI.

- In the **table**, the narrow rule's name shows a small `⊂ N`
  badge meaning "covered by N other rule(s)". Click the row to see
  who.
- In the **drawer**, a new **Relations** section lists the rules
  that cover the current one ("covered by") and the rules the
  current one covers ("covers"). Each entry is a clickable button
  that pivots the drawer to that rule.
- When the current rule is **strictly covered** by another rule
  that is still enabled, a *"Disable this redundant rule"* button
  appears. Clicking it flips `enabled=false` — it never deletes,
  and the wider rule keeps catching the traffic.

The detector recognises three kinds of relations: `subset` (every
match of A is also a match of B), `equal` (two rules cover the
exact same flow set) and `overlap` (the rules intersect without
containment). The full algorithm is described in
[../docs/rules.md#rule-relations](../docs/rules.md#rule-relations).

The relations are recomputed automatically after every rule
mutation **and** after every cartography mutation — moving a host
into a group is enough to surface new relations on the very next
table reload.

---

## Inspecting what a rule has caught

```sh
obserae-cli matches ls                                # last 50, all rules
obserae-cli matches ls --rule public-https --limit 200
obserae-cli matches ls --since 1h
obserae-cli matches ls --since 2026-05-01T12:00:00Z
obserae-cli matches ls --json | jq '.[]'
```

Each match row carries the canonical session endpoints
(`ip_a:port_a` ↔ `ip_b:port_b`), the protocol, and the inferred
role columns (`server_ip`, `server_port`, `role_method`,
`role_conf`).

In the GUI, click any rule on the **Rules** page to see a chart of
its matches over the last 24 hours plus a table of recent matches.

---

## Common patterns

### Stage a rule before turning it on

Add it with `enabled: false`, inspect its expansions and what it
*would* have caught (run an equivalent NFQL query on closed
sessions for a feeling), then `rule update --enabled=true`.

### Service binding constrains interfaces

When a rule names a `src_service` or `dst_service` (other than `"*"`),
the compiler only emits the IPs of interfaces the service is bound
to. Example:

```yaml
- name: bastion-to-prod-ssh
  src: bastion              # 1 host × 1 admin iface  = 1 CIDR
  dst: production           # 9 hosts × 1 ssh iface  = 9 IPs (only ssh-bound!)
  src_service: "*"
  dst_service: ssh          # service name pins port + protocol (TCP/22)
```

That produces **9 expansions** rather than 26 you'd get with
`dst_service: "*"` (because the rule only targets the ssh-bound
interfaces, not every interface of every host).

### Catch traffic that matched no rule

The canonical "what shouldn't be happening?" question. Run this in
NFQL:

```nfql
FROM session_matches | LAST 3600
> FROM sessions      | LAST 3600 | WHERE state == "closed"
                     | PIVOT NOT session_id == session_id
                     | KEEP ip_a, ip_b, server_ip, role_method
```

In the GUI, the *Sessions* page has an **Unmatched only** filter
that runs this for you.

### Disable a noisy rule temporarily

```sh
obserae-cli rule update X --enabled=false
```

Re-enabling later resumes the matcher cursor where it stopped — no
historical re-match storm. To remove the rule and its history
entirely, use `rule rm X`.

### Force a rebuild

There is no separate "recompile" command. Every supported edit
(rule update, cartography mutation) triggers it implicitly. If you
really need to force a rebuild without changing content (rare — for
example, after a daemon upgrade), edit the rule's description:

```sh
obserae-cli rule update X --description "..."
```

That bumps the revision and re-emits expansions.

---

## Quarantined rules

A rule references entities in the cartography. If a cartography
mutation removes one of those entities (or a typo references a
missing host), the next recompile fails, and the rule is
**quarantined**:

- It stays in the database with `enabled=true`.
- Its matcher cursor is paused — it produces zero matches.
- `last_compile_error` is populated with the reason.

`obserae-cli rule ls` shows the column:

```
NAME                  ENABLED  EXPANSIONS  LAST_COMPILE_ERROR
backends-to-postgres  true            24
ssh-from-old-host     true             0  host "old-host": not found
```

To clear it, either restore the missing entity in the cartography,
update the rule to point at a different reference, or delete the
rule.

---

## Where to next

- [sessions.md](sessions.md) — understand the inputs the matcher
  consumes.
- [nfql.md](nfql.md) — write your own ad-hoc detections without
  authoring permanent rules.
- [cartography.md](cartography.md) — refine the topology your rules
  depend on.

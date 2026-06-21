# Writing a rule set

This is the complete reference for authoring an obserae **rule set** (also
called a *rule pack*): the file format, every field, the dependency
("requirement") notation, versioning, the vocabulary, the rule syntax, and
the install/upgrade/delete lifecycle.

If you only want to *use* the bundled pack, see
[Rule sets](rulesets.md). For the query language used inside rules, see
[NFQL](nfql.md).

---

## 1. What a rule set is

A rule set is a **single YAML file**. It does two things:

1. It **defines a vocabulary** of standard attributes you attach to your
   cartography — network *zones* and *environments*, host *roles*, and
   service *purposes*. This vocabulary is what makes detection portable: a
   rule written against `role:std.workstation` works on any network once the
   operator tags their hosts.
2. It **ships detection rules** written against that vocabulary. On install,
   each rule becomes a read-only alerting rule (a saved NFQL query plus a
   firing condition) that the evaluator runs on a schedule.

A pack is installed explicitly (Rule Sets page or CLI). Its rules are
**read-only**: an operator can enable, disable or *duplicate* them, but the
file remains the single source of truth.

---

## 2. File at a glance

A pack has three top-level sections: `package`, `attributes`, `rules`.

```yaml
package:
  maintainer: example corp
  version: 1.0.0
  last_update: 2026-06-20
  id: example.baseline
  requirements:
    - std.community>=0.1.0      # optional dependency

attributes:
  zone:
    - name: example.crown-jewels
      comment: Segment hosting the most sensitive systems.
  purpose:
    - name: example.payments-api
      comment: Internal payments API.
      ports:
        - 8443/tcp

rules:
  payments-api-from-user-zone:
    description: A user-zone host reached the payments API directly.
    query: 'FROM flows | LAST 300 | WHERE src_addr == "zone:std.user" and server_port_proto == "purpose:example.payments-api"'
    condition: presence
    severity: high
    cadence: 15m
    cooldown: 1h
    remediation: Route payment access through the approved gateway only.
    tags: [segmentation, payments]
```

> **Validation rule:** every key is checked. A typo in any field name (e.g.
> `severty:`) fails the import with a clear message — there is no silent
> "unknown field".

---

## 3. The `package` block

Metadata identifying the pack.

| Field | Required | Type | Meaning |
|---|---|---|---|
| `id` | **yes** | string | Globally unique pack identifier. Convention: lowercase, dot-separated (`vendor.name`). It prefixes every rule id and is added as a tag on every rule. |
| `maintainer` | **yes** | string | Who publishes/owns the pack. Free text. |
| `version` | **yes** | semver | `MAJOR.MINOR.PATCH` — see [Versioning](#5-versioning). |
| `last_update` | no | string | Human date, free text (`2026-06-20`). Informational only. |
| `requirements` | no | list of strings | Dependencies on other packs — see [Requirements](#6-requirements-dependencies). |

The `id` is the pack's **namespace**. It is used to:

- build each rule's full id: `<package.id>.<rule-short-id>`;
- tag every rule (so you can filter alerts by pack);
- detect upgrades and conflicts (two installs with the same `id` are the
  same pack at different versions).

---

## 4. Naming and namespaces

Attribute values and the pack id share one rule: **prefix everything with a
namespace you own** so two packs never collide. The bundled pack uses
`std.*` (e.g. `std.dns`, `role:std.workstation`, pack id `std.community`).
For your own pack pick a distinct prefix (`acme.*`, `example.*`, …).

- Attribute value names **may contain dots** (`std.web.server`,
  `acme.payments-api`). Dots are just part of the name; they do not imply a
  hierarchy.
- Keep names lowercase and stable: renaming a value in a new version is a
  *new* value (the old assignments are not migrated).

---

## 5. Versioning

`version` is a three-part number `MAJOR.MINOR.PATCH`. Missing trailing parts
default to `0`, so `1.2` == `1.2.0` and `1` == `1.0.0`. Comparison is
numeric, not lexical (`1.0.10 > 1.0.9`).

How the version drives installs:

| Situation | Result |
|---|---|
| Pack `id` not installed | **Install**. |
| Same `id`, file version **higher** than installed | **Upgrade**. Pack content is replaced; each rule's enabled/disabled state is **preserved by rule id**. |
| Same `id`, file version **equal or lower** | **Rejected** (downgrade). Bump the version to re-import. |

Bump the version on **every** change you want to ship — otherwise an
upgrade is refused.

---

## 6. Requirements (dependencies)

A pack can require another pack — typically to reuse its attribute
vocabulary. Requirements live under `package.requirements` as a list of
constraint strings.

### Notation

Each entry is `<pack-id><operator><version>`:

```
std.community>=0.1.0
acme.base==2.0.0
example.shared>1.4
std.community            # bare id: any installed version
```

- **Operators:** `<`, `<=`, `>`, `>=`, `==`.
- **Version:** semver, same rules as `package.version` (missing parts → 0).
- **Bare id (no operator):** "this pack must be installed, any version".

The operator characters are detected as the first run of `<`, `>`, `=` in
the string; everything before is the pack id, everything after is the
version. Whitespace around the parts is ignored, so
`std.community >= 0.1.0` is also valid.

### Behavior

- **On import:** every requirement must be **installed** and satisfy its
  constraint. If a dependency is missing or too old, the import is rejected
  with an explicit message (e.g. *"requires `std.community>=0.1.0` but
  0.0.9 is installed"*). Install the dependency first.
- **A pack's rules may reference attributes its dependency defines.**
  Validation overlays the pack's own declared vocabulary on top of the
  installed one, so both your new values and a dependency's values resolve.
- **On delete:** a pack that another installed pack depends on **cannot be
  deleted** until the dependent is removed first. The error lists the
  dependents.

### Why dependencies

Split a large vocabulary into a shared base pack and thinner rule packs on
top. The base ships the zones/roles/purposes; the rule packs `require` it
and only add rules. Consumers install the base once.

---

## 7. The `attributes` block (the vocabulary)

Four attribute kinds, grouped by the entity they attach to:

| Key | Attaches to | Nature | NFQL prefix |
|---|---|---|---|
| `zone` | networks | IP-based | `zone:` |
| `environment` | networks | IP-based | `environment:` |
| `role` | hosts | IP-based | `role:` |
| `purpose` | services | port/protocol-based | `purpose:` |

Each kind holds a list of values. A value has:

| Field | Required | Applies to | Meaning |
|---|---|---|---|
| `name` | **yes** | all | The value (may contain dots). What operators pick in the GUI and what rules reference. |
| `comment` | recommended | all | One-line description shown in dropdowns and docs. |
| `ports` | **yes for purpose, forbidden otherwise** | purpose only | List of `PORT/PROTO` the purpose maps to. |

### Purpose ports

Each port is `PORT/PROTO`:

```yaml
purpose:
  - name: std.dns
    comment: Domain Name System.
    ports: [53/udp, 53/tcp]
  - name: std.https
    comment: HTTP over TLS.
    ports: [443/tcp]
```

- `PORT` is 1–65535.
- `PROTO` is a protocol **that carries a port**: `tcp`, `udp` or `sctp`
  (case-insensitive). Port-less protocols (icmp, gre, …) are rejected here —
  a purpose is a port concept.
- A purpose must declare **at least one** port. Non-purpose attributes
  (zone/role/environment) must **not** declare ports.

These are the *standard* ports for the purpose. A service tagged with the
purpose but listening on a different port is still detected — see
[Rule sets → how purpose matching works](rulesets.md) (the match also covers
the real port of any service you tagged).

### Conflict semantics

When your pack declares a value that already exists (from another pack):

- **Identical definition** (same comment, and for purpose the same port
  set) → the value is **ignored** (idempotent); the import continues.
- **Different definition** → the import is **rejected** with a conflict
  error. You cannot silently redefine another pack's value; depend on it
  instead, or choose a different (namespaced) name.

---

## 8. The `rules` block

`rules` is a **map** keyed by a short rule id. The full, globally-unique rule
id is `<package.id>.<short-id>` (e.g. `example.baseline.payments-api-from-user-zone`).
Short ids must be unique within the file.

```yaml
rules:
  workstation-dns-to-internet:
    description: A workstation resolved DNS directly against the Internet.
    query: 'FROM flows | LAST 300 | WHERE src_addr == "role:std.workstation" and dst_addr == "internet4" and port_proto == "purpose:std.dns"'
    condition: presence
    seen_retention: 3600      # first_seen only
    severity: medium
    cadence: 1h
    cooldown: 1h
    remediation: Point workstations at an approved internal resolver.
    tags: [dns, egress, hygiene]
```

### Rule fields

| Field | Required | Type | Meaning |
|---|---|---|---|
| `query` | **yes** | NFQL | The detection query — see [Writing the query](#9-writing-the-rule-query). |
| `description` | recommended | string | What the rule detects, shown in the GUI. |
| `condition` | no (default `presence`) | enum | When the rule fires — see below. |
| `severity` | no (default `medium`) | enum | `info`, `low`, `medium`, `high`, `critical`. |
| `cadence` | **yes in practice** | duration | How often the rule is evaluated — must be a preset (below). |
| `cooldown` | no | duration | Minimum time between two notifications for the same rule. |
| `seen_retention` | no | integer (seconds) | `first_seen` only: how long a seen key is remembered. Omitted = never forget. |
| `remediation` | no | string | Free-text runbook shown with the alert. |
| `tags` | no | list of strings | Labels for filtering. The pack `id` is always added automatically. |

### `condition`

| Value | Fires when |
|---|---|
| `presence` (default) | the query returns **≥ 1 row**. The common case ("this happened"). |
| `first_seen` | a row whose key was **never seen before** appears. Good for "new X" detections. Uses `seen_retention` to bound memory. |
| `heartbeat` | the query returns **zero rows** while the rule has previously had data — i.e. something expected **stopped** (a dead feed, a silent sensor). |

> There is no `threshold` condition in the pack format. To alert on a count
> or volume threshold, put the aggregation **inside the NFQL query** with
> `STATS … | HAVING …` and use `condition: presence`. Example:
> `… | STATS targets = COUNT_DISTINCT(server_ip) BY client_ip | HAVING targets >= 20`.

### `severity`

One of `info`, `low`, `medium`, `high`, `critical`. Drives triage and
notification routing. Defaults to `medium` if omitted.

### `cadence` (evaluation interval)

How often the evaluator runs the rule. It **must be one of these presets**:

| Cadence | Equivalent |
|---|---|
| `10s` | 10 seconds |
| `30s` | 30 seconds |
| `1m` | 60 seconds |
| `5m` | 300 seconds |
| `15m` | 900 seconds |
| `1h` | 3600 seconds |

You may write the duration (`15m`, `1h`) or the raw seconds (`900`, `3600`).
A value outside the preset list is rejected.

> **Coverage tip:** set the query's time window (`LAST`) to at least the
> cadence, with a small overlap, so no activity falls between two runs. A
> rule scheduled every `15m` typically uses `LAST 1200` (20 min); a `1h`
> rule uses `LAST 3900` (65 min). Per-rule `cooldown` prevents repeated
> notifications from the overlap.

### `cooldown`

Any non-negative duration (`1h`, `30m`, `3600`). After a rule fires, it will
not notify again until the cooldown elapses (the evaluation still runs; the
notification is throttled).

### `tags`

Free labels. Conventions used by the bundled pack that you may reuse:

- `requires-flow-matrix` / `flow-matrix-unmatched` — the rule only fires on
  connections not declared in the Flow Matrix.
- `requires-enrichment` — needs a threat/cloud enrichment source enabled.
- `tuning-required` — has a threshold/scope to adapt per environment.
- `behavioral` / `includes-matched` — looks at all traffic, declared or not.
- `attack-tXXXX` — MITRE ATT&CK technique id.

---

## 9. Writing the rule query

The `query` is ordinary [NFQL](nfql.md), with two constraints specific to
alerting:

1. **No `?` parameters.** An alert query runs unattended — there is nobody
   to fill placeholders. It must be fully self-contained.
2. **It must compile** against the catalog and the (installed + this pack's)
   vocabulary. A reference to an unknown attribute value fails the import.

In practice, **always bound the time window** with `LAST <seconds>` (or
`BETWEEN`) so each scheduled run is cheap and coverage is predictable.

### Referencing the standard attributes

This is what makes a pack portable — use the vocabulary, not client names:

| Reference | Matches |
|---|---|
| `ip == "zone:std.dmz"` | any address in a network tagged zone `std.dmz` |
| `src_addr == "role:std.workstation"` | a host tagged role `std.workstation` |
| `dst_addr == "environment:std.production"` | a network tagged environment `std.production` |
| `port_proto == "purpose:std.dns"` | a flow whose port/protocol is the DNS purpose (either direction) |
| `server_port_proto == "purpose:std.rdp"` | a session whose **server** side is the RDP purpose |
| `dst_addr == "internet4"` / `"internal4"` | built-in routable / non-routable IPv4 sets |

`zone:`/`role:`/`environment:` resolve to an IP set; `purpose:` resolves to
a port+protocol set (compared via `port_proto`, `server_port_proto` or
`client_port_proto`). See [NFQL](nfql.md) for the full language and
[the community pack](community_ruleset.md) for the advanced
"Flow-Matrix-unmatched" detection pattern.

---

## 10. What happens on install

- The pack's **attribute values** are added to the global vocabulary (owned
  by the pack) and become selectable in the cartography dropdowns.
- Each **rule** is materialised into the alerting subsystem as one saved
  NFQL query + one alert rule, both **read-only** and tagged with the pack
  id. The existing evaluator runs them.
- Pack rules can be enabled, disabled or **duplicated** (a duplicate is a
  normal, editable copy you own), but not edited in place.

---

## 11. Lifecycle reference

| Action | Effect |
|---|---|
| **Install** | Adds vocabulary + rules. Dependencies must be present. |
| **Upgrade** (higher version) | Replaces content; preserves each rule's enabled/disabled state by id. |
| **Enable / disable pack** | Toggles all of the pack's rules at once. Vocabulary and cartography untouched. |
| **Delete** | Removes the pack's rules and vocabulary. Cartography entities tagged with the pack's values are **cleared** (you are shown which, first). **Blocked** if another installed pack depends on this one. |
| **Config export** | Records only *which* packs are installed and each rule's enabled state — **never** the pack contents. On restore, the state is re-applied to packs you have installed; a referenced-but-not-installed pack is reported so you can upload it. |

---

## 12. Validation checklist

Before shipping, make sure:

- [ ] `package.id`, `package.maintainer`, `package.version` are present;
      `version` is valid semver.
- [ ] every `requirements` entry parses (`id`, operator, version).
- [ ] every attribute value has a non-empty `name`.
- [ ] every `purpose` declares ≥ 1 `ports` entry as `PORT/PROTO` with a
      port-carrying protocol; no other attribute declares `ports`.
- [ ] every rule has a non-empty `query`; `condition` is
      `presence`/`first_seen`/`heartbeat`; `cadence` is a preset; `cooldown`
      parses as a duration.
- [ ] every rule query compiles, uses no `?` parameters, and references only
      attribute values defined in this pack or a dependency.
- [ ] rule short-ids are unique; the resulting full ids
      (`<id>.<short>`) do not collide with an existing query/rule name.

The Rule Sets page runs all of these as a **dry run** when you upload a
file, and shows exactly what would be added (and any conflict or missing
dependency) before you commit.

---

## 13. A complete example

A small pack that depends on the community vocabulary and adds one
purpose plus two rules.

```yaml
package:
  maintainer: acme security
  version: 1.0.0
  last_update: 2026-06-20
  id: acme.baseline
  requirements:
    - std.community>=0.1.0      # reuse the std.* zones / roles / purposes

attributes:
  purpose:
    - name: acme.billing-db
      comment: Internal billing database.
      ports:
        - 5432/tcp
        - 6432/tcp              # pgbouncer in front of it

rules:
  billing-db-from-user-zone:
    description: A user-zone host connected to the billing database directly, bypassing the app tier.
    query: |-
      FROM flows
      | LAST 1200
      | WHERE src_addr == "zone:std.user" and server_port_proto == "purpose:acme.billing-db"
    condition: presence
    severity: high
    cadence: 15m
    cooldown: 1h
    remediation: Restrict billing-DB access to the application servers; investigate the source host.
    tags: [segmentation, data, payments]

  billing-db-new-client:
    description: A host never seen before connected to the billing database.
    query: |-
      FROM sessions_consolidated
      | LAST 3900
      | WHERE server_port_proto == "purpose:acme.billing-db"
      | KEEP client_ip
    condition: first_seen
    seen_retention: 2592000     # remember clients for 30 days
    severity: medium
    cadence: 1h
    cooldown: 1h
    remediation: Confirm the new client is an approved application server.
    tags: [data, baseline]
```

This pack:

- **requires** `std.community` ≥ 0.1.0, so it can use `zone:std.user`
  without redefining it;
- adds one **purpose** (`acme.billing-db`) on two ports;
- ships a **segmentation** rule (`presence`) and a **new-client** rule
  (`first_seen` with a 30-day memory);
- on the next version bump, re-import to **upgrade**; both rules keep
  whatever enabled/disabled state the operator chose.

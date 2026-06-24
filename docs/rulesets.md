# Rule sets

A **rule set** (or *rule pack*) is a ready-made bundle of detection rules
you can install in one click. Because every obserae deployment names its
hosts and services differently, a rule written against *your* names can't be
shared with anyone else. Rule sets fix that by adding a small **standard
vocabulary** to your cartography — zones, environments, host roles and
service purposes — and shipping rules written against that vocabulary, so
they work anywhere.

obserae ships with the **community** rule set: a vendor-neutral starter pack
with ten common detections (cleartext protocols, exposed RDP, DNS hygiene,
database access from the user zone, …).

## How it works in three steps

1. **Install a rule set.** Go to **Rule Sets**, upload the pack file (or
   import the bundled `community.std`). obserae checks its dependencies and
   tells you exactly what it will add.
2. **Tag your cartography.** Open a network, host or service and pick the
   standard attribute from the dropdown — for example mark your user LAN as
   `zone: user`, your jump host as `role: security.bastion`. You can only
   pick from the values the installed packs provide.
3. **Enable the rules you want.** The rule set's rules appear on the
   **Alerting** page (read-only, marked as pack-owned). Toggle them on, or
   enable/disable the whole pack at once from the Rule Sets page.

That's it — the rules now fire against your traffic, using your tags.

## The standard attributes

| Attribute     | You put it on… | Example values                       |
|---------------|----------------|--------------------------------------|
| `zone`        | networks       | `user`, `dmz`, `server`, `management`|
| `environment` | networks       | `production`, `preproduction`        |
| `role`        | hosts          | `workstation`, `security.bastion`, `db.server` |
| `purpose`     | services       | `std.dns`, `std.https`, `std.rdp`    |

You assign attributes the same way you edit anything else in the
cartography — in the GUI editor, or in your cartography YAML:

```yaml
networks:
  - name: office-lan
    cidr: 10.10.0.0/16
    zone: user
    environment: production
hosts:
  - name: jump01
    role: security.bastion
    services:
      - name: ssh
        protocol: TCP
        port: 22
        purpose: std.ssh
```

> **Your cartography is never broken by a rule set.** If you import a
> cartography that uses a value a rule set hasn't defined, obserae simply
> ignores that one tag and warns you — it never refuses the import. If you
> later remove a rule set, the tags it provided are cleared from your
> entities (you're shown exactly which, first) and nothing else changes.

## Using attributes in NFQL

Once tagged, the standard attributes work in NFQL just like groups:

```nfql
FROM flows | LAST 300 | WHERE src_addr == "role:workstation" and dst_addr == "internet4"
```

```nfql
FROM flows | LAST 300 | WHERE zone:dmz and port_proto == "purpose:std.https"
```

- `zone:`, `environment:`, `role:` match an address against the set of IPs
  carrying that tag.
- `purpose:` matches a **port + protocol**. Compare it against `port_proto`
  (either side of a flow), or `server_port_proto` / `client_port_proto` on
  sessions. For example `server_port_proto == "purpose:std.dns"` matches
  traffic to a DNS service (port 53 over UDP or TCP).

A `purpose:` match is **robust to your real deployment**. It catches two
things at once:

- the purpose's **standard ports** anywhere (e.g. any postgres on 5432);
- the **actual port of any service you tagged** with that purpose, scoped to
  that service's own host. So if you tag a postgres service that runs on a
  non-standard `6666/tcp`, `purpose:std.postgres` detects it — and because
  the match follows your cartography live, **changing the service's port is
  reflected immediately**, with nothing to recompile. (Tip: when you pick a
  purpose in the service form, its standard port pre-fills automatically;
  override it if your service uses a different one.)

Attribute values can contain dots, e.g. `purpose:std.dns`.

## Managing rule sets

On the **Rule Sets** page you can:

- **Install** a pack from a file, with a dry-run that shows added
  attributes, rules and any dependency or conflict before you commit.
- **Upgrade** a pack by installing a newer version — your enable/disable
  choices are preserved.
- **Enable / disable** a whole pack at once.
- **Delete** a pack — obserae first shows you which cartography tags will be
  cleared, and refuses if another installed pack depends on it.

A rule set's rules are **read-only**: you can enable, disable or **duplicate**
them (to make your own editable copy), but you can't edit the originals — the
pack file is their source of truth.

## Dependencies and versions

A rule set can require another one (for shared attributes), with a version
constraint:

```yaml
package:
  id: community.std
  version: 1.0.0
  requirements:
    - community.base>0.1.0
```

obserae won't install a pack until its dependencies are present at a
compatible version, and won't let you delete a pack that another installed
pack still needs.

## Backup & restore

When you export your configuration, obserae records **which** rule sets are
installed and **which of their rules are enabled** — but not the pack
contents themselves. On restore, those enable/disable choices are
re-applied — and they now **persist**: a per-rule disable used to be lost
whenever you imported a configuration that also carried alerting rules, but
that no longer happens.

If a referenced pack isn't installed yet:

- the bundled **community** pack is **installed automatically** during the
  import, so restoring a configuration no longer means installing it by hand
  first;
- a pack you uploaded yourself is not in the config bundle, so you still get a
  reminder to upload its file.

Older configuration files (from before rule sets existed) still import without
any changes.

## Writing your own rule set

A rule set is a single YAML file. The **[Writing a rule set](writing-rule-sets.md)**
guide is the exhaustive reference — the file format, every field, the
requirement (dependency) notation, versioning, the vocabulary and the rule
syntax. See the [NFQL guide](nfql.md) for the query language. The minimal
shape:

```yaml
package:
  maintainer: your org
  version: 1.0.0
  id: yourorg.baseline
attributes:
  purpose:
    - name: std.https
      comment: HTTP over TLS
      ports: [443/tcp]
rules:
  https-from-guest-zone:
    description: Guest devices reaching internal HTTPS services.
    query: 'FROM flows | LAST 300 | WHERE src_addr == "zone:guest" and dst_addr == "zone:server" and port_proto == "purpose:std.https"'
    condition: presence
    severity: medium
    cadence: 1h
    cooldown: 1h
    tags: [segmentation]
```

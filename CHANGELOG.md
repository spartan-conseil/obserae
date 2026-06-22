# Changelog

A high-level history of obserae, newest first. obserae is in **alpha** (pre-1.0):
it moves fast and every feature is open during the alpha. Dates are release
dates; binaries and Docker images for each version are on the
[releases page](https://github.com/spartan-conseil/obserae/releases). This is a
bird's-eye view, not an exhaustive commit log.

## [0.22.0] — 2026-06-22

- **Cartography edit lock (one editor at a time)**: when several admins are
  logged in, the cartography no longer lets them silently overwrite each other.
  The page is **read-only by default**; click **Edit** to take the **edit lease**
  (an *Editing* badge) and **Done** to release it — changes save as you go.
  Everyone else is then **read-only** with a banner naming the current editor,
  disabled controls and a **Request edit** button. **Only one editing session
  can be open at a time**, including the same admin in two windows: the second
  window's Edit is refused until the first clicks Done — so you can't reproduce
  the double-edit problem by opening two tabs. The lease **expires after 90 s**
  if a tab crashes, and the rule is enforced on the server too (a carto change
  from a non-holder is refused). No database change.

- **Docker data-volume permissions**: the images now create
  `/var/lib/obserae/data` and `chown` the whole `/var/lib/obserae` tree to the
  non-root user (UID 65532) at build time, so the daemon can write its database,
  parquet store and cache out of the box — no manual `chown` on the host bind
  mount before the first start.

- **Alert outputs — eleven new destinations**: alerts can now be delivered far
  beyond webhook/Gotify. **Messaging**: Slack, Mattermost and Telegram (bot
  token + API). **SIEM**: Syslog (RFC5424 over UDP/TCP/TLS, as JSON, **CEF** for
  ArcSight or **LEEF** for QRadar), Splunk HEC, and Elasticsearch/OpenSearch
  (basic or API-key auth). **Incident**: PagerDuty (Events API v2) and Opsgenie
  (US/EU), both de-duplicating on the rule name. **Email**: SMTP with
  STARTTLS / implicit TLS and optional auth. Every type rides the existing
  reliable outbox (retry with backoff, delivery audit) and the SSRF egress
  guard — now extended to the raw syslog/SMTP connections too — with secrets
  redacted on read as before. New destinations are picked from the type
  dropdown on the **Outputs** page; **Send test** works for each.

- **Richer alert payloads**: deliveries now also carry the rule's **tags**, a
  threshold rule's **observed value**, and a group-by rule's **key** — included
  only when the rule produced them. They flow into the webhook JSON, Splunk
  events, Elasticsearch documents, syslog JSON, and PagerDuty/Opsgenie details,
  and map to native fields where it helps (Opsgenie **tags**; CEF/LEEF carry the
  observed value and tag list). Message templates expose `{{.RuleTags}}`,
  `{{.ObservedValue}}` and `{{.KeyJSON}}`.

  > ⚠️ **Database wipe required.** This release adds columns to the output
  > delivery outbox (DuckDB schema change). Delete the DuckDB database file and
  > let the daemon recreate it on next start. **Your YAML config (cartography,
  > rules, alerting, outputs, …) is unaffected and re-imports cleanly.**

## [0.21.0] — 2026-06-21

- **Rule sets (rule packs)**: install ready-made, vendor-neutral detection
  bundles. A rule set adds a **standard vocabulary** to the cartography —
  `zone`/`environment` on networks, `role` on hosts, `purpose` on services —
  and ships rules written against it, so the same pack works on any
  deployment regardless of your naming. These attributes are queryable in
  NFQL (`zone:dmz`, `role:workstation`, and `port_proto == "purpose:std.dns"`
  for the port/protocol-based `purpose`). A new **Rule Sets** page installs
  packs (with a dry-run preview), enables/disables a whole pack, and shows a
  full impact screen before deletion; packs can depend on one another with
  version constraints. Pack rules land on the Alerting page as read-only
  (enable/disable or **Duplicate** to customise). Ships with the
  **community** pack: ten common detections (cleartext protocols, exposed
  RDP, DNS hygiene, direct database access, …). Config export records which
  packs are installed and their enabled-state — never the pack contents.

  > ⚠️ **Database wipe required.** This release changes the DuckDB schema
  > (new rule-pack tables, plus `zone`/`environment`/`role`/`purpose`
  > columns on the cartography). Delete the DuckDB database file and let the
  > daemon recreate it on next start. **Your YAML config (cartography,
  > rules, alerting, …) is unaffected and re-imports cleanly** — export it
  > first if needed, then re-import after the wipe.

- **Cartography discovery funnel**: build the map straight from observed
  traffic in two stages. **Network Discovery** (new) proposes candidate
  **subnets** clustered from non-routable (private) flows — `/24` per LAN,
  widening to `/23`–`/16` on contiguous ranges — and **+ Declare**
  pre-fills the network form. **IP Discovery** (the renamed *Orphan IPs*
  drawer) then surfaces the individual IPs to add as hosts. Internal /
  external separation is preserved: Network Discovery is private-only;
  routable peers stay on `internet4`/`internet6` via IP Discovery.

- **Self-documented cartography**: every host, network and group can now
  carry its own free-form **Markdown documentation** — runbooks, ownership
  notes, escalation steps, whatever the entity needs. The drawer renders it
  as formatted, sanitized HTML with an **Expand** full-screen view and an
  **Edit** button to update it inline. The documentation lives with the
  entity in the cartography, so it travels through config export/import
  (a `documentation` field in the YAML) like the rest of your map.

## [0.20.0] — 2026-06-17

- **Append-only alerts**: alerts are now persisted as an append-only JSONL
  journal (same model as the audit log); the alerts view is folded
  event-sourced and has its own retention.
- **Tamper-evident audit log**: every journal line carries a `seq` + `prev`
  SHA-256 hash chain, and closed files are anchored by HMAC seals in a separate
  registry. The format is verifiable from Go, the CLI (`verify-auditlog`) and a
  standalone Python tool.
- **Performance**: a series of ingest- and tick-path optimisations (slow-tick
  and DB-growth fixes) for steadier throughput at high traffic.
- **Accordion sidebar**: pages are now grouped under collapsible themes —
  **Network**, **Analysis**, **Connectors** and **Settings** — with Cockpit
  and Audit log as direct links. The group for the page you're on opens
  automatically, and your expand/collapse choices are remembered.
- **Lifecycle split**: the old single Lifecycle page is now three pages under
  Settings — **Storage**, **Retention** and **Backup**.
- Removed the **Flow Simulator** and the empty **Settings** placeholder page.
- Public documentation overhaul: `docs-web/` reorganised (landing README +
  `docs/`), a comprehensive **Configuring Exporters** guide, and a
  **Licensing & transparency** page.
- Web-GUI hardening guidance (reverse-proxy TLS, secure-cookie behaviour).

## [0.19.0] — 2026-06-16

- **IPFIX ingestion** alongside NetFlow v5/v9.
- **NFQL statistics engine** (SPEC-ENGINE-01): time bucketing, aggregates and
  metric thresholds for detection.
- **RAM-first sessionizer**: open sessions live in memory, closed sessions go
  straight to parquet — bounded RAM, a far smaller DuckDB, steadier ingest.
- Security-audit remediation (egress / SSRF hardening, test-API gating) and a
  slow-tick fix.

## [0.18.0] — 2026-06-10

- **Users & access management (RBAC)**: accounts, groups, API tokens.
- **Audit log**: append-only, tamper-evident journal of sensitive actions, with
  its own retention.
- High-traffic crash fixes and lifecycle hardening.

## [0.17.0] — 2026-06-06

- Memory: fixed an ingest-path leak; default memory cap at 80%; memory
  observability.
- NFQL: `JOIN` on `ip == ip`, plus `DROP` and `RENAME` operators.
- Coherent on-disk layout (per-table parquet directories).

## [0.16.0] — 2026-06-05

- **CLI overhaul**: full configuration management from the terminal and
  operational parity with the GUI (help registry, per-phase commands, docs).

## [0.15.0] — 2026-06-04

- **Single consolidated import/export** of the whole configuration as one YAML.
- Higher session ceilings; modal/UX fixes.

## [0.14.0] — 2026-06-04

- **Outputs**: send alerts to **Gotify** and **webhooks** (custom CA / skip-TLS
  options).
- Host clone in cartography; lifecycle/storage improvements.

## [0.13.0] — 2026-06-03

- **Parquet partitioning v2**: Hive-style partitions with pruning; concurrency
  and backup fixes.

## [0.12.0] — 2026-06-02

- **Hive partitioning** of the parquet stores; consolidated sessions moved to
  parquet.
- Retention and cartography-performance improvements.

## [0.11.0] — 2026-06-02

- Cartography polish: snap-to-grid, no more unwanted auto-zoom; ICMP fixes.

## [0.10.0] — 2026-06-01

- Observability and performance improvements; DB-activity panel fix.

## [0.9.0] — 2026-06-01

- **Cartography rendered with Sigma.js (WebGL)**: smoother zoom/pan, better
  groups, icons and network shapes.

## [0.8.0] — 2026-05-31

- Retention rework; ~200 MDI icons and OS badges for nodes; version in the footer.

## [0.7.0] — 2026-05-31

- **Alerting**: turn saved NFQL queries into alert rules (cadence + cooldown).
- Import/export of rules and saved queries.

## [0.6.0] — 2026-05-30

- **Lifecycle & backups**: DuckDB-snapshot backups with a timeline; data split
  by source; orphan-parquet recovery at startup.
- **NFQL cookbook** in the GUI; JSON/CSV export; rule-match NFQL table.
- Matcher and rule-expansion performance.

## [0.5.0] — 2026-05-24

- **Tags** and **rule-overlap (relations) detection**.
- Sessions page improvements; rematching on imported rules.

## [0.4.0] — 2026-05-23

- More protocols in sessions: **IGMP, GRE, AH, ESP, OSPF, SCTP**.
- **DHCP-aware** nodes (`.static` / `.dhcp`).
- Major ingest/correlation performance work (removed an O(n²) path) and stability.

## [0.3.0] — 2026-05-22

- **IPv6 support** (NetFlow v9), including the flow matrix.
- Persistent NetFlow v9 templates; DuckDB pinned to a checkpoint-safe build.

## [0.2.0] — 2026-05-20

- **Multi-source session correlation**: per-exporter aggregation, a consolidated
  view, and coherence scoring on the flow clock.
- **In-memory incremental sessionizer** (open-session cap, crash recovery, gauges).
- IP enrichment reworked (threat-intel vs cloud, on by default).

## [0.1.1] — 2026-05-20

- Packaging fix (older glibc compatibility).

## [0.1.0] — 2026-05-19

Initial release — the whole foundation landed at once:

- **Ingestion pipeline**: NetFlow v5/v9 over UDP → in-RAM buffer → parquet →
  DuckDB.
- **Cartography**: name your hosts, networks and groups in one global namespace,
  with a graph editor (auto-layout, undo/redo, import/export).
- **NFQL**: a pipeline query language with cartography-name resolution,
  pivot / anti-pivot, joins and syntactic sugar.
- **Sessions**: a bidirectional sessionizer with NFQL on sessions, plus a **rule
  matcher** for connectivity policy.
- **Web GUI**: cockpit, cartography, investigation, flow matrix, sessions.
- **Flow simulation** for testing without live traffic.
- **IP enrichment** (AWS / Azure / Google ranges).
- **CLI** and Unix control socket; Docker images and release tarballs; EULA and
  user documentation.

---

Pre-1.0: a minor version can include breaking changes. The terms that ship with
your version are yours to keep — see [Licensing & transparency](LICENSING.md).

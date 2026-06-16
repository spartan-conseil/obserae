# Changelog

A high-level history of obserae, newest first. obserae is in **alpha** (pre-1.0):
it moves fast and every feature is open during the alpha. Dates are release
dates; binaries and Docker images for each version are on the
[releases page](https://github.com/spartan-conseil/obserae/releases). This is a
bird's-eye view, not an exhaustive commit log.

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

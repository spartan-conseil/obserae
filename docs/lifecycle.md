# Storage, Retention & Backup

Three pages under the **Settings** group in the sidebar let you steer
obserae's data footprint over time:

- **Storage** (`/storage`) — watch how much disk the database, the
  parquet stores and the backups take;
- **Retention** (`/retention`) — evict stale flows, sessions and
  audit-log entries after a configurable age;
- **Backup** (`/backup`) — take periodic full-database snapshots,
  with rotation by age and/or count, and restore to any point.

Open the **Settings** group in the sidebar to reach them (the group
opens automatically when you are on one of these pages).

> The retention and backup settings you change here are now
> **persisted** (in the `app_settings` table) and survive a daemon
> restart — they no longer revert to `obserae.yaml` on reboot.

> Looking for the old **Flow I/O** tab (manual flow JSON export /
> import)? It was removed. Operator configuration — cartography,
> flow matrix, alerting, outputs, enrichment, exporters, backup and
> retention — is now exported and imported as one YAML file from the
> [**Config I/O**](#) page (`⇄` in the sidebar, `/config-io`).

---

## Storage page

A live snapshot of where the bytes are. Polls every 10 seconds —
the values move slowly so there's no point hammering them.

### Database section

- **Path** — the DuckDB file the daemon is running against.
- **DuckDB file** — the size of that file on disk.
- **Disk free** — free space on the mount that holds the
  database, alongside the total capacity (free / total).

When **Disk free** is the same order of magnitude as the
DuckDB file, it's time to either widen the mount or tighten the
retention policy below.

### Backup directory section

- **Snapshots** — cumulative size and file count of every backup snapshot
  currently on disk. Cross-check with the **Files on disk** list on the Backup page.

### Parquet stores section

All retained data lives in Hive-partitioned parquet stores on disk
(`env=default/year=…/month=…/day=…/hour=…`, UTC — except the enrichment
ranges, keyed by `type=…/source=…`). This section gives a SOC operator the
state of each store **at a glance**. The header shows the **total parquet**
size; then one card per store:

- **Flows** — the raw flow history (queried in place; a background compactor
  merges each elapsed hour into one file).
- **IP enrichment** — the insert-time classification log.
- **Sessions archive** / **Consolidated archive** — the cold tiers of the
  session and consolidated-conversation tables.
- **Enrichment ranges** — the cloud/threat-intel CIDR catalogue (per source).
- **Audit log** — the append-only audit journal (JSONL, hour-partitioned);
  its size, file count, span and write timeline, same as the parquet stores.

Each time-partitioned card shows:

- **Size** and **file count**.
- **Updated _N_ ago** — a freshness badge from the newest hour written
  (green when recent, amber when stale — useful to spot a store that stopped
  receiving data).
- **Span** — oldest → newest partition, i.e. how far back the store reaches.
- **Timeline** — a small bar chart of bytes written over time, at an adaptive
  granularity: **hourly** (last 48 h) for a short history, **daily** (last 30
  days) for longer ones. A caption under the bars names the granularity/window
  and the two ticks show the first/last bucket. Gaps show as blanks, so you see
  the temporal spread of the hiving and any missing hours/days at a glance.

The Enrichment ranges card lists each source with its size instead of a
timeline (it is a reference catalogue, not time-series data).

---

## Retention page

**Off by default.** The daemon never auto-evicts data unless you
opt in. That's intentional: a fresh install accumulates so an
analyst can investigate yesterday's flows on day three. Once you
have a sense of the daily volume, come back here and turn it on.

The page has two parts: a **Status** section at the top (what's
happening) and a **Policy** section below (the age thresholds).

### Status

- **Clean up now** — run a cleanup immediately, without waiting for
  the next scheduled sweep. Useful right after lowering a max-age, or
  to reclaim space on demand.
- **Last cleanup** — when the last sweep ran ("just now", "2 hours
  ago"…) and what it removed (flows, sessions, duration).
- **Next automatic cleanup** — when the next scheduled sweep will run
  (only when retention is ON). When it's off, the line reminds you to
  turn it on to sweep on a schedule.

A manual "Clean up now" does **not** reschedule the periodic sweep —
the automatic cadence keeps its own clock.

### The master toggle

- **Retention OFF** — the runner ticks but does nothing.
  Flipping it on is the activation switch.
- **Retention ON** — every interval (1 hour by default) the runner evicts
  flows older than `flows_max_age` and sessions older than
  `sessions_max_age`. Flows and archived sessions live in parquet, so
  eviction simply **drops whole time-partitions** (near-instant, never
  competing with live ingestion). Purging a session also removes its
  correlation overlay row, so no orphan rows are left behind.

### The ages

| Field                  | What it means                                        |
|------------------------|------------------------------------------------------|
| **Flows max age**      | Drop rows from `flows` whose `time_received` is older than this. Default `720h` (30 days). |
| **Sessions max age**   | Drop rows from `sessions` whose `last_activity_at` is older than this. Default `2160h` (90 days). |
| **Audit log max age**  | Drop audit-journal entries older than this. Default `0` — **the audit log is kept forever** unless you set a limit. Raise this deliberately: the audit trail is your forensic record. |

All three are edited on the **Retention** page as a number + unit
(hours / days / weeks / months) and accept Go duration strings under
the hood (`168h`, not `7d`). Set a value to `0` to skip that store
entirely (e.g. `0` on the audit log = "keep the audit trail forever").
The status line reports what the last sweep removed — flows, sessions
and audit file(s).

Edits take effect on the **next** sweep. You don't have to
restart the daemon — but they also don't get persisted back to
the YAML. For changes that should survive a daemon restart,
edit `configs/obserae.yaml` directly.

### Sweep counters

The **Last cleanup** line in the Status section shows the counters
from the most recent sweep: how many rows were deleted from each
table, and how long the sweep took. A long sweep (> 1 second) briefly
stalls flow ingestion — the daemon log emits a `WARN` line when
that happens.

> **The first sweep on a long-running daemon can be large.** If
> you enable retention on a daemon that has been running for
> months with no eviction, the first sweep may delete millions
> of rows in one shot and noticeably block ingestion. To
> spread the load, drop the database file once and start fresh,
> or temporarily set the buffer's `max_age` higher so flows
> queue while the purge finishes.

---

## Backup page

Periodic **transactional snapshots of the whole obserae state** —
both the DuckDB database (rules, cartography, exporters, NetFlow
templates, hot sessions…) **and** the on-disk stores (flows,
session & consolidated archives, IP enrichment, enrichment ranges,
and the audit log) — all captured together so a restore reconstructs
exactly the state the daemon was in.

Each snapshot is a directory `obserae-backup-YYYYMMDDTHHMMSS/`
containing:

- `snapshot.duckdb` — a native binary copy of the database.
- `manifest.json` — metadata (format, kind, row counts, per-store
  file counts, watermarks).
- `stores/<key>/…` — a mirror of the on-disk parquet/JSONL stores.
  A **full** snapshot copies the whole tree; a **delta** only the
  partition directories changed since its parent.

On restore the database is swapped and the stores are reapplied:
the data stores are **replaced** (point-in-time consistent with the
database), while the audit log is **merged** so its append-only
history is never erased.

### The master toggle

- **Backup OFF** — no periodic snapshots.
- **Backup ON** — every interval (24 hours by default) the
  runner writes one snapshot under the configured directory.

### The fields

| Field          | What it means                                                  |
|----------------|----------------------------------------------------------------|
| **Directory**  | Where the snapshots land. The daemon creates it if missing.    |
| **Interval**   | Cadence between snapshots. **Read-only at runtime** — change it in the YAML and restart the daemon. |
| **Max age**    | Snapshots older than this are removed on the next tick. `0` disables age-based rotation. |
| **Max files**  | Keep at most this many snapshots (oldest go first). `0` disables count-based rotation. |

Both rotation knobs can apply together — a snapshot must satisfy
**every** active limit to be kept.

### Backup now

The **↓ Backup now** button writes one snapshot immediately,
independent of the interval **and independent of the toggle** —
clicking it always produces a snapshot even when Backup is OFF.
The snapshot list below refreshes within a few seconds; the
**Last snapshot** line reports table count, total size and
rotation count.

> **Ingestion pauses briefly during a snapshot.** Backup runs in
> a single DuckDB transaction so every table is captured at the
> same instant. While that transaction holds, the inserter
> waits — typically a few seconds on a small DB, tens of seconds
> on a multi-GB DB. The daemon resumes ingestion automatically
> as soon as the snapshot commits.

### Snapshots on disk

Lists every `obserae-backup-*/` directory under the backup
directory, newest first, with its cumulative size, table count
and modification time.

> **Hand-placed directories aren't touched.** The runner only
> rotates files whose name matches its own format — so a
> directory you copied in for safe keeping will not be pruned.

### Restoring from a snapshot

A point-in-time restore is now available from the CLI. Pick a
target instant in RFC3339, ask the daemon for the chain it would
apply, and only then trigger the restore for real:

```sh
# 1. List what's on disk.
obserae-cli backup list

# 2. Preview the chain (no work done).
obserae-cli backup plan --point-in-time 2026-05-28T13:00:00Z

# 3. Dry-run: every step except the final swap (live DB untouched).
obserae-cli backup restore --point-in-time 2026-05-28T13:00:00Z --dry-run --confirm

# 4. The real thing. The daemon will exit after the swap and your
#    supervisor (systemd, Docker, …) restarts it on the new DB.
obserae-cli backup restore --point-in-time 2026-05-28T13:00:00Z --confirm
```

> **The daemon exits after a successful restore.** The current
> implementation closes the live DuckDB pools, renames the rebuilt
> file over the live one, and asks the process to terminate. Your
> supervisor restarts it on the freshly restored database — this is
> by design, the safest way to swap a database that has open
> writer connections.

> **Same DuckDB version required.** The daemon refuses to apply a
> snapshot whose `manifest.duckdb_version` differs from the running
> engine. There's no force flag — silent cross-version restores
> have a history of subtle corruption. Upgrade DuckDB or pick a
> snapshot from the same version.

The same operations are also available from a future GUI panel
(Phase 4); for now use the CLI.

---

## Where things live

- **YAML** — every knob on this page has a corresponding section
  in `configs/obserae.yaml` (`retention`, `backup`). The YAML
  values are the source of truth at daemon boot; runtime PATCH
  edits from this page don't get written back.

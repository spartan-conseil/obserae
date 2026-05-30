# Lifecycle

The **Lifecycle** page is where you steer obserae's data
footprint over time:

- watch how much disk the database, the parquet buffer and the
  backups take;
- enable **retention** to evict stale flows and sessions after
  a configurable age;
- enable **periodic full-database backups** as `.json.gz`
  snapshots, with rotation by age and/or count;
- run **manual export and import** of the flow data.

Open it from the sidebar (`⧗ Lifecycle`) or directly at
`/lifecycle`. Four tabs.

---

## Storage tab

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

### Working directories section

- **Parquet buffer** — temporary parquet files written by the
  ingestion buffer between flushes. Should hover near zero
  (the inserter deletes each file after a successful INSERT). A
  growing buffer points at a stuck inserter — check the daemon
  log for failed inserts.
- **Backup directory** — cumulative size and file count of every
  backup snapshot currently on disk. Cross-check with the **Files
  on disk** list in the Backup tab.

---

## Retention tab

**Off by default.** The daemon never auto-evicts data unless you
opt in. That's intentional: a fresh install accumulates so an
analyst can investigate yesterday's flows on day three. Once you
have a sense of the daily volume, come back here and turn it on.

### The master toggle

- **Retention OFF** — the runner ticks but does nothing.
  Flipping it on is the activation switch.
- **Retention ON** — every interval (1 hour by default) the
  runner deletes flows older than `flows_max_age` and sessions
  older than `sessions_max_age`.

### The two ages

| Field                  | What it means                                        |
|------------------------|------------------------------------------------------|
| **Flows max age**      | Drop rows from `flows` whose `time_received` is older than this. Default `720h` (30 days). |
| **Sessions max age**   | Drop rows from `sessions` whose `last_activity_at` is older than this. Default `2160h` (90 days). |

Both accept Go duration strings: `48h`, `7d` is **not** supported,
write `168h` instead. Set a value to `0` to skip that table
entirely (e.g. `0` on sessions = "keep sessions forever, only
purge flows").

Edits take effect on the **next** sweep. You don't have to
restart the daemon — but they also don't get persisted back to
the YAML. For changes that should survive a daemon restart,
edit `configs/obserae.yaml` directly.

### Last sweep

Below the form, the GUI surfaces the counters from the most
recent sweep: how many rows were deleted from each table, and
how long the sweep took. A long sweep (> 1 second) briefly
stalls flow ingestion — the daemon log emits a `WARN` line when
that happens, mirrored here.

> **The first sweep on a long-running daemon can be large.** If
> you enable retention on a daemon that has been running for
> months with no eviction, the first sweep may delete millions
> of rows in one shot and noticeably block ingestion. To
> spread the load, drop the database file once and start fresh,
> or temporarily set the buffer's `max_age` higher so flows
> queue while the purge finishes.

---

## Backup tab

Periodic **transactional snapshots of the whole obserae database**
— flows, sessions, rules, cartography, enrichment, exporters and
NetFlow templates — all dumped together so a restore reconstructs
exactly the state the daemon was in.

Each snapshot is a directory `obserae-backup-YYYYMMDDTHHMMSS/`
containing one `<table>.json.gz` per table plus a `manifest.json`
listing what's inside.

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
(Phase 4); for now use the CLI. The internal documentation has the
chain algorithm and design decisions (see
[docs/lifecycle.md](../docs/lifecycle.md#restore-phase-3)).

---

## Flow I/O tab

Manual, on-demand export and import. Same backend as the periodic
backup above; this tab is what you reach for during a one-off
session.

### Export

Click **↓ Download flows.json**. The browser streams a complete
JSON array of every flow currently in the database. Timestamps
are emitted in absolute RFC3339 form
(`2026-05-13T12:00:00Z`). Large datasets stream incrementally —
the file shows up as growing in your downloads folder rather
than waiting for the whole table to render.

### Import

Drop a file (or click to browse). Both **`.json`** and
**`.json.gz`** are accepted; the daemon detects gzip
automatically (by extension, by `Content-Encoding`, or by the
file's magic bytes).

The **Time mode** radio decides how timestamps are interpreted:

- **Absolute** — keep timestamps as written in the file. Use
  this when you want to preserve the original wall-clock of a
  forensic capture.
- **Relative** — shift every timestamp so the newest
  `time_received` in the file lands at **now**. Use this to
  replay a fixture captured days ago as if it were happening
  right now — the sessionizer and matcher then pick it up via
  their normal time-window selectors.

Click **↑ Import**. The status banner below tells you how many
flows were queued for the pipeline.

> **Imports are asynchronous.** The records traverse the same
> path as live NetFlow (enrichment → sessions → matching →
> storage), so they appear on the other pages a few seconds
> later, after the next buffer flush. Don't worry if the
> Cockpit doesn't immediately reflect the import.

> **Upload cap: 64 MiB after decompression.** The cap is
> measured on the decompressed stream so a small gzip that
> would balloon to gigabytes is rejected with a clear "payload
> too large" message. For larger backups, drop the file into
> the configured backup directory directly and use the daemon's
> CLI to import it server-side.

---

## Where things live

- **Daemon-internal reference** — [docs/lifecycle.md](../docs/lifecycle.md)
  covers the schema, the runner internals (set-based SQL,
  ticker cadence, atomic-pointer config swap) and the REST API
  contract.
- **YAML** — every knob on this page has a corresponding section
  in `configs/obserae.yaml` (`retention`, `backup`). The YAML
  values are the source of truth at daemon boot; runtime PATCH
  edits from this page don't get written back.
- **Architecture** — [docs/architecture.md](../docs/architecture.md)
  explains where the lifecycle runners sit relative to the
  ingestion pipeline (writer-pool contention, set-based SQL,
  parquet round-trip).

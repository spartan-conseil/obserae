# Monitoring

The **Monitoring** page (`/monitoring`, under the **Settings** group in the
sidebar) is obserae's operational dashboard — built for a sysadmin or a SOC
engineer who needs to understand how the daemon is doing and spot a problem
early. It updates live from the same `/ws/health` stream as the cockpit, about
every two seconds.

Unlike the Cockpit (which is about *using* the product — flow matrix coverage,
sessions, alerts), Monitoring is about *running* it. It requires the
**`system:manage`** permission.

## What it shows

### Ingestion (parquet)

obserae's pipeline runs in RAM and *generates* parquet: incoming flows are
folded into a batch and flushed to parquet files that the `flows` view reads
back. This section is the "are flows landing, and how fast do they import"
signal:

- **Files written** / **Records ingested** — cumulative parquet files produced
  and flow rows they carry since the daemon started.
- **Flushes** — how many flush cycles have run.
- **Flush last / avg / max** — the flush wall-time, most-recent, a smoothed
  average, and the recent peak. A rising flush time points at the disk, not the
  CPU.
- The line below the cards spells out the **last flush** (files × records, and
  when it happened) — a quick freshness check.

### Memory

- **Heap in-use** — live Go heap. A steadily rising value over hours is the
  first sign of a real leak.
- **Heap alloc** / **Sys (RSS ceiling)** — allocated heap, and the total the
  runtime holds from the OS (≈ RSS). A flat heap under a rising Sys is
  fragmentation, not a leak.
- **Goroutines** / **GC cycles** — runtime counters.
- **Sessions in RAM** — open sessions held in memory against their cap (sessions
  are RAM-only until they close); the card turns amber/red under pressure.

> Memory is sampled on a throttled cadence (not every tick) because reading it
> briefly pauses the runtime — so these figures refresh a little slower than the
> rest of the page.

### Pipeline

Every stage of the `UDP → … → store` pipeline is a buffered channel. A channel
that stays full back-pressures the stage before it. The table shows each
channel's fill (green / amber / red), and **UDP drops** counts packets the
collector had to shed — a direct ingest-loss signal.

### Database

The writer connection is single (`MaxOpenConns=1`), so when ingestion stalls
the question is always "which operation holds the writer, and is a queue piling
up behind it":

- **Writer pool** — in-use connection, the wait Δ over the last interval, and
  the cumulative wait total (a monotonic counter — normal, not an alarm), plus
  the matcher backlog lag.
- A **Writer contention** banner lights up only during real contention this
  interval; a **Matcher falling behind** banner warns when closed sessions pile
  up faster than the matcher drains them.
- **In-flight operations** — what is running right now, longest first (the first
  writer row holds the connection).
- **Recent operations** — the last operations that *completed*, with their
  duration and whether they errored. This is the permanent, `obserae-cli ps`-style
  view: even when nothing is running, you can see what just happened.

## The top-bar warning

The DB-activity panel used to live on the Cockpit; it now lives here so the
Cockpit stays focused on product use. When there is a real database or ingestion
problem (writer contention or matcher backlog), a ⚠ icon appears in the top bar
from **any** page and links straight to this Monitoring screen.

## From the terminal

The same DB activity is available without the GUI:

```sh
obserae-cli ps             # one-shot: in-flight + recent ops
obserae-cli ps --watch 1s  # refresh like top
```

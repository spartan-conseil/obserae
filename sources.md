# Sources

The **Sources** page is your central place for everything that
*produces data* for obserae:

- the **NetFlow exporters** — the switches, firewalls, routers
  and probes that emit flow records toward the daemon;
- the **cloud-provider attribution sources** (AWS, Azure, Google);
- the **threat-intelligence feeds** (FireHOL …).

Open it from the sidebar (`⇅ Sources`) or directly at
`/sources`. Three tabs.

---

## Exporters tab

This is where you give every flow-emitting device a friendly
name and an equipment type. Once labelled, every other page
(Sessions, Cartography, Investigation) shows that label instead
of the raw `sampler_address` IP — much easier to scan in an
incident review.

### How the list is populated

The daemon discovers exporters **automatically** by aggregating
the `sampler_address` column of every flow it has stored. A
background sweep runs every 5 minutes by default; new devices
appear in the table the next time that sweep runs.

If you just plugged in a new device and don't want to wait,
click the **↻ Rescan** button at the top of the table. It
triggers a fresh aggregation and the new IP appears within
seconds (assuming at least one flow has reached the daemon).

### The table

| Column           | What it is                                          |
|------------------|-----------------------------------------------------|
| **IP**           | The `sampler_address` carried on every NetFlow packet from this device. Identifier — read-only. |
| **Name**         | Friendly name (e.g. `core-switch-01`). Editable.    |
| **Equipment type** | Model / vendor (e.g. `Cisco Catalyst 9300`). Editable. |
| **Details**      | Free-form notes (e.g. `rack A, primary uplink`). Editable. |
| **Flows**        | Cumulative count of flow records the daemon received from this exporter. Auto-maintained — you never edit it. |
| **Last seen**    | Most recent `time_received` for a flow from this exporter. Auto-maintained. |

### Editing a row

1. Click into any editable cell (Name / Equipment type / Details).
2. Type. A **Save** button appears at the end of the row as soon
   as the value changes.
3. Click **Save**. A green `✓ saved` badge confirms it lasted.

Edits are persisted immediately; they do not require a daemon
restart and they **survive every subsequent rescan** — the
background sweep never overwrites operator-edited columns, it
only refreshes the auto-maintained counters.

> **Trying to label a device that has never sent a flow?** The
> API refuses (404). Labels are anchored to observed traffic; if
> the device has never reached the daemon, there's nothing to
> label yet. Plug it in, wait for one flow, then rescan.

---

## Cloud attribution tab

This tab annotates every IP the daemon sees with its cloud
provider when applicable (AWS / Azure / Google Cloud). On
Sessions and Cartography, a small grey hint then appears under
the host: e.g. `52.93.x.x` shows up as `AWS · us-east-1 · S3`
instead of an opaque public IP.

### The master toggle

The **IP enrichment** slider at the top is the kill-switch. When
off, the daemon stops fetching new CIDR ranges from any source
and stops resolving IPs at ingest time. Existing annotations stay
in place until you turn it back on or restart the daemon.

### The source list

Each row is one provider. Per-source controls:

- **Per-source toggle** — disable just AWS without affecting
  Azure / GCP, for example.
- **↻ Refresh** — forces an immediate fetch of the CIDR list.
  Useful right after you enable a brand-new source, before its
  next hourly refresh. The spinner reflects the worker's real
  state — you can see when the fetch is in flight, when it
  succeeds (`last fetched 10 s ago`, `range_count: 4 213`), or
  when it errors (last error message displayed in red).

> The fetch goes out to the provider's public CIDR endpoint
> (`ip-ranges.amazonaws.com`, the Azure ServiceTags page, the
> Google Cloud ranges JSON). No credentials, no per-IP queries.

---

## Threat intelligence tab

Same shape as the cloud tab but for open-source threat-intel
feeds. Hits surface as a red triangle on Sessions and
Cartography for any IP listed by an enabled feed.

The default seed is **FireHOL Level 1** (a curated list of known
malicious networks). Other feeds can be added by extending the
daemon's enrichment-sources package — operator interface for
adding new feeds is on the roadmap.

---

## Where things live

- **Schema** — the `exporters` table is described in
  [docs/lifecycle.md](../docs/lifecycle.md) (the daemon-internal
  reference).
- **REST endpoints** — `/api/exporters` (list / patch / rescan)
  and `/api/enrichment/*` (toggles, refresh). See
  [docs/lifecycle.md](../docs/lifecycle.md) for the exact contract.
- **Architecture** — [docs/architecture.md](../docs/architecture.md)
  explains how the three runners (rescanner, enrichment worker,
  matcher) sit alongside each other.

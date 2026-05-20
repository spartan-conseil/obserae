# IP enrichment

Enrichment tags the IPs obserae sees with contextual metadata:
cloud-provider attribution (AWS / Azure / GCP), and — over time —
open-source threat-intel feeds. Once enabled, every IP that
appears in the GUI gets a small badge revealing who owns the range
and where it lives.

For example, a session to `52.x.x.x` shows up as
**AWS / us-east-1 / EC2** instead of an opaque IPv4 address.

---

## What it does

| Source  | What it tags                                                                                        |
|---------|------------------------------------------------------------------------------------------------------|
| AWS     | Service (S3, EC2, AMAZON, CLOUDFRONT…) + region (us-east-1, eu-west-3…). ~15 000 prefixes.           |
| Azure   | Microsoft systemService + region (regional umbrella tags like `AzureCloud.francecentral` included). ~100 000 prefixes. |
| Google  | "Google Cloud" + scope (region name, or `global`). ~1 000 prefixes.                                  |

All three sources fetch directly from the cloud provider's
published list — no third-party feeds, no commercial subscriptions.

---

## Enabling enrichment

### From the GUI (recommended)

Open the **Data** page and head to the *IP Enrichment* tab. You'll
see each source with an enable toggle, the last refresh time, and
the current range count.

To turn a source on:

1. Click the toggle next to the source name.
2. Click **Refresh now** — the first fetch pulls the full list
   (a few seconds for AWS/Google, ~15 s for Azure).
3. Once `range_count` is non-zero, every IP in the GUI is enriched
   on the fly.

### From the CLI

The CLI exposes the same operations over the control socket:

```sh
# Master switch
curl --unix-socket ./data/obserae.sock -X PATCH \
  http://localhost/api/enrichment \
  -d '{"enabled": true}'

# Enable AWS
curl --unix-socket ./data/obserae.sock -X PATCH \
  http://localhost/api/enrichment/sources/aws \
  -d '{"enabled": true}'

# Force an immediate refresh
curl --unix-socket ./data/obserae.sock -X POST \
  http://localhost/api/enrichment/sources/aws/refresh
```

---

## How the refresh cycle works

A single background goroutine handles every source:

- **Hourly tick** — every source with `enabled = true` is refreshed.
- **On-demand refresh** — clicking *Refresh now* in the GUI sends
  one shot, regardless of the enable flag (you can test a source
  before turning it on).

To minimize bandwidth and load on the upstream, each refresh uses
HTTP conditional GETs (`If-None-Match` / `If-Modified-Since`):

- If the upstream hasn't changed → `304 Not Modified`, no body
  transferred, the existing snapshot stays. Log line:
  `enrichment: source unchanged`.
- If it has changed → the new payload is parsed and atomically
  swapped in via a single DuckDB transaction.
- If the upstream errors → the previous snapshot is preserved and
  the error is shown in the GUI.

Practical numbers for AWS:

| Path             | Body size | Wall time |
|------------------|-----------|-----------|
| First fetch      | ~2 MB     | ~1 s      |
| Unchanged (304)  | 0 bytes   | ~250 ms   |

The mechanism is transparent: the *Refresh* button always reaches
the upstream; the answer about "did anything change" comes back as
the provider's HTTP status.

---

## NFQL surface

The enriched ranges live in DuckDB as `enrichment_ip_ranges`,
exposed to NFQL under the shorter alias **`enrichment_ip`**:

```nfql
FROM enrichment_ip
  | WHERE source == "aws"
  | KEEP cidr, details
```

Available columns:

| Column       | Type      | Meaning                                                            |
|--------------|-----------|---------------------------------------------------------------------|
| `id`         | UUID      | Row identifier.                                                     |
| `source`     | VARCHAR   | `aws`, `azure`, `google`.                                           |
| `cidr`       | INET      | The IP range.                                                       |
| `nature`     | VARCHAR   | `cloud` (more values to come as threat-intel sources are added).    |
| `details`    | VARCHAR   | Provider-specific string (e.g. `S3 / us-east-1`).                   |
| `fetched_at` | TIMESTAMP | When this row was loaded. Use with `LAST` / `BETWEEN`.              |

### Typical use: pivot against sessions

The natural query is "which of my sessions had a server endpoint in
a given cloud range?":

```nfql
# Sessions whose server is in any AWS prefix
FROM enrichment_ip | WHERE source == "aws" | KEEP cidr
> FROM sessions    | PIVOT server_ip WITHIN cidr
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, server_port, ab_bytes

# Same idea but extract per-region detail with a JOIN
FROM enrichment_ip | WHERE source == "aws" | KEEP cidr, details
> FROM sessions    | JOIN server_ip WITHIN cidr
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, prev_details, ab_bytes
```

The first form keeps the result narrow; the second pulls the cloud
metadata into each result row via the `prev_` prefix.

---

## How it appears in the GUI

When enrichment is on, IPs across every page render with a small
badge:

```
session opened 10:42:18
  ↳ 10.0.0.10 (host:webserver:eth0) ↔ 52.10.x.x  [AWS · us-west-2 · EC2]
```

Hover the badge for a tooltip with the provider, region, and
service. The cartography page also lists nearby cloud ranges in
the side drawer when you select a host whose traffic frequently
hits a particular provider.

---

## Frequency and data freshness

- The hourly tick keeps every enabled source within an hour of
  the upstream's latest publication.
- Conditional GETs mean a no-op refresh costs ~250 ms and 0 bytes
  of body, so the hourly cadence is cheap.
- Manual *Refresh now* lets you pull a freshly-published list
  immediately if you know one just dropped.

The published lists themselves update at different cadences:

- **AWS** — frequently, multiple times per week.
- **Azure** — weekly, on a rotating filename.
- **Google** — irregular, typically weekly.

obserae tracks these and adapts automatically — no operator action
needed beyond initial enablement.

---

## Privacy

The enrichment subsystem fetches **public** lists from the cloud
providers' own publication endpoints. It never sends your traffic,
your IPs, or any local data to a third party.

If you don't want any outbound traffic from the daemon, leave the
master switch off (`PATCH /api/enrichment` with `{"enabled":false}`,
or toggle it off in the GUI). The product works fine without
enrichment — IPs simply render as bare addresses.

---

## Where to next

- [web-gui.md](web-gui.md#data) — the *Data* page that hosts the
  enrichment controls.
- [nfql.md](nfql.md#cross-pipeline-lookups) — the `WITHIN` operator
  and PIVOT/JOIN cascade.

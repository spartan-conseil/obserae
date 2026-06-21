# IP enrichment

Enrichment tags the IPs obserae sees with contextual metadata:
cloud-provider attribution (AWS / Azure / GCP / Oracle / Cloudflare),
open-source threat-intel feeds (FireHOL, Tor), country-level geolocation
(GeoIP), and autonomous-system attribution (ASN).
Once enabled, every IP that appears in the GUI gets a small badge
revealing who owns the range — and your NFQL queries can filter or
join on it.

For example, a session to `52.x.x.x` shows up as
**AWS / us-east-1 / EC2** instead of an opaque IPv4 address, and a
session to a known-bad address is flagged **threat / firehol_level1**.

---

## What it does

| Source           | Nature   | What it tags                                                                                        |
|------------------|----------|------------------------------------------------------------------------------------------------------|
| AWS              | cloud    | Service (S3, EC2, AMAZON, CLOUDFRONT…) + region (us-east-1, eu-west-3…). ~15 000 prefixes.           |
| Azure            | cloud    | Microsoft systemService + region (umbrella tags like `AzureCloud.francecentral` included). ~100 000 prefixes. |
| Google           | cloud    | GCP **compute** ranges only (`cloud.json`): "Google Cloud" + scope (region name, or `global`). ~1 000 prefixes. |
| Google services (incl. DNS) | cloud | Google's **whole** published space (`goog.json`): the superset that also covers Google Public DNS (`8.8.8.0/24`), Search, Workspace. Use this if you want non-GCP Google IPs tagged. |
| Oracle Cloud (OCI) | cloud | OCI public ranges, tagged with their region (e.g. `OCI / eu-frankfurt-1`). |
| Cloudflare       | cloud    | Cloudflare's edge IP ranges (v4 + v6). Tags any IP fronted by Cloudflare. |
| FireHOL Level 1  | threat   | Address space that should never appear in legitimate traffic (attackers, bogons, hijacked ranges).   |
| Tor exit nodes   | threat   | IPs of Tor exit relays (the bulk exit list) — traffic leaving the Tor network.                       |
| Tor relays       | threat   | IPs of all running Tor relays/bridges (onionoo), tagged with the node nickname.                      |
| ASN (ip2asn)     | asn      | The owning autonomous system (AS number + organisation) of any public IP, e.g. `AS13335 CLOUDFLARENET`. Catches IPs no curated list covers (the `1.1.1.1` resolver, etc.). Refreshed weekly. |
| GeoIP (RIR country) | geoip | The ISO country code of any public IP, from the regional internet registry data. Drives the country flag on Cartography hosts. Refreshed weekly. |

> **Google Cloud vs Google services.** `Google Cloud` lists only GCP
> compute/region prefixes — it does **not** include Google Public DNS
> (`8.8.8.8`), which is general Google space, not GCP. Enable
> **Google services** to have addresses like `8.8.8.8` recognised as
> cloud. The two overlap on GCP ranges; enabling both is fine (a range
> matched by both shows one tag per source).

Every source fetches directly from the provider's (or project's)
published list — no commercial subscriptions, no third-party brokers.
A cloud IP belongs to at most one provider, but a threat IP can be
listed by several feeds, so obserae records **one tag per matching
source**.

---

## Two ways enrichment is used

The same fetched ranges feed two lookup paths, and you don't have to
choose between them:

- **In the GUI** — every IP rendered on a page gets its tag resolved
  on the fly, so tooltips and badges always reflect the latest ranges.
- **In your queries** — as flows arrive, obserae resolves each IP
  once and records the match in a table you can **equi-join** in NFQL.
  That makes "show me every session talking to a threat IP" a cheap,
  fast query rather than a scan over thousands of CIDRs.

**Private and local addresses are never tagged.** Threat blocklists
like FireHOL deliberately list private/bogon ranges (e.g.
`192.168.0.0/16`), so obserae first checks whether an observed IP is
actually routable on the public internet — RFC1918, loopback,
link-local, CGNAT and their IPv6 equivalents are skipped. Your
`192.168.x` / `10.x` hosts will never be flagged as cloud or threat.

---

## On by default

Enrichment is **opt-out**: on a fresh install every source is already
enabled and the daemon fetches each one at startup, so IPs are enriched
without any setup. The sources live under the **Connectors** group in
the sidebar, split across four enrichment pages — each showing its
sources with their last refresh time and range count:

- **Cloud Attribution** (`/cloud-attribution`) — AWS, Azure, Google,
  Oracle Cloud, Cloudflare.
- **Threat Intelligence** (`/threat-intel`) — FireHOL Level 1, Tor exit
  nodes, Tor relays.
- **GeoIP** (`/geoip`) — country-level geolocation from RIR data.
- **ASN** (`/asn`) — autonomous-system attribution from ip2asn.

A single global **IP enrichment** master switch governs all four pages
and stays in sync between them: it is a **kill-switch** — turn it off to
stop all outbound enrichment traffic at once (no fetches at startup or on
the refresh tick). You can also disable a single source with its own
toggle, or click **Refresh now** to pull a freshly published list
immediately. See [sources.md](sources.md) for the per-page walkthrough,
including what each source is good for and its limitations.

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
exposed to NFQL under the shorter alias **`enrichment_ranges`**:

```nfql
FROM enrichment_ranges
  | WHERE source == "aws"
  | KEEP cidr, details
```

Available columns:

| Column       | Type      | Meaning                                                            |
|--------------|-----------|---------------------------------------------------------------------|
| `id`         | UUID      | Row identifier.                                                     |
| `source`     | VARCHAR   | The feed: `aws`, `azure`, `google`, `google_services`, `oracle`, `cloudflare`, `firehol_level1`, `tor_exit`, `tor_relays`, `geoip`, `asn`. |
| `cidr`       | INET      | The IP range.                                                       |
| `nature`     | VARCHAR   | `cloud`, `threat`, `geoip` or `asn`.                                |
| `details`    | VARCHAR   | Source-specific string (e.g. `S3 / us-east-1`, `FR`, `AS13335 CLOUDFLARENET`). |
| `fetched_at` | TIMESTAMP | When this row was loaded. Use with `LAST` / `BETWEEN`.              |

### Typical use: pivot against sessions

The natural query is "which of my sessions had a server endpoint in
a given cloud range?":

```nfql
# Sessions whose server is in any AWS prefix
FROM enrichment_ranges | WHERE source == "aws" | KEEP cidr
> FROM sessions    | PIVOT server_ip WITHIN cidr
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, server_port, ab_bytes

# Same idea but extract per-region detail with a JOIN
FROM enrichment_ranges | WHERE source == "aws" | KEEP cidr, details
> FROM sessions    | JOIN server_ip WITHIN cidr
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, prev_details, ab_bytes
```

The first form keeps the result narrow; the second pulls the cloud
metadata into each result row via the `prev_` prefix.

### Faster: the `enrichment_ips` table

`enrichment_ranges` is a CIDR catalogue, so the queries above scan ranges
with `WITHIN`. For traffic that has already been ingested, a second
table — **`enrichment_ips`** — holds the *exact* IPs obserae already
resolved at ingest, one row per `(ip, source)`. Because the value is
the resolved IP itself, you **equi-join** on it (`==`), which is much
faster on large result sets.

| Column        | Type      | Meaning                                                |
|---------------|-----------|--------------------------------------------------------|
| `ip`          | INET      | The resolved IP. Equi-join against `server_ip` / `ip`. |
| `source`      | VARCHAR   | `aws`, `firehol_level1`, `geoip`, `asn`, … (several rows per IP — e.g. an IP can be cloud *and* carry a country *and* an AS). |
| `nature`      | VARCHAR   | `cloud`, `threat`, `geoip` or `asn`.                   |
| `cidr`        | INET      | Longest matching range the IP fell in.                 |
| `detail`      | VARCHAR   | Per-source hint (country code for `geoip`, `AS… org` for `asn`; empty for FireHOL). |
| `resolved_at` | TIMESTAMP | When the IP was classified.                            |

```nfql
# Sessions whose server is on a known threat feed
FROM enrichment_ips | WHERE nature == "threat" | KEEP ip
> FROM sessions    | PIVOT ip == server_ip
                   | LAST 3600
                   | KEEP ip_a, ip_b, server_ip, ab_bytes

# Sessions annotated with their cloud provider
FROM enrichment_ips | WHERE nature == "cloud" | KEEP ip, source
> FROM sessions    | KEEP server_ip, ab_bytes | JOIN ip == server_ip
```

The left column (`ip`) comes from the first pipeline; the right
(`server_ip`) from the second.

---

## How it appears in the GUI

When enrichment is on, IPs across every page render with a small
badge:

```
session opened 10:42:18
  ↳ 10.0.0.10 (host:webserver:eth0) ↔ 52.10.x.x  [AWS · us-west-2 · EC2]
  ↳ 10.0.0.11 (host:db:eth0)        ↔ 185.x.x.x   [threat · firehol_level1]
```

Hover the badge for a tooltip with the provider, region, and
service. The cartography page also lists nearby cloud ranges in
the side drawer when you select a host whose traffic frequently
hits a particular provider.

---

## Frequency and data freshness

- An **hourly tick** keeps most enabled sources within an hour of the
  upstream's latest publication.
- **GeoIP and ASN refresh weekly, not hourly.** Their underlying data
  (RIR allocations, ip2asn) changes slowly and the files are large, so a
  weekly cadence is plenty — and it keeps the cost of these two large
  sources low. *Refresh now* still forces an immediate fetch on demand.
- Conditional GETs mean a no-op refresh costs ~250 ms and 0 bytes
  of body, so the hourly cadence is cheap.
- Manual *Refresh now* lets you pull a freshly-published list
  immediately if you know one just dropped.

The published lists themselves update at different cadences:

- **AWS** — frequently, multiple times per week.
- **Azure** — weekly, on a rotating filename.
- **Google** — irregular, typically weekly.
- **FireHOL Level 1** — continuously, several times a day.
- **GeoIP (RIR) and ASN (ip2asn)** — slowly; obserae refetches them
  weekly to match.

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

- [sources.md](sources.md) — the **Connectors** pages that host the
  enrichment controls, with what each source is good for and its
  limitations (GeoIP accuracy, what an ASN is, why flag Tor traffic).
- [nfql.md](nfql.md#cross-pipeline-lookups) — the `WITHIN` operator
  and PIVOT/JOIN cascade.

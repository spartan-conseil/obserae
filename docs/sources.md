# Connectors

The **Connectors** menu group gathers everything that *produces
data* for obserae. Six pages cover the data sources:

- **Exporters** (`/exporters`) — the switches, firewalls, routers
  and probes that emit flow records toward the daemon;
- **Devices** (`/devices`) — your OPNsense firewalls, polled for their
  ARP table, DHCP leases and interface overview (admin-only);
- **Cloud Attribution** (`/cloud-attribution`) — the cloud-provider
  attribution sources (AWS, Azure, Google, Oracle, Cloudflare);
- **Threat Intelligence** (`/threat-intel`) — the open-source
  threat-intel feeds (FireHOL …);
- **GeoIP** (`/geoip`) — country-level geolocation built from the
  regional internet registry (RIR) data;
- **ASN** (`/asn`) — autonomous-system attribution (which AS owns an IP)
  built from the ip2asn dataset.

Open them from the sidebar under **Connectors**
(🖧 Exporters · 🧱 Devices · ☁ Cloud Attribution · 🛡 Threat Intelligence · 🌐 GeoIP · ⑂ ASN).

---

## Exporters page

This is where you give every flow-emitting device a friendly
name and an equipment type. Once labelled, every other page
(Sessions, Cartography, Investigation) shows that label instead
of the raw `sampler_address` IP — much easier to scan in an
incident review.

> This page labels devices that obserae has **already seen**. To
> configure a device to *emit* flows toward obserae in the first
> place, see [Configuring Exporters](exporters.md).

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

### Deleting a row

Each row has a **🗑 Delete** button. Use it to drop an exporter
that no longer belongs in the list — typically a device you have
**decommissioned or moved** after a network reconfiguration. The
rescan only *adds* newly-seen samplers; it never removes old ones,
so Delete is how you clear out the stale entries.

Clicking it opens a confirmation dialog (Cancel / Delete exporter);
the row is only removed once you confirm.

> **Delete is best-effort.** It removes the row (and its label)
> right away, but the rescanner re-creates it from observed traffic
> if that sampler is **still sending flows** — this time without
> your label. Delete is therefore meant for samplers that have
> actually stopped emitting; deleting one that is still active just
> resets its label on the next sweep.

---

## Devices page

> **Admin-only.** This page requires the `devices:manage` permission.

Where the Exporters page labels devices that *emit* flow records, the
**Devices** page connects obserae to your **OPNsense firewalls** to pull
**ground truth** the NetFlow pipeline alone cannot see: which MAC address
holds which IP (ARP), which hostnames the DHCP server handed out, and the
firewall's own interface subnets. obserae uses this to resolve IPs to
real hostnames/MACs in the cartography and to expose two new NFQL tables
(`arp`, `dhcp`) you can query and join against your flows and sessions.

### Adding an OPNsense device

Click **Add device** and fill in:

| Field             | What it is                                                       |
|-------------------|-----------------------------------------------------------------|
| **Name**          | A friendly name for the firewall (e.g. `opnsense-edge`).        |
| **Base URL**      | The firewall's web URL, e.g. `https://192.0.2.1`.              |
| **API key**       | The OPNsense API key (see below).                              |
| **API secret**    | The matching API secret. **Encrypted at rest** with the master key and **never shown again** — to change it you re-enter it. |
| **Skip TLS verify** | Toggle on if the firewall uses a self-signed certificate and you have no CA to pin. |
| **Root CA (PEM)** | Optional: paste your firewall's CA certificate to verify TLS properly instead of skipping verification. |

**Where to get the API key/secret in OPNsense:** in the firewall's web
UI go to **System → Access → Users**, open (or create) a user, and under
**API keys** click **+** to generate a key/secret pair. OPNsense downloads
a small text file containing both — copy them into the fields above.

### Refresh and status

obserae polls each device **every ~10 minutes** automatically. A poll
also runs immediately when you add a device, and you can force one any
time with the per-row **↻ Refresh** button.

Each row shows a status **pill**:

- a green **OK** pill with the last successful poll time (`last_collected_at`);
- a red **error** pill carrying the last error message if the most recent
  poll failed (wrong credentials, unreachable host, TLS mismatch …).

A failing device never blocks the others and never delays the daemon
boot — the error is recorded and the device is retried on the next cycle.

### What gets collected

Each poll pulls three things from the firewall:

- **ARP table** — every IP↔MAC binding the firewall currently sees,
  appended to an append-only store and exposed as the NFQL `arp` table.
- **DHCP leases** — the active leases (IP, MAC, hostname, lease type),
  exposed as the NFQL `dhcp` table.
- **Interface overview** — the firewall's interfaces and their CIDRs
  (Loopback and unassigned interfaces are filtered out), kept as a fresh
  snapshot that is replaced on every refresh.

### Where this data shows up

- **NFQL** — query `FROM arp` / `FROM dhcp` like any other table, and
  equi-join or `PIVOT` them against `flows.ip` / `sessions.ip` on `ip`
  to attach a MAC/hostname to traffic. See [NFQL](nfql.md#tables).
- **Cartography → DHCP hexagon** — a network's DHCP drawer shows the
  firewall-reported hostname, MAC and manufacturer for each lease,
  tagged by source (NetFlow, OPNsense, or both).
- **Cartography → IP Discovery** — IPs the firewall has seen in ARP are
  listed **first**, carrying an `arp` tag with their MAC/hostname. When you
  adopt one, the new host is **named after its hostname** (ARP first, then the
  DHCP lease); if no hostname is known — or the name is already taken — it
  falls back to the `?<ip>` placeholder you can rename later.
- **Cartography → Network Discovery** — the firewall's interface CIDRs
  are proposed as candidate subnets to declare as networks, and a subnet
  detected from traffic that matches an interface is **suggested with that
  interface's name** (e.g. `WORK`) instead of a generic slug. Network
  names are matched **case-insensitively** (so `WAN` maps to `wan`).

### Backup &amp; export

Devices are part of the [Config I/O](configuration.md) bundle, so an
export/import carries your firewall connectors with everything else. The
`api_secret` is exported in its **encrypted** form (the `enc:v1:` envelope),
never in clear text. Because that envelope is sealed with this instance's
master key (`data/secrets.key`), a bundle restores a working secret **on the
same instance**; importing it on a fresh instance (different master key) keeps
the device but you must re-enter its API secret.

---

## Cloud Attribution page

This page annotates every IP the daemon sees with its cloud
provider when applicable (AWS / Azure / Google Cloud / Oracle Cloud /
Cloudflare). On Sessions and Cartography, a small grey hint then
appears under the host: e.g. `52.93.x.x` shows up as
`AWS · us-east-1 · S3` instead of an opaque public IP.

### The master toggle

The **IP enrichment** slider at the top is the global kill-switch.
When off, the daemon stops fetching new CIDR ranges from any
source and stops resolving IPs at ingest time. Existing
annotations stay in place until you turn it back on or restart the
daemon.

> ⚠ The master toggle (labelled **Global enrichment**) is exactly that —
> **global**: it governs **every** enrichment source (Cloud Attribution,
> Threat Intelligence, GeoIP and ASN). The same switch appears on all
> these pages and stays in sync. Flipping it opens a **confirmation
> dialog** spelling out that it turns every source on or off at once;
> use the **per-source** toggles to enable or disable a single source
> without the dialog.

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

## Threat Intelligence page

Same shape as the Cloud Attribution page but for open-source
threat-intel feeds. It carries the same global **IP enrichment**
toggle (synced with Cloud Attribution). Hits surface as a red
triangle on Sessions and Cartography for any IP listed by an
enabled feed.

Seeded feeds:

- **FireHOL Level 1** — a curated list of known malicious networks
  (active attackers, bogons, hijacked ranges) that should never appear in
  legitimate traffic.
- **Tor exit nodes** — the IPs of Tor **exit** relays (the bulk exit
  list): the last hop where Tor traffic *leaves* the anonymity network and
  re-enters the public Internet.
- **Tor relays** — the IPs of **all** running Tor relays and bridges (from
  the Tor Project's onionoo service), each tagged with its node nickname —
  a superset that also covers middle and guard nodes.

Each has its own per-source toggle and Refresh button.

### Why flag Tor traffic?

**Tor** (The Onion Router) is a volunteer-run network that anonymises
traffic by bouncing it through several relays, hiding the real source.
That anonymity is legitimate for many users, but for a network operator a
connection to or from a Tor node is **context worth surfacing** during
triage:

- **Inbound from a Tor exit node.** Someone is reaching one of your
  exposed services *through* Tor to hide where they really are — a common
  pattern for credential-stuffing, scanning and reconnaissance. For most
  internal services this should simply never happen, so a hit is a strong
  signal.
- **Outbound to a Tor node.** An internal host connecting *out* to Tor is
  often a red flag: malware command-and-control and data exfiltration
  frequently tunnel over Tor to evade egress filtering. A server that has
  no business using Tor suddenly doing so deserves a look.
- **Faster qualification.** When an alert fires, the Tor tag instantly
  tells you the peer is anonymised, so you stop trying to attribute it by
  GeoIP/ASN (which only point at the exit node's hosting provider anyway).

When to use which feed: **exit nodes** is the high-signal list for
*inbound* suspicious traffic (that is the only kind of Tor node a client
on the Internet connects to your service through). The full **relays**
list also catches an internal host reaching *into* the Tor network at any
relay, at the cost of more matches.

Example — sessions where one side is a known Tor node:

```nfql
FROM enrichment_ips | WHERE source == "tor_exit" | KEEP ip
> FROM sessions | PIVOT ip == server_ip
                | LAST 3600
                | KEEP ip_a, ip_b, server_port, ab_bytes
```

**Limitations.** The feeds list only nodes that are *currently running*,
so a relay that just went offline lingers for up to ~30 minutes, and
private (unpublished) Tor bridges are not listed at all by design. The tag
means "this IP is a Tor node", not "this traffic is malicious" — it is a
qualifier for triage, not a verdict.

---

## GeoIP page

Same shape as the other enrichment pages, for **country-level
geolocation**. The single source builds its database from the five
regional internet registry (RIR) delegation files — the public,
license-free record of which IP block was allocated to which country.
No MaxMind account or API key required.

Once enabled, every **public** IP the daemon sees is tagged with its
ISO country code. The most visible effect is on **Cartography**: a host
whose interface IP is internet-routable and found in the GeoIP database
shows a small **country flag** at its top-right corner. Private/internal
IPs (RFC1918) are never geolocated and show no flag.

One thing sets GeoIP apart from the other sources:

- **Weekly refresh.** RIR data changes slowly, so the automatic refresh
  runs once a week (the *Refresh* button still forces an immediate fetch
  on demand). The same global **IP enrichment** toggle as the other
  pages governs it.

Like the other sources it is **enabled by default**. GeoIP matches
almost every public IP, so it writes more enrichment rows than the
cloud/threat feeds — disable it here if you don't want country tagging.

### What it is good for

A country flag next to a remote IP is the fastest possible context in an
incident review. Typical uses:

- **Spot the unexpected origin.** A database that normally talks only to
  local hosts suddenly has a session to a 🇨🇳 / 🇷🇺 address — the flag makes
  it jump out before you read a single port number.
- **Compliance & data residency.** Confirm at a glance that traffic for a
  given service stays inside the regions you expect.
- **Triage enrichment.** Combine the country with the ASN and threat tags
  on the same IP to qualify an alert quickly (see the ASN and Threat
  Intelligence pages).

### Accuracy & limitations

GeoIP is built from **free, public RIR allocation data**, not a commercial
geolocation product. Understand what that means before you rely on it:

- **Country granularity only.** You get an ISO country code — **no city, no
  latitude/longitude, no ISP/organisation name**. (Paid databases like
  MaxMind GeoIP2 offer city-level data; obserae deliberately avoids that
  licensing dependency.) For *who owns* the IP, use the **ASN** source
  instead.
- **It reflects allocation, not physical location.** The country is the one
  the IP block was *registered/allocated* to at a regional registry — not
  necessarily where the server physically sits. A cloud or CDN block
  allocated to a US entity may host machines in Europe, so a flag on an
  AWS / Cloudflare / Google IP can be misleading. Treat flags on
  cloud/CDN ranges with caution and cross-check with the cloud attribution
  tag.
- **Update latency.** A freshly (re)allocated or transferred block can take
  **one to two weeks** to appear in the published RIR files, and obserae
  itself refreshes weekly. GeoIP is not real-time.
- **Public, announced space only.** Bogons, reserved and unannounced ranges
  have no entry — those IPs simply show no flag. Private/RFC1918 addresses
  are never geolocated by design.

In short: GeoIP is excellent for *fast human context* and *anomaly
spotting*, and unreliable as *forensic ground truth* for cloud/CDN
endpoints. Pair it with ASN and the cloud sources for a fuller picture.

---

## ASN page

Same shape as the other enrichment pages, for **autonomous-system
attribution**. The single source builds its table from the
[ip2asn](https://iptoasn.com) dataset — the public mapping of every
announced IP range to the AS that owns it.

### What is an ASN?

An **Autonomous System** is a block of IP addresses operated by a single
organisation under one routing policy — an ISP, a hosting/cloud provider,
or a large enterprise. Each one has a number, written `AS<n>` (e.g.
`AS13335` is Cloudflare, `AS16509` is Amazon, `AS15169` is Google). It is
the unit Internet routing (BGP) works in: when a packet crosses the public
Internet, it hops from one autonomous system to the next.

For obserae this answers one practical question about any public IP: **who
owns the network it lives on?** That is often what you actually want to
know in an investigation — not the exact service, just "is this Amazon,
some hosting provider in another country, or a residential ISP?".

### Why it is useful

Its job is to **catch what the curated cloud/threat lists miss**. Those
lists are hand-published and incomplete; ip2asn covers essentially every
announced IP on the Internet. For example, Cloudflare's published CDN list
does **not** include the `1.1.1.1` public DNS resolver (`1.1.1.0/24`), so
that IP would otherwise show up as plain public — but ip2asn knows it
belongs to `AS13335 CLOUDFLARENET`. Once enabled, every public IP carries
its AS (number + organisation) in the host drawer, hover tooltip and NFQL.

A useful triage move is to list the autonomous systems your traffic
actually reaches:

```nfql
# Which networks do we egress to? (group sessions by owning AS)
FROM enrichment_ips | WHERE nature == "asn" | KEEP ip, detail
> FROM sessions | KEEP server_ip, ab_bytes | JOIN ip == server_ip
```

A brand-new AS appearing in that list is a classic "first seen" signal for
an alert rule.

### Limitations

- **An AS is not a service.** `AS16509` is *all of Amazon* — EC2, S3, every
  region at once. ASN tells you the owner, not which product or region (use
  the **Cloud Attribution** source for that).
- **No regional breakdown** and the dataset is large, so this is the
  heaviest source in memory.
- **Update latency.** A newly announced or reassigned AS can take days to
  appear; refresh is weekly.

Like GeoIP it is **enabled by default** and **refreshed weekly** (large
dataset, slow-changing). It is the heaviest source — disable it here if
you don't need AS attribution. The same global **IP enrichment** toggle
governs it.

---

## Where things live

- **REST endpoints** — `/api/exporters` (list / patch / delete /
  rescan) and `/api/enrichment/*` (toggles, refresh) back these
  pages.

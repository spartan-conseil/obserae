# The `std.community` rule set

## What it is, in one minute

`std.community` is a **ready-to-use bundle of 68 alerts** that watch your
network traffic and warn you when something looks risky, misconfigured or
suspicious — passwords sent in clear text, a remote-control service left
open to the Internet, a guest laptop reaching a database, a machine
scanning the network, traffic to a known-malicious address, and so on.

You don't have to be a security expert to use it. The rules are written in
**generic terms** ("a workstation", "a database", "the guest network")
rather than against your specific machine names, so the same pack works on
any network once you've told obserae what your machines *are*. Install it
from the **Rule Sets** page, label your network, and turn on the alerts you
want.

It ships:

| What | Count |
|---|---:|
| Network **zones** (e.g. user, dmz, server, guest, iot, ot) | 16 |
| **Environments** (production, test, …) | 8 |
| Host **roles** (workstation, database server, bastion, …) | 30 |
| Service **purposes** (dns, https, rdp, ssh, postgres, …) | 134 |
| Detection **rules** | 68 |

## How to use it (three steps)

1. **Install the pack.** Rule Sets → install `std.community`. This adds the
   vocabulary above and the 68 rules (they arrive read-only and you choose
   which to enable).

2. **Label your network.** In the cartography, tag your entities with the
   standard vocabulary: mark your office LAN as zone `std.user`, your jump
   host as role `std.security.bastion`, your database's service as purpose
   `std.postgres`, and so on. **The rules only become meaningful once your
   network is labeled** — an unlabeled network produces no alerts.

3. **Describe what's normal (the Flow Matrix).** Most rules in this pack
   work by *exception*: they only alert on connections you have **not**
   declared as legitimate in your Flow Matrix. So you tune the pack by
   **declaring the flows that are normal for you**, not by muting alerts.
   This is explained below.

Optionally, enable a few **enrichment sources** (threat-intelligence and
cloud lists) so the rules that rely on them can fire — see *Prerequisites*.

## How the pack decides what to alert on

There are two simple ideas behind the 68 rules.

### 1. "You didn't say this was allowed" (most rules)

62 of the 68 rules are **policy rules**. They look only at connections that
are **not already covered by your Flow Matrix** (the list of flows you've
declared as legitimate). The logic is:

> If you explicitly allowed this connection, it's fine — stay quiet.
> If you didn't, and it matches a known-risky pattern, raise an alert.

The practical consequence is important and friendly to beginners:

- A connection you've **declared as normal in the Flow Matrix never alerts**.
- When a rule fires on something that's actually legitimate, the fix is to
  **add that flow to your Flow Matrix** — not to silence the rule or fork
  it. Your Flow Matrix becomes your single, auditable "this is normal" list.

These rules carry the tags `requires-flow-matrix` and
`flow-matrix-unmatched`. Until you've built a Flow Matrix, expect them to be
noisy — that's normal: you're still teaching obserae what your network
looks like.

### 2. "This pattern is suspicious by itself" (a few rules)

6 rules are **behavioral**: they look for suspicious *shapes* of traffic
regardless of whether the connection was declared — because the signal is
the behavior, not the permission. Examples: a machine that contacts dozens
of others on the same port (a scan), or a server pushing gigabytes out to
the Internet. These carry the `behavioral` tag and may need their thresholds
tuned to your environment (`tuning-required`).

## What it actually detects

The 68 rules fall into a handful of plain-language families.

### Clear-text and legacy protocols (credentials exposed)

Old protocols that send passwords or data without encryption. If you see
these, someone could read the credentials off the wire.
Examples: **Telnet**, **FTP**, **TFTP**, **POP3/IMAP without TLS**,
**syslog without TLS**, **cleartext LDAP**, **SNMP v1/v2c**.

### Sensitive services exposed to the Internet

Administration and data services that should never be directly reachable
from the Internet — a top cause of breaches and ransomware.
Examples: **RDP, SSH, WinRM, VNC** (remote control); **databases**;
**directory services**; **Kubernetes API, Kubelet, etcd, Docker
Engine/Swarm** (container control planes); **OT/industrial services**.

### Segmentation violations (who shouldn't talk to whom)

Connections that cross trust boundaries you'd normally keep separate.
Examples: **guest → database / admin / SMB / directory**, **user → remote
admin**, **dev or test → production database**, **IoT → directory or
database**, **management-plane access from outside the management zone**.

### Egress hygiene (traffic leaving in the wrong way)

Outbound traffic that usually indicates a misconfiguration or a leak.
Examples: **workstations doing DNS straight to the Internet**, **SMTP to the
Internet from non-mail hosts**, **NetFlow/IPFIX export to the Internet**,
**OT protocols reaching the Internet**, **a rogue DHCP server** on an
untrusted zone.

### Suspicious behavior (anomalies)

Patterns that look like reconnaissance or exfiltration.
Examples: **horizontal scan** (one source, many targets, same port),
**vertical scan** (one source, many ports, one target), **admin fan-out**
(one source administering an unusual number of systems), **very large
uploads** to a single Internet destination.

### Known-bad addresses and Tor (threat intelligence)

Traffic to or from addresses on public threat lists.
Examples: **traffic to/from FireHOL Level 1** (known malicious ranges),
**internal hosts reaching Tor relays/bridges**, **Tor exit nodes reaching a
sensitive internal service**, **Tor proxy/control ports observed locally**.
These need the matching enrichment source enabled (`requires-enrichment`).

### Cloud (deliberately narrow)

Cloud use is mostly legitimate, so the pack only flags two contextual cases,
both tagged `tuning-required`: **OT zone reaching a public cloud**, and a
**database server pushing high volume to a public cloud** (possible
exfiltration or unmanaged backup — to investigate, never proof of
compromise).

## Severity levels

Each alert has a severity so you can triage at a glance:

| Severity | Meaning | In this pack |
|---|---|---:|
| **critical** | Act now — exposure or known-bad with high impact. | 18 |
| **high** | Investigate quickly. | 24 |
| **medium** | Review when you can; often needs context. | 20 |
| **low** | Informational / hygiene. | 6 |

## Prerequisites and tuning

**To get value from the pack:**

- **Label your cartography** (zones, roles, service purposes). Unlabeled =
  no detection.
- **Build a Flow Matrix** of your normal flows. The 62 policy rules depend
  on it; without it they are noisy.
- **Enable the enrichment sources** you need for the threat/cloud rules:
  FireHOL Level 1, Tor exit nodes, Tor relays, and the cloud lists relevant
  to you. Alerts tagged `requires-enrichment` stay silent without them.

**Tags worth knowing** (shown on each rule):

- `requires-flow-matrix` / `flow-matrix-unmatched` — only fires on
  connections you haven't declared as normal.
- `requires-enrichment` — needs a threat/cloud source enabled.
- `tuning-required` — expect to adjust the threshold or scope to your
  environment.
- `behavioral` / `includes-matched` — looks at all traffic, declared or not.
- `attack-tXXXX` — maps the rule to the corresponding MITRE ATT&CK technique
  (for teams that track coverage).

**A note for late adopters:** the threat/cloud rules match against IPs that
were enriched *at ingestion time*. If you enable enrichment after traffic
has already been recorded, older history may not carry the enrichment data
those rules need.

---

## Under the hood (for the curious)

This section is optional — you can use the pack without it.

### The "unmatched session" pattern

Policy rules don't scan raw flow records. They evaluate **closed sessions
that the Flow Matrix did not match**, then check the policy predicate
against the consolidated (per-conversation) view:

```nfql
FROM session_matches
| LAST <window>
> FROM sessions
| LAST <window>
| WHERE state == "closed"
| PIVOT NOT session_id == session_id      -- keep only sessions the Flow Matrix did NOT match
| KEEP correlation_id
> FROM sessions_consolidated
| LAST <window>
| PIVOT correlation_id == correlation_id
| WHERE <policy predicate>                -- e.g. client_ip == "internet4" and server_port_proto == "purpose:std.rdp"
```

Behavioral rules instead aggregate over `sessions_consolidated` with a
`STATS … HAVING` threshold (e.g. `COUNT_DISTINCT(server_ip) >= 20`).

### Evaluation windows and cadence

A rule's lookback (`LAST`) is set to at least its scheduler cadence plus a
five-minute overlap, so no activity falls between two evaluations:

| Cadence | Lookback | Overlap |
|---|---:|---:|
| `15m` | `LAST 1200` (20 min) | 5 min |
| `1h`  | `LAST 3900` (65 min) | 5 min |

The overlap can make one session visible in two consecutive evaluations;
that's intentional. Per-rule **cooldowns** prevent repeated notifications,
while the overlap guarantees coverage.

### Known limitation: long-lived sessions

`LAST` filters on a table's time column, which for sessions is `opened_at`
(when the conversation started). A session that stays open longer than the
lookback can therefore be missing when it finally closes. The five-minute
overlap protects against scheduler and sessionization delay; it does not
make arbitrarily long-lived sessions observable once their *opening* time
has scrolled out of the window. A future engine feature (a close-time
window operator, e.g. a `LAST_CLOSED` stage or a predicate over `closed_at`)
would be the proper fix.

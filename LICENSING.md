# Licensing & transparency

obserae is **closed-source, free-to-use** software published by Spartan Conseil
Cybersécurité. This page answers, in plain language, the questions people
reasonably ask about a closed-source tool they're about to run on their network.
It does not replace the license — the binding terms are in `EULA.txt` (French)
and `EULA.en.txt` (English courtesy translation), bundled with every release and
Docker image.

> obserae is currently **in alpha** (pre-1.0). Every feature is open and free
> while it stabilises — including the features planned to become Enterprise
> later (see *"Which features will become paid?"* below).

## Is obserae open source?

No. obserae ships as **proprietary binaries and Docker images; the source code
is not public.** You are free to download it, run it, configure it and file
issues — but not to read, modify or redistribute the source. A public GitHub
repository for docs, releases and issues is not the same as an open-source
license, and we'd rather say so up front than have you find it in the fine print.

That said, the source is **available for security review on request**: a
qualified reviewer evaluating obserae for production (say, a security team that
won't run a closed box on its network) can ask for code access under NDA. Write
to <licensing@spartan-conseil.fr>.

## Is it free? For whom?

Yes, for two groups (EULA art. 2):

- **Personal use** — a natural person, on their own behalf, for non-commercial
  purposes.
- **Eligible small business** — a group of **≤ 20 people *and* ≤ €2,000,000**
  annual revenue. Both criteria are cumulative.

It is **self-assessed**: there is no license key, no sign-up, no activation.
During the alpha, every feature is open to everyone.

## Why are there limits, if it's free?

obserae is both a passion and a business, and the bills are real. The aim is to
be generous — free for individuals and small businesses, one-off audits allowed,
every feature open during the alpha — without leaving the door open to abuse.
Software usually ends up *tightening* its license because of abuse at scale, so
obserae keeps a **few structural limits** rather than an unverifiable "fair use"
clause.

A structural limit is one a homelabber or a five-person shop barely notices (a
single administrator account is plenty for them) but that an 80-person company
trying to deploy free at scale feels immediately. It keeps the line clear without
anyone having to play policeman — and without punishing the people the free tier
is *for*.

## I run a bigger company / an MSP / a paid service on it?

Then you need a **commercial license** (EULA art. 3) — for any organisation above
the small-business threshold, for offering obserae as a managed service
(MSSP / SOC-as-a-service), or for paid services (audit, consulting, integration,
training) delivered to a client above the threshold. One narrow exception
(art. 4): an independent consultant may run a **one-off audit of ≤ 30 days** on a
larger client's infrastructure, provided the software is removed and the data
purged at the end and the report states that permanent use requires a commercial
license.

Commercial contact: <licensing@spartan-conseil.fr>.

## Which features will become paid?

A small, stable set — and we name them now rather than springing them on you
later. All of them are **free and open during the alpha**:

- **Users & access management** — multiple user accounts, groups, role-based
  access control (RBAC) and API tokens. (The single administrator login the GUI
  always requires stays part of the core product.)
- **Audit log** — the tamper-evident *who-did-what-when* journal.
- **Connectors to major commercial platforms** — the exact list is still open,
  but, for example, a connector that ships obserae's alerts into a SIEM such as
  IBM QRadar will be part of the commercial license.
- **Commercial IP-enrichment sources** — premium, cyber-grade enrichment feeds.
  (The free public sources — AWS, Azure, GCP, FireHOL — stay free.)

The principle is simple: **if you can afford cyber-grade tools and data sources,
you can afford to support obserae too.** The free tier keeps everything an
individual or a small team needs; the paid tier is where obserae plugs into the
expensive commercial ecosystem.

## Can the terms change under me later?

Not for a version you already have. The license is **versioned per release**: the
terms that shipped with your version are yours to keep, for that version, for
good (EULA art. 2.3). If the terms ever change, the change applies only to
*future* versions — downloading one release does not put you at the mercy of
whatever a later one decides. Nobody is taken hostage.

## Does obserae phone home or send telemetry?

No. The EULA commits to it contractually (art. 7): **no usage telemetry, no
outbound contact with Spartan Conseil's or any third party's servers, and no
online license verification.** obserae is built to run fully air-gapped.

The only outbound network traffic obserae makes is traffic **you** turn on:

- **IP-enrichment refreshes** — downloading *public* IP-range lists from AWS,
  Azure, Google and FireHOL. These are downloads of public data; nothing about
  you is uploaded. Turn them off with `enrichment.enabled: false`.
- **Alert delivery** — webhooks / Gotify to the destinations *you* configure,
  never to a vendor endpoint.

## What does the publisher see about my data?

Nothing. Your flows, cartography, detection rules, sessions and reports are your
**sole property**; Spartan Conseil has no access to them and claims no rights
over them (EULA art. 6.3).

## Do I need a license key or internet access to run it?

No key, no activation, no online check. obserae runs entirely offline — core
ingestion, queries and the GUI have no external dependency.

## What happens if the project stops, or Spartan Conseil disappears?

Your installation keeps working. There is **no remote kill-switch and no license
check to fail**, so an installed copy keeps running with no internet and no
contact with anyone. The license text and binaries are bundled locally, and your
data stays yours.

## Can I modify, redistribute or reverse-engineer it?

No (EULA art. 5) — beyond the non-waivable interoperability rights French law
grants under art. L122-6-1 of the Intellectual Property Code. Spartan Conseil is
the sole authorised distributor, through its official channels only
(`github.com/spartan-conseil/obserae` and `ghcr.io/spartan-conseil/obserae`).

## Can I contribute code?

No — obserae does not accept code contributions, and that is deliberate: a single
owner keeps the intellectual property clean and the project's direction coherent.
**Issues are very welcome**, though — bug reports, reproduction cases and feature
suggestions genuinely help. Open them at
<https://github.com/spartan-conseil/obserae/issues>.

## Is there support or an SLA?

The free license comes with **no support obligation** — updates are published at
the publisher's discretion (EULA art. 8). Technical support, priority fixes, SLAs
and custom development are part of commercial agreements.

Support contact: <support@spartan-conseil.fr>.

## Anything it must not be used for?

Yes — obserae is **not** designed or certified for life-critical or
high-criticality systems (medical devices, air/rail/maritime traffic control,
nuclear or Seveso-classified sites, weapons/defence systems, or critical
infrastructure without prior agreement). See EULA art. 10.

## Where are the binding terms?

In the repository and in every release / Docker image:

- `EULA.txt` — French, **the legally binding version**.
- `EULA.en.txt` — English, courtesy translation (the French version prevails in
  case of conflict).

Online copy: <https://github.com/spartan-conseil/obserae/blob/main/EULA.txt>.
Commercial licensing: <licensing@spartan-conseil.fr>.

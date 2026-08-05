# Changelog

A high-level history of obserae, newest first. obserae is in **beta** (pre-1.0)
and running in production at early-adopter sites: every feature is open during
the beta. Dates are release dates. This document is published as the dedicated
[Changelog](https://obserae.com/docs/changelog/) page on obserae.com. It is a
bird's-eye view, not an exhaustive commit log.

## [0.33.0] — 2026-08-05

Two themes. **Restitution**: obserae now produces the document you hand to an
auditor. **Response**: an alert now carries enough context, identity and
lifecycle for a SOAR to act on it without asking three follow-up questions.

### Added

- **Reports.** A new *Analysis → Reports* page turns a time window into a
  document you can read, keep, download or send on. **Operations** opens on what
  your network *is* — networks, hosts, services, NAT rules and declared flows,
  with the map drawn from your cartography at the positions, colours and groups
  you arranged — then covers what the detection engine emitted. **Compliance**
  reports which of the controls your installed rule sets claim to instrument
  really have a rule that is enabled and being evaluated, against NIS 2, DORA,
  SOC 2, ISO/IEC 27001, CIS Controls and MITRE ATT&CK, and closes on a rule
  annex giving each rule's condition in words, its remediation and the exact
  NFQL the detection executes — paste it into Investigation and see for yourself
  what a control is watching.

  It also says what it cannot prove: the control catalogue comes from the rule
  sets you have installed, so obserae never claims to know how many controls a
  framework contains, and a control with a live rule and no alert during the
  window is reported as **covered** — a clean period, never a gap.

  Every report is a print-ready PDF and a self-contained HTML file, in **English
  or in French**, chosen per report; names — frameworks, controls, your hosts and
  rules — are never translated, because they are what an auditor matches against
  their own paperwork. Reports also run unattended: a job fires daily, on chosen
  weekdays or on a day of the month (*the 31st* lands on a short month's last
  day) and mails the PDF to an SMTP destination. Each job carries its own
  **Reports to keep**, so a quarterly compliance pack survives a chatty daily
  report; the store as a whole keeps 200 reports, 180 days, 512 MB.

- **Alerts now carry their context, and an identity that survives a rename.** An
  alert used to hand a SOAR two bare IP addresses. It now says that `10.0.0.50`
  is `ci-runner-prod` of group `build`, that the destination is **not covered by
  any Flow Matrix rule**, and that the public address involved is listed by a
  threat feed, with the date that feed last refreshed — plus its ASN,
  organisation, country and cloud provider. That is three follow-up API calls a
  playbook no longer has to make. The context is **frozen at the moment the rule
  fired**, so a delivery retried an hour later re-ships the original reading, and
  it **never delays a notification**: if the lookups run long, the alert leaves
  on time with whatever was resolved. Tune it with `outputs.entities`
  (`full` / `carto` / `off`) and `outputs.max_entities`.

  The payload is now a named contract, **`obserae.alert/2`**. Matched rows arrive
  as objects instead of positional arrays, so a playbook keyed on `detail[0]` can
  no longer break silently when someone edits a rule's `KEEP`; each alert carries
  the NFQL and `as_of` that produced it, so posting them back to `/api/query`
  returns the same rows; and rules gain a **stable identifier** that survives
  renaming and is the same on every obserae running the same pack.
  `outputs.sample_rows` caps the evidence rows, `instance_name` labels the
  deployment, and your own instance publishes the schema at
  `GET /api/schemas/alert/2`.

  **Nothing migrates on its own.** Outputs that already exist keep receiving the
  exact bytes they always did; new ones default to v2, and a legacy output shows
  a before/after preview and a one-click switch.

- **Alerts can be sent in your SIEM's own language: ECS, OCSF or Splunk CIM.** An
  Elasticsearch index full of obserae's own field names supports no Elastic
  Security dashboard and no detection rule. An Elasticsearch output can now write
  **ECS**, so Elastic's network views populate and rules keying on `source.ip`
  keep working; a webhook or Splunk HEC output can send an **OCSF Detection
  Finding (class 2004)**, which Microsoft Sentinel, Google SecOps and AWS
  Security Lake ingest natively. The complete obserae alert travels along either
  way, so the matched rows and the entity block are still there as evidence. A
  **Splunk add-on** maps alerts onto the CIM Alerts and Network Traffic models,
  and the index template an Elastic cluster needs is served by your instance at
  `GET /api/integrations/elastic/template` — apply it before the first alert, as
  a mapping Elasticsearch guessed does not fail loudly, it just makes some
  queries return nothing.

  **No existing output changes shape**: only a newly created Elasticsearch output
  starts in ECS, and moving an index already mapped one way means a reindex, so
  the recommended path is a new one.

- **Eight new destinations.** **GLPI** opens a ticket in the helpdesk that is
  everywhere in French SMEs and served by no security vendor. **Jira** opens an
  issue, on Cloud or on Server / Data Center, and stops there — no polling, no
  status write-back. **Microsoft Sentinel** writes OCSF into a custom
  `Obserae_CL` table through the Logs Ingestion API. **MISP** publishes the
  publicly routable addresses an alert saw, with sharing defaults that are
  decisions rather than accidents: your organisation only, `to_ids` off, no
  immediate publication, private addresses never sent. **TheHive 5** creates a
  SIRP alert whose addresses arrive as typed **observables** carrying their
  cartography name, group and threat-intel verdicts. **Microsoft Teams** posts an
  Adaptive Card to a Workflows webhook or a MessageCard to a legacy Office 365
  connector — a visible setting, because the wrong shape does not fail, Teams
  just renders nothing. **Discord** posts a card to a channel webhook, and
  **ntfy** publishes to a topic, self-hosted or on ntfy.sh.

- **Connectors for Shuffle, n8n and Cortex XSOAR, and recipes for four more
  platforms.** They live under `integrations/`, alongside the Splunk add-on, and
  each declares the **contract** it targets — `obserae.alert/2`, SOAR profile
  `1.0.0` — never an obserae release number, because a connector pinned to a
  release is wrong within a quarter and wrong silently. The Shuffle app is the
  SOAR specification itself, imported. The n8n node has both halves: eight
  actions and a webhook trigger that verifies the alert signature and refuses to
  run with no secret configured. The Cortex XSOAR pack ships three commands and a
  segmentation-triage playbook that asks the Flow Matrix first, since a
  conversation the matrix already allows is a tuning ticket rather than an
  incident. **Tines**, **Torq**, **Sentinel (Logic Apps)** and **TheHive +
  Cortex** are documented as recipes — a webhook, a signature check, a few HTTP
  calls, nothing to install.

- **A page for the engineer wiring obserae into a SOAR.** Everything needed to
  build an *alert → enrichment → ticket* playbook is now in one document,
  [Response Integrations](https://obserae.com/docs/integration), written for
  someone who has never seen obserae: the alert contract field by field, how to
  verify a webhook signature in Python or in Go, the SOAR profile's operations,
  three end-to-end reference playbooks, and what leaves the instance in each
  direction — the question a security officer asks before approving an outbound
  destination. It also states plainly, because it is the first thing asked, what
  obserae does not do: it is out-of-band and blocks nothing, there is no firewall
  API here, and turning it off cannot break connectivity.

- **A SOAR profile of the API, typed enough to generate a connector from.** The
  OpenAPI document described 220 operations, and 224 of their responses were
  declared as "a JSON object" or "a JSON array" — which tells a code generator
  nothing, and left an integrator reverse-engineering the data model from
  examples. The fourteen
  operations a playbook actually calls are now fully typed, each with a response
  example, and ship as their own document, **`openapi-soar.yaml`**, which your
  instance serves at `GET /api/openapi-soar.yaml`: importing it produces fourteen
  actions rather than 220, and it is derived from the full specification so the
  two cannot disagree. `GET /api/alerts` also gained the filters an automation
  needs — `rule_id` (stable across renames), `tag`, `until`, `offset` — and now
  answers `{items, total, limit, offset}` instead of a bare array, `total` being
  what lets a client that pages know when to stop. The base URL is no longer
  hard-coded to loopback.

- **Five answers a playbook needs, without writing a query.**
  `GET /api/context/host` returns who a host talked to, who talked to it, what it
  served, how much it moved and which peers are new — each peer carrying the Flow
  Matrix's verdict on that exact conversation. `POST /api/context/peers` narrows
  the same question by direction, scope and count. `POST /api/policy/check` says
  whether a conversation was supposed to be allowed, names the covering rule, and
  when the answer is no, `nearest_rules` says what would have to change — `port
  not in rule`, `protocol mismatch`, `source not in scope`, `destination not in
  scope` — a closed list an integration can switch on, where `{"covered": false}`
  alone was never something an analyst could put in a ticket.
  `GET /api/enrichment/lookup` returns what obserae knows about an address, up to
  50 in one call. And `GET /api/alerts/{id}` and `GET /api/carto/hosts/{name}`
  read one alert or one asset back by id or name — often all a webhook body or a
  ticket field carries.

  The context endpoints take an `as_of` instant, so a playbook can place itself
  where the alert fired instead of where the network is now. The enrichment
  lookup keeps three answers distinct, and an integration should not collapse
  them: `threat_intel: []` means checked and unlisted, an absent `threat_intel`
  means not checked, and `{"verdict": "unavailable"}` means the database could
  not be consulted. Only the first means "clean".

- **An indicator feed a firewall can pull — obserae publishes a list, something
  else acts on it.** `GET /api/indicators` exposes the publicly routable
  addresses obserae's own detection rules fired on, as `plain` (one address per
  line, what a firewall or an RPZ ingests), `json`, `csv` or a `misp` manifest.
  Private addresses are never published — an RFC1918 line in a list something
  acts on would have someone cut off their own network. An address is one
  indicator however many alerts saw it, carrying the highest severity any of them
  gave it and the rules that saw it, which is the provenance a human needs before
  acting on such a line. It has its own permission, `indicators:read`, in no
  built-in group but `admin`, so the device polling it can hold that and nothing
  else, and it answers `ETag`, `Last-Modified` and `304 Not Modified`.

- **The complete documentation now ships inside obserae.** A new *Tools* section
  carries the whole product manual, rendered offline from the binary: an index,
  full-text search, per-page contents and working cross-links. Nothing is fetched
  from the internet, so an air-gapped install has exactly the same manual as any
  other. Every page in the GUI also gained a `?` in the top bar that opens the
  section covering it — Investigation opens NFQL, Cartography opens Cartography,
  Devices opens the device connectors.

- **A sizing calculator.** *Tools → Sizing* turns a flow rate, a session ratio
  and a retention policy into the disk, backup volume, memory and CPU a
  deployment needs, with the full per-store breakdown. Every number says where it
  came from — measured on a real production instance, estimated, or read from
  your own deployment — and the page says which figures have never been measured
  against a known flow rate rather than presenting a guess as a fact. On a
  running instance, **Use my instance** substitutes the coefficients your own
  data produces.

- **Reads made by an API token are now in the audit log.** Mutations and refusals
  were recorded, but a successful *read* left no trace, so "which automation
  queried what, and what came back" was a question the journal could not answer.
  Each call by a Bearer token to a SOAR-profile operation now leaves an entry
  carrying the operation, the permission that admitted it and the status code.
  Browser sessions are excluded on purpose: a page refreshing every few seconds
  would bury the trail an auditor came for. The entry format is unchanged, so a
  journal spanning this upgrade still verifies.

### Changed

- **Incidents now close by themselves — a behaviour change for anyone already
  routing to PagerDuty or Opsgenie.** Until now obserae only ever *opened* an
  incident: nothing resolved it, so the on-call engineer closed by hand and, in
  our experience, stopped trusting the integration inside a fortnight.

  An alert now opens an incident and closes it once the rule has come back clean
  three times in a row (`alerts.resolve_after_evaluations`, 1–20) — three rather
  than one because a condition that comes and goes would otherwise open and close
  an incident on every other tick. The alert also reaches **closed** in obserae,
  so the GUI and the SOAR agree, and acknowledging an alert here now reaches the
  destinations too: a SOAR no longer pages for an alert a human has taken. A
  heartbeat rule works the other way round, as it should — it fires when its
  query empties, so it closes when the data comes back.

  **Deduplication moved off the rule name.** PagerDuty's `dedup_key` and
  Opsgenie's `alias` were the rule's name, so renaming a firing rule opened a
  *second* incident and left the first open forever, and a group-by rule
  collapsed every entity onto one incident. Both now key on an identity built
  from your instance, the rule's immutable id and the alert's group key: renaming
  is free, a rule grouped by IP opens one incident per IP, and two obserae
  installations feeding one SOAR can no longer close each other's incidents.

  Resolutions are **on by default** for PagerDuty, Opsgenie, webhook, syslog,
  Splunk and Elasticsearch, and **off** for Slack, Mattermost, Telegram, Gotify
  and email, where a "resolved" message doubles the noise for the person reading
  it. Flip either with **Send lifecycle events** on the output. The trigger
  message is untouched in every case, and a resolution carries no matched rows on
  purpose: the condition is gone, so those rows would be stale evidence rather
  than proof of a resolution.

- **Four documented API responses corrected.** Each was documented as something
  the server does not send, so a client written from the specification would have
  failed on its first call while the document looked correct — listed
  individually because each is a breaking correction for anyone who trusted the
  old text:

  - `GET /api/alerts` was declared as a JSON array; it has always returned an
    object, now `{items, total, limit, offset}`.
  - `GET /api/carto/search` was declared as a JSON array; it has always returned
    `{query, matches}`.
  - `POST /api/alerts/{id}/status` was declared as `200` with a body; it returns
    **`204 No Content`**, and its status vocabulary is `new` / `ack` / `closed` —
    the documented example used a value the server rejects.
  - `DELETE /api/alerts/{id}` was declared as `200` with a body; it also returns
    **`204 No Content`**.

  Two of those responses also returned `null` instead of an empty array when
  nothing matched. They no longer can.

- **obserae is in beta, not alpha.** The product runs in production at
  early-adopter sites, on real traffic, day after day, while the documentation
  still described an alpha to be factored into a risk analysis. The published
  project status is now *beta, in production at early-adopter sites*, and the FAQ
  explains why an off-path collector is a reasonable thing to run in production
  before 1.0.

- **The EULA commits to open-sourcing obserae if it ever stops** (art. 8.3,
  French and English, EULA 1.1). Should Spartan Conseil permanently cease its
  activity or obserae be permanently discontinued, the source code of the
  complete Enterprise edition — every feature included, not a stripped-down
  core — is released under an open source licence letting users keep using,
  maintaining and evolving it, and the already-published builds stay
  downloadable. The licence also states what was until then only a design
  property: there is no remote deactivation mechanism, so an installed instance
  keeps running with the vendor entirely out of the picture. The wording on
  editions is more precise as well: Community needs no licence key at all, a
  commercial subscription ships a licence file renewed each year, and neither is
  ever checked against our servers — validation is local, so an air-gapped
  deployment renews by dropping in a new file.

- **Downloads and legal pages stay on obserae's own endpoints.** Downloads go
  through `get.obserae.com`, Docker Compose is fetched by the same installer, and
  legal, support and security links remain on `obserae.com` instead of sending
  readers to the distribution repository.

### Fixed

- **Rule packs asked for the wrong permission.** Every rule-pack route —
  installing, toggling, deleting a pack, and the vocabulary the cartography
  editor's dropdowns read — was gated on the **Flow Matrix** permissions instead
  of the alerting ones, so a user holding `alerting:write` but not `rules:write`
  could not install a detection pack. The routes now carry the permissions their
  own documentation always claimed. If you built a group around installing rule
  packs, check that it holds `alerting:read` / `alerting:write`.

- **Asking whether a flow is allowed required permission to change it.**
  `POST /api/rules/find-covering` modifies nothing but required `rules:write`
  purely because it is a `POST`; it now needs only `rules:read`, so an automation
  can check a flow before opening a ticket without being trusted to edit the
  matrix. The same reasoning governs the new `/api/enrichment/lookup`, which
  requires `sessions:read` rather than the `sources:manage` that covers the rest
  of `/api/enrichment`: reading what the feeds say is a read, configuring the
  feeds is not.

- **ASN badges came back empty.** The upstream that publishes the IP-to-network
  mapping began refusing one of its two files, and because the source refuses a
  half-loaded picture, that one refusal left obserae with no autonomous-system
  attribution at all — no `AS13335 CLOUDFLARENET` in host drawers, hover tooltips
  or NFQL. obserae now reads the publisher's single combined table, which covers
  IPv4 and IPv6 together and is served normally, and asks "has this changed?"
  before downloading, so *Refresh* no longer pulls roughly 9 MB when nothing
  moved.

- **A first start no longer requires laying the data directory out by hand.**
  Pointing obserae at a directory that did not exist yet — or at a database path
  in a sub-directory of its own, which is what the systemd and Docker layouts
  do — failed on an `IO Error: Cannot open file` naming neither the setting at
  fault nor the missing directory. The daemon now creates the data directory and
  the directory holding the database file on first start. Existing directories
  are left alone, permissions included, so a data area an installer hardened
  stays hardened, and the `mkdir -p` steps are gone from the installation and
  operations guides.

- **A schema migration could leave the database impossible to open.** A
  migration's schema changes reached the write-ahead log first and the database
  file only at the next checkpoint; an unclean shutdown in between — a `kill -9`,
  a power cut, an OOM — forced DuckDB to replay them at the next start, which
  hits an open DuckDB bug and aborts. The daemon then refused to start, with a
  stack trace and no obvious way back. A migration now folds its changes into the
  database file before declaring itself done, so no restart has to replay them.
  Recovery for a data directory already in this state is in the migrations guide.

- **A checkpoint that had stopped working said nothing.** Every ten minutes
  obserae folds its write-ahead log into the database file. A failure was logged
  as a warning and retried, which is right for a hiccup and wrong for a daemon
  that has not managed a single checkpoint in hours — the log then grows without
  bound and every write since the last success depends on being replayed at the
  next start. One production instance ran thirteen hours in that state.
  *Monitoring* now has a **Checkpoint (WAL)** panel: checkpoints completed, how
  long ago the last one succeeded, and after three consecutive failures a banner
  carrying the reason and what it costs.

- **The Assistant now finds the right documentation page.** A question naming a
  topic could miss the page devoted to it: asking about NFQL did not return the
  NFQL guide at all, and asking about NAT returned the NFQL page instead. The
  documentation search now ranks the page whose subject matches the question.

- **A configuration export now carries the whole configuration.** Restoring a
  bundle used to come back without the AI providers, without the NAT page's
  switches and decisions, and without the alert-journal retention — those areas
  had never been part of the exported file. They are now: provider endpoints and
  settings, including the API key encrypted with the instance master key; the
  Assistant's monthly budgets, named by user so the bundle travels between
  instances; the two NAT detection switches with the translations you invalidated
  and the proposals you dismissed; and the alert-journal retention. A bundle also
  carries each output's payload format, so restoring one no longer silently
  reverts every destination to the legacy alert.

- **The Assistant no longer imposes a silent limit.** A conversation used to hold
  400 messages and then close for good; unopened conversations were deleted after
  90 days; and opening a new one past the 200th quietly deleted your oldest. All
  three are gone. Keep one thread for as long as it is useful — compression
  already summarises the oldest turns so a long conversation stays affordable —
  and the only thing that removes a conversation is your own Delete button. Your
  monthly budget and the per-message limits are unchanged: those bound what the
  daemon spends on your behalf, not what you write.

- **Documentation corrections.** Seven cross-references pointed at headings that
  had been renamed — into the NFQL guide's table reference, its error section and
  its cross-table lookups, and into the session tuning section — and were broken
  on the published site too. The sizing guide also said retention was off by
  default, which is true of the code defaults and false of the `obserae.yaml` the
  installer, the tarball and the Docker image actually deploy; the page now says
  both.

## [0.32.0] — 2026-07-27

### Added

- **Enrichment data can be purged per source.** Disabling a source keeps its
  downloaded ranges so it can be enabled again immediately, while **Purge data**
  (or `obserae-cli enrichment purge NAME`) removes them when the disk space is
  needed. The source remains configured and past enriched traffic is unchanged.

- **The Assistant brings plain-language investigations and confirmed actions to
  obserae.** It can resolve objects on the map, build and run queries, inspect
  enrichment feeds, and answer with visible, re-runnable evidence. It can also
  propose changes to the cartography, flow-matrix and detection rules, and
  alerts; every write is checked against the user's permissions and requires
  confirmation unless it was explicitly auto-approved for that conversation.
  Conversations are private, retained for 90 days and covered by per-user
  budgets.

  Ollama, OpenRouter and DeepSeek providers are configured under Settings → AI
  Providers. obserae discovers their models and published prices, protects API
  keys at rest, and lets each provider override the Assistant's limits and
  generation settings. Full guide: **docs/assistant.md**.

- **Assistant conversations now have context and lifecycle controls.** A meter
  shows how much of the selected model's context window is in use. Old messages
  can be compressed manually or automatically without altering the visible
  thread or its exports. A running turn can be stopped, local thinking models
  show their reasoning while they work, and complete conversations can be
  exported as Markdown reports or faithful JSON archives.

- **NAT rules and detected translations can be managed from Network → NAT.**
  SNAT and port-forward rules are declared on the translating device, shown as
  readable sentences and used to fold both observed legs into one conversation
  via that device. The page also exposes detected translations, their direction
  evidence and rule proposals, including unused rules imported from OPNsense.
  Operators can invalidate a bad detection or change automatic-detection policy
  without restarting. Existing network-level declarations and older
  cartography bundles are migrated automatically. Full guide: **docs/nat.md**.

- **NAT correlation now works when one probe sees both sides.** Cartography can
  identify the translating device when exporter order cannot: declare its
  interfaces in both networks or an explicit NAT rule. NFQL exposes the method
  that proved each direction so the result remains auditable; without such
  evidence, same-probe traffic is deliberately left unmerged.

- **Alert maintenance now covers bulk cleanup and journal compaction.**
  `obserae-cli alert purge` deletes alerts selected by severity, status, rule or
  age, with confirmation by default. In the background, completed hours of the
  append-only alert journal are compacted into one current record per alert,
  keeping reads fast without dropping data.

- **Session queries can include cartography names.** The `client_host`,
  `server_host` and `server_service` fields expose the endpoint and service names
  recorded when a session closed, so investigations can show meaningful names
  without joins while preserving the historical context after later renames.

### Fixed

- **Disabling an enrichment source now stops matching immediately.** Its ranges
  are unloaded from memory and remain inactive across restarts; the global
  enrichment switch does the same for every source. Downloads remain on disk
  for a fast offline re-enable, and disabled sources can no longer be refreshed
  accidentally.

- **The Sessions matrix no longer reports unevaluated traffic as unmatched.**
  Sessions that closed after the matcher's last pass are shown as pending and
  excluded from both the Unmatched view and the cockpit's coverage calculation.
  Each aggregated ribbon also shows its matched and unmatched split.

- **Deleting many alerts is now a single batched operation.** Bulk deletion no
  longer re-reads and syncs the complete alert journal once per alert, removing
  the multi-second stalls seen with large selections.

- **Routine storage maintenance no longer raises false alarms.** Reads racing
  with Parquet compaction are still retried but logged at debug level, while
  genuine failures remain errors. Database checkpoints now wait for ordinary
  write transactions within a bounded interval instead of emitting harmless
  `checkpoint failed` warnings.

- **Editing the network map is responsive and no longer loses moves.** Editable
  topology is served independently from slower activity, alert, country and
  DHCP decorations, which load in the background. Superseded refreshes are
  discarded so an older response cannot repaint a node at its previous
  position.

## [0.31.2] — 2026-07-21

- **Fixed: clicking a network with a DHCP range no longer stalls for seconds.**
  On busy instances, opening a network that has a DHCP range configured could hang
  for tens of seconds, while networks without one (and host nodes) stayed fast.
  The drawer's "live DHCP leases" were computed by scanning the last 24h of traffic
  on every click, which on a busy sensor means opening thousands of small data
  files — so the click waited on the files, not the data. That computation now runs
  in the background and is cached, so opening a network (and the DHCP badge counts
  on the map) is a fast cache read. Two smaller cartography fixes ship alongside it:
  the firewall ARP/DHCP lease lookups now read only recent data instead of the whole
  history, and the network map's topology is no longer rebuilt behind a lock that
  could briefly freeze every map panel at once.

## [0.31.1] — 2026-07-21

- **Fixed: cartography labels no longer balloon when you zoom out.** Node and
  group names kept a fixed size on screen but were multiplied as the camera
  pulled back, so at topology-overview zoom they rendered enormous and
  overlapping — you had to zoom far in to read anything. Labels now keep a
  constant, legible size at every zoom, and when hosts pack tightly at overview
  zoom the map thins overlapping names to a readable subset (hover a node to
  read its name in full).

- **Fixed: cartography stayed fluid under heavy traffic.** On busy instances the
  cartography panels could randomly take several seconds to open. The web GUI now
  runs on its own database connection pool, isolated from background jobs, so a
  panel read never waits behind a heavy background scan; the network topology is
  cached and only rebuilt after an edit; and the graph's activity scans are
  bounded to recent data instead of the whole history. New
  `storage.web_reader_conns` setting (default 4) sizes the GUI pool.

## [0.31.0] — 2026-07-21

- **Added: the OpenAPI spec is now linted.** `make lint-openapi` runs vacuum
  (pinned as a `go tool`, no node toolchain) against
  `docs-web/docs/openapi.yaml`, and a CI job lints it on every pull request that
  touches the spec. This catches structural regressions — dangling `$ref`s,
  duplicate `operationId`s, invalid 3.1 constructs — that the previous
  reference-only guard test could not.

- **Fixed: the OpenAPI spec is importable again.** Retiring the Config I/O page
  accidentally deleted the whole `components:` block of
  `docs-web/docs/openapi.yaml` while leaving every `$ref` that pointed at it, so
  the shipped spec could not be imported into Postman/Insomnia. The block is
  restored, and a Go test now fails the build if any local `$ref` is left
  dangling.

- **Fixed: editing a rule no longer stalls detection.** Changing a rule or a
  flow-matrix cell rewound that rule's matcher cursor to "re-examine all of
  history". On any real retention horizon that never finishes: each pass had to
  read further back than the last, so the daemon burned CPU, stopped responding,
  and eventually stopped producing detections altogether — while ingestion, and
  every ingestion counter, stayed perfectly healthy. One rewound rule was enough
  to slow matching for every rule. The rewind is now bounded to the last few hours by
  default (`matcher.rematch_window`; set it negative to apply an edited rule to
  future traffic only).

- **Fixed: the detection matcher can no longer get permanently stuck.** Each
  pass now reads a bounded window of history (`matcher.catchup_window`, 2h by
  default) instead of everything since the last one, so a backlog drains at a
  steady rate rather than making every pass slower than the one before. A daemon
  that has fallen behind now catches up on its own, including after a restart.

- **Added: a horizon on how far behind detection may fall.** Past
  `matcher.max_lag` (6h by default) the daemon gives up on the history it cannot
  catch up on and resumes on live traffic. Those sessions are never matched
  against any rule, so it is not silent: the skipped window is written to the
  audit journal as `matcher.backlog.shed` and shown in the GUI as **Detection
  coverage dropped**. Set `matcher.max_lag: 0` if you would rather wait than
  lose coverage.

- **Changed: the detection backlog has its own panel in Monitoring.** It used to
  sit inside **Writer pool**, which could read "writer idle, all is well" while
  detection had been down for days — the matcher works on a different connection
  pool entirely. The warning now reports how far behind the matcher is (in time,
  which means the same thing whatever your traffic rate) and no longer suggests
  lightening rules or changing their cadence, neither of which was the cause.

- **Fixed: the backlog gauge no longer makes the problem worse.** Counting
  unmatched sessions meant scanning the whole session store every two seconds
  once the matcher fell behind, permanently occupying a quarter of the read
  capacity — taken from the matcher trying to catch up. The count is now an
  estimate; the alert is on how far behind the cursor is.

- **Fixed: cartography nodes no longer change size on their own.** Nodes could
  drift between too small to read and so large they overlapped, with no action
  from you. Two causes, both removed. The map resized itself whenever the canvas
  changed height — the read-only banner appearing was enough — because the
  compensation read the on-screen scale one frame too early and concluded there
  was nothing to correct. And every automatic refresh (another admin editing,
  any alert firing) re-derived the size from the span of the data, so one host
  dragged far away could squeeze everything else until the discs touched. Node
  size is now computed from the window alone, so the data cannot influence it.
  An automatic refresh updates what the nodes show and leaves your view exactly
  where it was, unless it would leave you facing an empty canvas — after a YAML
  import replacing the topology, for instance — in which case the map reframes
  rather than show you nothing. **Fit** now centres on the bulk of the map, so a
  distant host no longer drags the view into empty space. An active network
  filter or search also survives a refresh instead of being silently cleared.

- **Fixed: one bad NAT translation no longer blanks the Sessions riverview.** If
  a recorded NAT address could not be read back, the query behind the riverview
  failed outright and the chart stayed empty — once a second, for as long as the
  row lived. Such a row is now skipped: the riverview falls back to the NAT
  metadata held on the consolidated conversation and keeps drawing. The affected
  row is also reported in the daemon log so the underlying cause can be traced,
  and NAT observations carrying an unusable address are rejected before they are
  stored. Queries on `nat_translations` and `nat_relations` no longer return
  rows whose addresses do not parse.

## [0.30.0] — 2026-07-20

- **The master key has its own page, and the Config I/O page is gone.** Two
  unrelated things had been sharing one screen: a configuration bundle, which
  is portable operator data, and the master key, which is the root credential
  sealing every secret. The key now lives at **Settings → Master key**, where
  you can read it as base64, **download `masterkey.bin`** — the exact file the
  daemon reads at boot, so you can drop it into a data directory before a
  restore instead of decoding a `.txt` by hand — and rotate it. Exporting the
  configuration is now a button at the top right of the **Backup** page, next
  to a new **Download archive (.tar.zst)**; importing one stays on **Restore**,
  where it already lived. **Breaking:** `/api/config-io/*` moved to
  `/api/config/*` (export, import, restore) and `/api/masterkey/*`.

- **The separate "validate a configuration file" step is gone.** Importing a
  bundle already checks the whole file before writing anything, so an invalid
  file is refused rather than half-applied — the extra dry-run button, the
  `obserae-cli config validate` verb and the `POST /api/config-io/validate`
  endpoint only duplicated that guarantee. **Breaking:** scripts calling
  `config validate` should call `config import` and check its exit status.

- **The daemon starts in about a second instead of freezing for twenty.** On
  startup obserae rebuilt every threat-intel and cloud IP catalogue in memory
  *before* opening its network sockets. With large feeds that took roughly
  twenty seconds, and during the whole window no flow was collected — the
  exporters kept sending, and those packets were simply lost — while the web
  interface refused connections. The catalogues are now rebuilt in the
  background: listeners and the GUI come up immediately, and enrichment fills
  in behind them, source by source, over the next few seconds. Flows that
  arrive in that short window are collected normally; a handful may miss their
  threat-intel or cloud label. Loading is also faster in itself (about three
  times), so the window is short.

- **The turquoise accent is gone.** Progress bars, links, numeric values, chart
  series and cartography swatches used a turquoise `#4FBFBE` that clashed with
  the rest of the console. It is replaced everywhere by a periwinkle blue in the
  same cool family as the navy background, so the interface reads as one palette
  again. Cartography nodes you had coloured with one of the three retired
  turquoise swatches are remapped automatically on upgrade — no action needed.

- **Local backups are now multi-directory processes, and Run now shows a live
  bar + ETA again.** A local snapshot is a first-class process with **its own
  directory**, so you can run several — for example one to a local disk and one to
  a mounted NAS partition — each with its own full/delta cadence and retention;
  the standalone "Backup policy" card is gone. **Run now** on a remote (SFTP/S3)
  process shows a live **progress bar + ETA** again (it had regressed to a plain
  text line). A **full restore no longer drops your offsite backup configuration**
  — restoring an archive pulled over SFTP used to wipe the very SFTP destination it
  came from. On the Restore page, the cards are spaced out and **"Restore from a
  local archive"** now lives there (moved off the Backup page).

- **Backup is now a list of scheduled processes, with a new Data Protection menu
  and a redesigned Restore page.** Retention, Backup and Restore moved out of
  Settings into a dedicated **Data Protection** section. Instead of one global
  schedule, the Backup page opens on an **at-a-glance status strip** — how many
  processes, how many enabled, anything failing, the next run and the last
  success — above a **list of independent backup processes** (for example a
  **local copy every hour** and an **offsite copy once a day**). **"Add backup"**
  opens one self-contained form that sets **where the copy goes** (a local folder,
  an S3 bucket, or an SFTP server) together with **when** it runs (every N
  minutes/hours, daily, or weekly, in UTC) and **how many** to keep (*keep the
  last N*, or **smart (GFS)** — the newest of the last N days, N weeks and N
  months, default 7/4/3) — no configuring a destination separately first. Click a
  process to open a **detail panel** on the right with its settings, a **Run
  now** / **Test connection** / **Ship now** action row, its run history, and — for
  the local-snapshot process — the **point-in-time timeline** to restore to an
  earlier moment. A failed run surfaces as a **red error chip** with the message,
  so what broke is obvious at a glance. SFTP destinations gain an insecure
  **"skip host-key verification"** opt-in (and S3 a **CA-certificate / skip-TLS**
  option) for self-signed or un-pinnable servers — unsafe, surfaced with a warning.
  The **Restore** page pulls it together, full width: paste the master key once,
  then choose to restore **everything** (pull a remote `.tar.zst`, validated
  master-key-first, with a multi-step **progress bar + ETA**) **or the
  configuration only** (a bundle, no master key needed) — two clear choices side by
  side instead of an ambiguous stack of steps. **Run now** on any process now backs
  up immediately and shows a **live result** in the panel (running → ✓ shipped, or
  ✗ with an actionable hint) honouring the process's own retention — no more silent
  no-op — and the redundant "Ship now" button is gone. Failures that used to be
  dead ends now explain themselves: a destination blocked by the egress guard says
  to allow its CIDR in `backup.egress_allow_cidrs` and restart (instead of a bare
  `egress: destination address not permitted`), and an offsite backup with nothing
  to ship says to take a local snapshot first.

- **Config export/import now includes backup destinations and processes.** A
  consolidated config YAML (`obserae-cli config export` or the Config I/O page)
  now round-trips the offsite **backup destinations** (local/S3/SFTP) and the
  scheduled **backup processes** — previously they were absent, so a restored
  instance lost its backup wiring. A process references its destination **by
  name** (portable across instances), and each destination's secret rides
  **encrypted** (re-usable only on the same instance/master key — re-enter it
  after a move to a new instance).

- **Backups can now go offsite — download, S3 or SFTP — and restore directly.**
  Backups used to write only to a local directory, which is a single point of
  failure on a mono-instance host. A backup point-in-time can now be packaged as
  one portable, self-contained `.tar.zst` archive and **downloaded from the
  browser**, or shipped to an **S3-compatible bucket** (AWS, MinIO, Backblaze, …)
  or an **SFTP server**. Uploads run through an SSRF guard (an upload can't be
  pointed at cloud metadata or an internal service) and SFTP host keys are pinned.
  A destination can be flagged **ship-on-full**: after each daily full snapshot the
  archive is shipped automatically and remote storage is kept bounded (**keep the N
  newest**, prune the rest). Every ship shows a **live progress bar + ETA** and a
  persistent topbar indicator.
  **Restore is direct and master-key-first.** The archive contains everything
  **except the master key** (which never leaves the host in a backup), so to
  restore onto a fresh machine you upload the archive **and provide the matching
  `masterkey.bin`** — it is validated against the archive (format, DuckDB version,
  a sealed canary) **before anything is touched**, so a wrong key or a
  cross-version archive is refused up front with the live database intact; only
  then is the database swapped and the key installed. All of this is available in
  the web GUI (a new **Backup** page section, gated by the new `backup:read` /
  `backup:manage` permissions; the destructive restore stays admin-only) and at the
  command line: `obserae-cli backup destinations list|add|remove`,
  `backup ship --destination ID`, and
  `backup restore-from-archive --file … --master-key-file … --confirm`.

- **"Download archive" no longer hands back an empty file.** On a machine with no
  backup snapshot yet (backups off, or never run), clicking **Download archive**
  saved a **0-byte `.tar.zst`** that looked successful — the server hit "no
  snapshot to pack" *after* it had already sent the download headers, so the
  browser recorded an empty 200. The download now builds the archive **before**
  sending any header (a real error surfaces as a real HTTP status), and when
  there is nothing to pack it **creates a fresh full snapshot on demand** and
  streams that — so a first-time download just works, even with scheduled backups
  disabled.

- **Rotating the master key now re-encrypts every secret, not just three of them.**
  A master-key import (Config I/O modal or `obserae-cli masterkey import`) re-keyed
  only the alert-output secrets, OPNsense API secrets and session-signing keys —
  but silently left the per-user MFA secrets, the LDAP bind password, the OIDC
  client secret and the abuse.ch Auth-Key sealed under the *old* key. Once the old
  key was dropped, those four became undecryptable (MFA logins, LDAP/OIDC sign-in
  and the abuse.ch feeds would break). The rotation now covers all of them, and a
  test pins the full set so a new secret location can't drift out of coverage again.

- **Restoring a configuration no longer freezes the UI or looks like it crashed.**
  Importing a large bundle (a big cartography plus many rules) used to run
  synchronously inside the request: it blocked past the server's write timeout, so
  the reverse proxy returned a 502 and the page looked frozen — and even after it
  came back, rule compilation and the cartography rebuild were still running in the
  background, so opening the cartography showed an empty graph and the operator
  assumed the import had failed. The restore now runs asynchronously with a live
  **progress bar, per-phase detail ("compiling rule 45/200") and an ETA**, streamed
  over Server-Sent Events. A **persistent topbar indicator** shows the progress on
  every page, so navigating to the cartography mid-restore makes clear it is still
  running. Crucially, **"done" is now truthful**: the restore reports complete only
  once the cartography has been rebuilt, so the "Open cartography" button never
  lands on an empty graph. The restore also runs on a detached context (a proxy
  timeout or a closed tab can no longer cancel a half-applied restore) and is
  single-flight (a second concurrent restore is refused). The CLI/scripting
  `POST /api/config-io/import` stays synchronous and unchanged.

## [0.29.1] — 2026-07-15

- **Anomaly emission guards now actually reach the detector.** The spread floor,
  the variance-stabilizing transform and the direction / dead-band / persistence
  gates shipped in 0.29.0 were read by the edit form, the reconstruction chart and
  the validator — but the detector itself never loaded them. A rule configured with
  a spread floor still fired billion-sigma false positives on a near-constant count
  (a vertical-scan rule on distinct ports flipping 2↔1), while the chart drew that
  same point as *within normal*. Fixed end to end: the engine now loads every knob
  each tick, and creating a rule persists the guards on first save (they used to
  take effect only after a later edit). A reflection parity test pins the engine
  and store rule-loaders together so this class of drift can't recur silently.

## [0.29.0] — 2026-07-15

- **Anomaly rules gain emission gates — page on what matters, not on every blip.**
  Three optional knobs decide *what to alert on* once the baseline is right, and
  each is built so it can never create a blind spot. **Direction** fires only on a
  rise or only on a drop (a monotone port count vs. a liveness signal that
  shouldn't fall to zero). A **dead-band** ignores operationally-trivial
  deviations — a 3-vs-1 port count is huge in σ but nothing worth waking someone —
  while a *sustained* sub-band breach still escalates, so low-and-slow is never
  hidden. **Persistence** debounces single-bucket blips, yet a single massive
  spike still fires immediately. All default off, all gate only the alert (never
  the learning), and all are tunable live in the Anomaly Lab. The dead-band is the
  right tool where operators used to bolt a `HAVING` on the query — which silently
  *corrupts* the baseline by hiding observations from it.

- **Anomaly detection no longer pages all day on count metrics.** A detector that
  watches a discrete count — distinct ports, peers, hosts — used to fire the
  instant a normally-constant value ticked by one: with the spread collapsed to
  zero, a two-vs-one reads as a *billion*-sigma anomaly. Two composable knobs fix
  it, on every baseline method: a **spread floor** (in raw units — set it to the
  count quantum, `1`) that stops a collapsed spread from manufacturing a huge
  z-score, and a **variance-stabilizing transform** (`sqrt` for counts, `log1p`
  for byte volumes) so a single symmetric band is statistically valid on a skewed
  metric. Both default off — existing rules are unchanged — and both are tunable
  live in the Anomaly Lab (which now shows the effect on the fire count before you
  commit) and on the rule form. The nine shipped anomaly detectors adopt them.

- **The Anomaly Lab now tells you the real reason a query can't be tuned.** A
  single catch-all — *"it needs a terminal `STATS <metric> BY <keys>`"* — used to
  fire for seven different causes, including the common trap of a valid terminal
  `STATS ... BY` with a `HAVING` bolted on to "cut false positives". That `HAVING`
  is worse than nothing: the baseline only ever sees the rows the query returns,
  so a post-`STATS` filter censors observations and *corrupts* the learned normal.
  The lab now names the actual cause and, for a post-`STATS` filter, points you to
  a spread/trigger floor on the rule instead.

- **The Anomaly page is now a workstation.** Clicking a fire — or a baseline —
  opens **one screen per anomaly**: the chart with *the point you clicked starred*,
  and beside it everything needed to read it. A sentence says what happened
  (*"Observed 412 where 18 was expected — 9.7σ above the centre, outside the normal
  band"*), tiles give the numbers, and a rail carries the entity's identity, its
  other fires, the rows it matched, the *investigate at fire time* link, and
  Acknowledge/Close. Nothing needs a hover, and nothing needs a second page.
  The display window now follows the fire: a three-day-old alert used to open an
  empty 24-hour chart.

- **An alert tells you who its entity is.** An alert named its entity by value —
  `client_ip=203.0.113.10` — which is a number, not a lead. Every IP now reads as
  an identity: its **cartography asset**, name first (`web-01 (10.8.8.8)`), or the
  network it sits in; and for a public address its **country** (with flag), its
  **ASN**, and the **threat or cloud feeds that list it**. An address with no asset
  name is itself a finding — nothing in your inventory claims it. A composite key
  (`client_ip, server_ip`) shows both halves, one per line. On Detection and on
  Anomaly, rendered identically.

- **Fix: a composite-key anomaly rule never showed its fires.** Not "showed them
  wrongly" — showed **none**, silently, on its chart and in its entity detail.
  Every shipped scan detector groups by two columns, so this was the common case.
  The per-entity fire lookup only understood single-column keys and gave up on the
  rest without a word.

- **Fix: the Anomaly and Cartography pages had a phantom scrollbar.** Both computed
  their height with a formula written before the page footer existed, and so stood
  a footer's height taller than the space they had — a scrollbar on an empty page.
  Both now fit the window; the drawer and the graph scroll inside themselves.

- **Faster drawer.** Opening a rule replayed seven days of flows through the query
  engine just to decide whether to offer the activity heatmap. The heatmap is now
  computed when you actually ask for it.

- **Enrichment sources now explain themselves.** A feed used to be just a name:
  nothing told you what *IPsum* or *CINS Army* actually is, who publishes it, or
  whether it is noisy enough to bury you in false positives — you had to leave
  the page and read the docs. Hover a source name (or tab to it) on Threat
  Intelligence, Cloud Attribution, GeoIP or ASN and a card now gives its role,
  origin, confidence and false-positive profile, so you can decide whether to
  enable it on the spot. The same information is exposed on the API, under
  `info`, for every source.

- **Fix: an anomaly rule could not be created from scratch.** The form rejected
  *Create* with “needs a numeric column metric (not rows)” while the **Metric**
  field plainly showed the column — often the only one the query offered. The
  anomaly Metric picker lists numeric columns only, but the form's metric still
  defaulted to `rows`, which is not among them: the browser fell back to
  displaying the first column while the form kept submitting `rows`. With a
  single numeric column there was no way out, since re-picking the shown option
  changes nothing. The picker now holds what it displays. Editing an existing
  rule was hit by the same bug as soon as its saved query was re-selected.

- **Fix: an anomaly rule could not be deleted.** The drawer on the Anomaly
  Detection page offered Edit and Duplicate but no Delete, so a rule you own
  could only be removed from the Alerting Rules page. It now offers Delete, with
  the same confirmation, for any rule that is not owned by a rule set.

- **Fix: Duplicate did nothing on the Anomaly Detection page.** A ruleset-owned
  rule (`std.anomaly.*`) is read-only, so its drawer offers *Duplicate* instead of
  *Edit* — the only way to tune a shipped anomaly rule. On the Anomaly Detection
  page the button was wired to a handler that page did not have, so clicking it
  did nothing at all. It now clones the rule (and its query) into an editable,
  disabled copy and opens its drawer, exactly as on the Alerting Rules page.

- **Fix: form fields came back on a white background once the browser remembered
  them.** Re-opening *New alert rule* and picking a name you had already submitted
  handed the field to Chrome's autofill, which paints from its own stylesheet at a
  priority no page style can beat — a white box in the middle of a navy form. The
  app now declares a dark colour scheme, so everything the browser draws for itself
  (autofill, native `select` popups, checkboxes, scrollbars) follows the theme, and
  autofilled fields are repainted in the input colour. Applies everywhere a browser
  may autofill, not just to alert rules. The alert-rule modal also gains the focus
  ring and the accented checkboxes it was missing.

- **Fix: an anomaly rule's baseline method was ignored at run time.** The
  evaluator never loaded `baseline_method` or `anomaly_window` from the database,
  so **every anomaly rule ran as EWMA** with an unbounded window whatever the GUI,
  the rulepack or the config bundle said — while the chart on the Anomaly
  Detection page drew the *configured* method. Switching a noisy rule to
  **Median + MAD** or **Seasonal**, the fix the docs recommend, therefore did
  nothing. Both settings now reach the estimator. A rule already configured as
  `median_mad` or `seasonal` carries an EWMA baseline today and will re-enter
  warm-up once the right estimator takes over — expect a quiet period while it
  relearns, exactly as after a manual baseline reset.

- **New: the Anomaly Lab** (*Analysis → Anomaly Lab*). A page to design and tune an
  anomaly rule against your real data **before it pages anyone**. Pick a signal — an
  existing rule, a saved query, or NFQL typed on the spot — pick an entity, then move
  **k / α / N / warm-up**: the band, the graded anomalies and the alert count redraw
  as you go. A **sweep** scores a grid of settings and recommends the quietest one
  inside the alert budget you say you can read, and **Apply to the rule** writes it
  back. Because the signal need not be a rule yet, a rule can be worked out *before*
  it is created.

  It tells you two things the Anomaly Detection chart cannot. First, **the spread the
  estimator believes against the spread your data really has** — when that ratio runs
  away, the `k` on your rule is not the `k` that is running, and the page says so.
  Second, **the bucket the engine really uses**: a rule observes once per cadence, so
  the Lab replays at the cadence, while the Anomaly Detection chart re-buckets to fit
  500 points on screen — which is why *its* dots and its fire rings do not always line
  up. Nothing in the Lab is a second implementation: it folds your series through the
  engine's own estimator.

- **Docs: corrected anomaly tuning advice.** Two recommendations were measured and
  found wrong, and the guidance now says so. On a **heavy-tailed volume metric**
  (bytes, packets), freeze-on-fire withholds every firing value from the variance,
  so the estimator settles on a σ roughly **four times below** the data's true
  spread — `k = 3` really means `k ≈ 0.75`, and a healthy host pages you several
  times a day. The fix is a **much larger k**, *not* Median + MAD, which is tighter
  still on a skewed series and fires about twice as often. And on a **recurring
  burst** (a nightly backup), Median + MAD never goes quiet **at any k**. The Anomaly
  Lab measures all of this against your own traffic.

- **Fix: orphan anomaly baselines are now reclaimed.** An anomaly rule's learned
  baseline (`data/baseline/rule=<id>/`) used to survive when the rule was removed
  on a path other than a direct delete — a rulepack delete/upgrade or a config /
  alerting bundle import — so stale baselines accumulated on disk and in RAM (and
  showed up as bare hashes on the Storage page). Those paths now reconcile the
  baseline store against the live rules, and the daemon also sweeps orphans once
  at boot, so this no longer happens in production.

- **Storage page refresh.** The parquet-store charts are recoloured to the
  UI's steel-blue accent (was an off-brand turquoise). Stores that have no time
  axis now live in their own **Reference data** block, rendered as ranked bars:
  the **Anomaly Baseline** card — previously blank despite holding files — now
  shows a per-rule breakdown labelled by rule name, and enrichment ranges show a
  ranked-by-size source breakdown instead of a plain list.

- **abuse.ch Auth-Key is now part of the Config I/O bundle.** The shared
  Threat-Intelligence API key (Feodo/ThreatFox) was left out of config
  export, so a restore silently lost it and the feeds went quiet. It now
  travels in the bundle as its at-rest encrypted envelope (never in clear
  text) — the same round-trip devices' secrets use — so a restore recreates
  working feeds. A key sealed under a different master key is kept verbatim
  and flagged to be re-entered, and importing a bundle that leaves a
  key-gated feed enabled with no key on file raises a restore-time warning.

- **Fix: enrichment feed rows now align into clean columns.** On the Threat
  Intelligence and Cloud Attribution pages, each feed row's Refresh button,
  toggle and "Edit API key" button drifted horizontally from row to row (and
  jittered as feeds refreshed). The live row's grid was inheriting a placement
  rule meant for the static placeholder card, spawning phantom columns whose
  width followed each row's text; the action cluster is now pinned to a single
  right-aligned column on every row, mid-refresh included.

- **NAT-aware session consolidation.** Multi-exporter sessions can now be
  consolidated across inferred SNAT, DNAT and PAT while preserving pre-NAT
  endpoints. NFQL exposes bounded aggregate and recent socket-level NAT tables,
  and Sessions marks translated conversations without double-counting.

- **Eight new threat-intelligence feeds.** The Threat Intelligence page gains
  Emerging Threats (Compromised IPs), CINS Army, IPsum (with a tunable
  `ipsum_level`), FireHOL Proxies/Anonymous, an X4BNet VPN list, and the two
  abuse.ch feeds — Feodo Tracker and ThreatFox (the latter tagging each hit with
  its malware family). The keyless feeds are on by default; the abuse.ch feeds
  need a free Auth-Key, saved (encrypted at rest) from a new key field on the
  page and set/cleared via `PUT /api/enrichment/abusech-key`.

## [0.28.0] — 2026-07-08

- **One-line installer is now front and centre in the docs.** The
  `curl -fsSL https://get.obserae.com | sudo sh` installer — which downloads,
  verifies and deploys the systemd service in a single command — was buried at
  the bottom of the install page and missing from the README entirely. It is now
  the featured first method in the README's Quick Install and Option 1 on the
  Installation page.

- **Browser-tab favicon.** The web interface now sets the same brand icon as the
  public website (obserae.com) as its favicon, so the browser tab shows the
  obserae mark instead of a blank default on every page, including the sign-in
  and two-factor screens.

- **Cartography renders at a constant on-screen size on every screen.** On a
  small or short window (a laptop, a headless capture) the map used to cram its
  nodes together until they overlapped, while a large monitor looked clean. The
  map now keeps a fixed on-screen density whatever the viewport: a small window
  shows part of the map — pan to move around, zoom out to see it all — instead of
  squashing the nodes. Node size and spacing no longer change with the window
  size, so the topology reads the same everywhere.

- **Demo installer: no more permission error when importing the config.** Run
  via `sudo sh`, the demo files were fetched as root, so the manual
  `masterkey import - < obserae-masterkey.txt` / `config import - < obserae-config.yaml`
  commands failed with "permission denied" (the host-side `< file` redirect runs
  as your normal user). The installer now hands the demo directory back to the
  invoking user (`$SUDO_USER`) after fetching, so the import commands — and later
  edits to `.env` or the scripts — work without root.

- **Demo lab is benign by default; attacks are opt-in.** The `obserae-demo`
  environment no longer generates malicious "drift" traffic (network scan, direct
  DB access, external beacon) on its own — the workstations emit only normal
  traffic, so you can build a clean cartography baseline first. The three
  scenarios move into standalone scripts you run on demand, one at a time
  (`scripts/attack-scan.sh`, `attack-beacon.sh`, `attack-db-access.sh`), each with
  a configurable burst and the NFQL query to run when it finishes.

- **Detection "view rule" link now routes to the right page and pre-filters it.**
  Following the *view rule* link from an alert on the Detection page opens the
  targeted rule's drawer and filters the list down to just that rule. It also
  routes by rule kind: anomaly rules open the **Anomaly** page (they are managed
  there and are absent from the alerting-rules list, which previously produced a
  spurious "rule not found" warning), every other rule opens the **alerting-rules**
  page. The search box is pre-filled on both.

- **REST API reference + OpenAPI spec.** New docs page describing the full HTTP
  API — Bearer-token authentication, the permission model, error shapes and every
  `/api/…` endpoint with `curl` examples — plus a machine-readable OpenAPI 3.1
  description (`docs-web/docs/openapi.yaml`) you can import into Postman/Insomnia
  or render with Swagger UI / Redoc.

- **OpenID Connect (OIDC / SSO) sign-in.** A third way to log in, alongside local
  accounts and LDAP: employees sign in through an identity provider (Keycloak,
  Authentik, Microsoft Entra ID, Google…) by browser redirect. A new **Identity &
  Access → OIDC / SSO** page (and `obserae-cli oidc`) configures the issuer, client
  credentials, claim names and a *provider group → obserae role* mapping; enable it
  and a **"Sign in with …"** button appears on the login page. The flow uses PKCE
  and validates `state`, `nonce` and the ID-token signature/audience/expiry; a
  first login just-in-time provisions a shadow account. Policy: an identity that
  maps to **no** role is refused (no role, no access). The built-in **admin** stays
  a local break-glass login. The client secret is encrypted at rest and travels in
  the Config I/O bundle as its encrypted envelope.

- **Double-click to edit on the cartography.** In edit mode, double-clicking a
  host, network or group opens its edit form directly — a shortcut for opening
  the drawer and clicking **Edit**. Read-only double-clicks stay inert (inspect
  only).

- **Self-service password change + locked MFA disable.** On **My account**, a
  local user can now change their own password (verifies the current one, then
  signs every session out — you re-authenticate with the new password). And when
  an admin makes MFA **mandatory** for someone's group, the **Disable** button on
  their account page is greyed out and a direct disable request is refused — a
  mandated user can no longer strip their own second factor. LDAP accounts change
  their password in the directory, so the Password card is hidden for them.

- **Local authentication hardening: MFA, rate limiting, IP allowlist.** Three
  additions strengthen local sign-in (all local-account only; LDAP stays
  directory-owned):
  - **Two-factor authentication (TOTP).** Any signed-in user manages their own
    second factor from a new **My account** page (top-bar user menu): enroll an
    authenticator by scanning a QR code (or entering the secret), reveal
    single-use **recovery codes** once at activation, and disable after
    confirming a code. Login becomes two-step for MFA-enabled accounts, and
    admins can **require** MFA globally or per RBAC group on **Identity & Access
    → Login security** (a covered user is sent to enroll at next login). Admins
    can **reset** a user's MFA from the Users page for the lost-device case. The
    TOTP secret is encrypted at rest with the master key; recovery codes are hashed.
  - **Configurable rate limiting & lockout.** Failed logins (and OTP attempts)
    are throttled by **username and by source IP** with a temporary lockout;
    thresholds and durations are editable on the same page and persist.
  - **Source-IP allowlist.** Restrict where authenticated access may come from —
    for **all** users or per **RBAC group** — enforced for browser sessions and
    API tokens alike. A locked-out admin can clear it from the host.
  - **New "Identity & Access" sidebar section.** Users, Groups, API tokens,
    Login security and Authentication (LDAP) move out of *Settings* into a
    dedicated left-menu category, each its own page (the old in-page tabs are gone).
  - **Portable via Config I/O.** The rate-limit thresholds, IP allowlist and MFA
    policy are exported/imported in the consolidated YAML bundle under a new
    `login_security:` section (the policy only — never a per-user MFA secret);
    an import applies them live, no restart.

- **One-command binary install (`get.obserae.com`).** A new installer sets up
  obserae on a bare-metal or VM Linux host in a single command:
  `curl -fsSL https://get.obserae.com | sudo sh`. It selects the amd64/arm64
  build of the latest release, always verifies the **SHA256 checksum** and — when
  [`cosign`](https://docs.sigstore.dev/system_config/installation/) is present —
  the **Sigstore keyless signature** (`--verify-provenance` also checks the SLSA
  build provenance). Without cosign it says the binary is not signature-verified
  and lists what to install; `--strict` makes verification mandatory. It then
  deploys the full **systemd** service (service user, `/var/lib/obserae`,
  `/etc/obserae/obserae.yaml`, hardened unit, enable + start). Re-run to upgrade;
  `uninstall` (`--purge` to also drop data/config/user) to remove; `--download-only`
  verifies a release without installing.

- **One-command demo install.** The Docker-Compose demo lab (`obserae-demo/`)
  can now be deployed with a single
  `curl -fsSL https://demo.obserae.com | sh`. The installer fetches
  the lab files from GitHub, builds the images and starts the stack, then prints
  the next steps (UI, config-import one-liner). It doubles as a lifecycle tool —
  `status` / `logs` / `update` / `uninstall` — takes `--with-ldap` to also
  provision the FreeIPA/LDAP sign-in demo, and `--dir` / `--ref` / `--no-start`
  for control. FreeIPA now sits behind an `ldap` compose profile, so the default
  `docker compose up` (and the default install) stays light and fast.

## [0.27.0] — 2026-07-05

- **Fix — the Anomaly Detection chart modal is padded like every other modal.**
  The large time-series chart modal (`.modal__panel--chart`) had no inner
  padding, so the title, the window/scale toggles and the legend ran flush to
  the panel edges and looked about to overflow. It now carries the standard
  16px/24px breathing room.

- **Fix — ruleset-owned anomaly rules are read-only, like on the Rules page.**
  The Anomaly Detection page let you open the Edit form on a rule provided by a
  rule set (e.g. `std.anomaly.adaptive-exfiltration`); saving failed with a red
  *internal server error*. Pack-owned anomaly rules are now read-only in the
  drawer — the Edit button and baseline-method switch are hidden, a **Duplicate**
  action and a "provided by rule set … — read-only" note appear instead (and a
  `pack` badge in the list), exactly like the deterministic Rules page. Editing a
  pack-owned rule server-side now returns a clean **403** with the help text
  instead of a 500. Migration-free, GUI-only.

- **Cartography quality-of-life.** Three editor ergonomics on the `/carto` page:
  the **Network Discovery** and **IP Discovery** drawers gain a text box to filter
  their rows by IP/name or CIDR/name; clicking **+ Group** with hosts selected on
  the graph now opens the new-group form with those hosts **already ticked**; and
  the **Delete** key removes the selected hosts and networks after an aggregated
  cascade confirmation. Migration-free, GUI-only.

- **`std.anomaly` 0.5.0 — client-correct malicious-activity detectors.** The
  shipped anomaly detectors grouped by the canonical `ip_a` and summed `ab_bytes`,
  but that A/B order is not the client/server orientation — so exfiltration summed
  the wrong direction for a possibly-server endpoint. All rules now group by the
  inferred `client_ip` and sum the true client direction. The pack grows from 3 to
  **9** session-based detectors — adaptive exfiltration, egress fan-out, DNS
  exfiltration, lateral spread, lateral admin surge, vertical port scan, horizontal
  host sweep, half-open (SYN-scan) surge and auth brute force — each mapped to
  **MITRE ATT&CK** and the **NIS2 / DORA / CIS Controls v8 / SOC 2** detection
  obligations (carried in rule tags). The flows-based `scan-surge` is replaced by
  the client-correct scan rules. Migration-free.

- **Fix — the Install button in the Rule Sets modal is clickable again.** After a
  clean dry-run report, the button's disabled binding returned a non-boolean
  (`undefined` / `0`), which the framework left stuck as *disabled* — so installing
  a healthy pack (e.g. `std.anomaly`) did nothing and the button appeared to vanish
  on hover. It now enables for a clean report and only disables when a rule fails to
  compile; disabled solid buttons also keep their fill on hover instead of
  disappearing.

- **NFQL `sessions` surface reoriented to client/server (breaking).** The
  `sessions` query surface is now fully client/server oriented, mirroring
  `sessions_consolidated`. The canonical a/b columns — `ip_a`/`ip_b`,
  `port_a`/`port_b` and the directional `ab_*`/`ba_*` counters — are **removed from
  NFQL** (they stay in physical storage, where they remain the folding key and
  role-inference input). Query the client/server endpoints (`client_ip`,
  `client_port`, `server_ip`, `server_port`) and the reoriented directional
  counters `client_to_server_*` / `server_to_client_*` for bytes, packets, flows,
  flags, start and end. The virtual `ip`/`port` now expand to
  `server_ip`/`client_ip` and `server_port`/`client_port`. `SUM(client_to_server_bytes)`
  is the correct exfiltration metric. Computed on the `sessions_correlated` view
  (hot and archived parquet alike), NULL while the role is unknown; no data
  migration. **Custom saved queries or alert rules that reference `ip_a`/`ab_bytes`
  on `sessions` must move to the client/server columns** — they quarantine with a
  clear compile error until updated. Shipped packs are unaffected.

- **Homelab example bundle uses the `std.anomaly` rule set.** The example config
  now carries the anomaly detectors as the bundled `std.anomaly` pack
  (declared under `rule_sets`, auto-installed on import like `std.community` /
  `std.enterprise`) instead of in-place `alerting` rules left over from the
  removed in-page detector catalog — a shape that could strand the whole bundle,
  since dropping the paired `… (detector)` saved queries left the rules pointing
  at unknown queries and the config refused to import.

- **NFQL `client_ip` / `client_port` on `sessions`.** The `sessions` table now
  exposes the client endpoint as first-class, queryable columns — the side that
  is *not* the inferred server, computed from `server_ip`. Detection rules can
  target the requester directly (`WHERE client_ip WITHIN "10.0.0.0/8"`) instead
  of re-deriving it from the canonical `ip_a`/`ip_b` pair (which is a stable
  ordering, not a client/server orientation). They are NULL while the role is
  unknown, and behave identically over hot tables or archived parquet.

- **Sessions match-state toggle** (Analysis → Sessions): a new **All / Matched /
  Unmatched** segmented switch in the filter bar re-angles the riverview against
  the Flow Matrix — see only sessions a rule accounted for, only the ones none
  did, or everything. It works standalone ("every unmatched session in the last
  hour", bounded by the time window) or on top of a source/destination/port
  scope, and deep-links via `?match=matched|unmatched`.

- **NFQL fixes — pipeline chaining after `STATS` and true division.** Two
  compiler bugs are fixed. (1) A `>` pipeline separator placed directly after
  an expression-terminated stage — most commonly `STATS … BY <col>` — is no
  longer mistaken for a greater-than comparison, so `… | STATS out = SUM(x) BY
  ip > FROM … | JOIN …` chains without the `| LIMIT` workaround. (2) Division
  `a / b` is now correctly typed as `DOUBLE` (DuckDB's `/` is *true* division,
  fractional even for integer operands); an `EVAL ratio = a / b` no longer
  fails at scan time with *"converting driver.Value type float64 … to a
  int64"* and can be filtered against a decimal threshold in a later `HAVING`.

- **Anomaly time-series visualisations** (Analysis → Anomaly Detection): you can
  now *see* the anomaly, not just the fires. Clicking an entity opens a **large
  chart modal** — the **observed metric as a line over a moving normal envelope**
  (centre ± k·spread recomputed at every bucket) — for **every** baseline method
  (EWMA, Median + MAD *and* Seasonal, which keeps its 24 × 7 weekly grid behind a
  Timeline / Weekly-grid toggle). The chart reconstructs the **whole display
  window** regardless of the rule's own live window (a rule scanning `LAST 900`
  no longer draws a 15-minute sliver over a 24 h view), with **12 h / 24 h / 7 d**
  presets. Deviations are **graded by severity** (warning → major → critical by
  how far past the band they sit), the buckets that actually **paged** get a ring
  on the line, the **warm-up** span is shaded *learning*, and a hover card spells
  out observed / expected / bounds / z-score / status. Real zoomable axes and a
  **Linear / Log** value-axis toggle keep a few-kB baseline and a multi-MB spike
  both readable. A rule's **Activity heatmap** button opens a full-screen grid
  (top entities × time, blue = below / red = above normal, fired cells outlined,
  colour-scale legend); **click a cell to drill straight into that entity's
  chart**. Everything is drawn with ECharts and **reconstructed on demand** —
  obserae replays the rule's query bucketed over the display window and re-folds
  the same estimator the engine uses, so nothing new is stored and the scan stays
  bounded. Rules whose query can't be replayed keep the frozen-envelope band.

- **Anomaly Detection page — NDR-style redesign** (Analysis → Anomaly
  Detection): the page is now a self-contained home for **statistical** rules,
  fully separate from the deterministic **Rules** page (the two lists never
  mix). A **compact metrics bar** summarises the whole engine (rules active /
  learning / off, entities tracked, fires in 24 h, a 7-day timeline and a
  by-severity breakdown); the Rules page gains the same style of bar. Anomaly
  rules are **authored in place** — **New anomaly rule** opens a modal on the
  page (the same searchable query picker as the Rules page, no redirect) — and a
  filter box searches the list. Each rule gains an **inline baseline-method
  switch** (EWMA / Median + MAD / Seasonal), and selecting an entity draws its
  learned baseline as a **24 × 7 seasonal heatmap** or a **mean ± k·σ band**
  with the fires that broke it — all hand-rolled SVG, no new dependency.
  *Known limitation:* the activity charts reflect the most recent 5000 alerts.
- **`std.anomaly` rule set**: the three starter detectors (Adaptive
  exfiltration, Lateral spread, Scan surge) now ship as an installable **rule
  set** on the **Rule Sets** page, alongside `std.community`/`std.enterprise`,
  instead of an in-page catalog. Rule packs can now carry **anomaly-condition**
  rules (metric, group-by, baseline method and knobs), validated on import like
  any other rule.

- **Anomaly Detection page** (Analysis → Anomaly Detection): a dedicated
  screen for the statistical engine. It lists the anomaly rules with their
  baseline method, how many entities they track and when they last fired,
  with an on/off switch on each row; selecting a rule shows the per-entity
  baselines it has learned (mean ± spread / window / primed time-slots, and
  warm-up vs active) and its fires over the last 7 days. You can finally *see*
  the engine learn — a freshly enabled rule shows entities in warm-up flipping
  to active as traffic arrives. Creating a rule opens the editor pre-set to the
  anomaly condition.

- **Anomaly detection: seasonal (time-of-week) baseline**: a third
  **baseline method** that learns a separate normal for each hour-of-day ×
  day-of-week (168 slots per entity) instead of one flat average. A load
  that is high every weekday morning — backups, a nightly job, market open —
  is learned as normal *for that slot* and no longer alerts every morning,
  while the same value at an unusual hour still fires. It tunes like EWMA
  (α, k), needs a few weeks of data to prime every slot, and uses a lower
  default entity cap since it holds more state per entity.

- **Anomaly detection: robust median + MAD baseline**: an anomaly rule can
  now pick its **baseline method** — the default **EWMA** (rolling
  mean/variance) or **Median + MAD**, which keeps a sliding window of recent
  values and measures normal with the median and median absolute deviation.
  The robust option ignores outliers, so a metric that is legitimately spiky
  now and then (a weekly backup, a batch job) no longer blunts detection: one
  freak value neither raises the baseline nor hides the next real spike.
  Choose the window size on the rule form; everything else (k, warm-up,
  two-sided firing, freeze-on-fire) works the same.

- **Anomaly baselines stored in Parquet, not the database** (performance):
  the per-entity learning an anomaly rule accumulates now lives in a
  RAM-resident store that snapshots to compact Parquet files (one per rule)
  on a cadence and at shutdown, instead of a growing DuckDB table upserted
  every evaluation cycle. This keeps the database file and its checkpoints
  bounded no matter how many entities you track, takes the write off the
  single writer connection, and reports the store's size on the Storage
  page. A restart re-loads the baselines; a crash loses at most the most
  recent learning (it re-learns), and alert cooldowns stay transactional so
  you never get a duplicate alert.

- **Anomaly alert condition (statistical baseline)**: a new
  condition type alongside presence/threshold/first-seen/heartbeat. It
  learns, per entity (group-by key), a rolling baseline of a numeric
  metric and fires when the current value strays more than *k* standard
  deviations from normal — in either direction. This catches behaviour
  that has no fixed threshold: a host sending far more than *it* usually
  does (exfiltration), or reaching far more internal peers than usual
  (lateral movement), with no per-host tuning. It learns silently on
  cold start, freezes its baseline when it fires so one spike can't hide
  the next, and stays cheap (three numbers per entity, capped by
  *Max keys* and pruned like every grouped rule). Configure *k*, the
  adaptation speed *alpha*, and the warm-up length on the alert-rule form.
  
- **Behavioural NFQL aggregates** (`ENTROPY`, `MAD`, `SKEWNESS`,
  `KURTOSIS`): `STATS` gains four statistical functions that describe the
  *shape* of a distribution per group rather than its total. Entropy of
  destination ports per source flags scans; entropy of destinations flags
  lateral movement; skewness/stddev over inter-session deltas is the basis
  of a beaconing detector — all expressible in pure NFQL. Groundwork for
  the upcoming baseline/anomaly alert condition.

## [0.26.0] — 206-07-02

- **LDAP / Active Directory sign-in (hybrid with local accounts)**: employees
  can now log in with their Active Directory credentials alongside the existing
  local accounts. obserae verifies passwords with a service-account
  **search-and-bind** over LDAPS/STARTTLS, maps AD groups to obserae roles
  (refreshed on every login), and just-in-time provisions a shadow account on
  first sign-in. The built-in **admin** always stays a local **break-glass**
  login, so you keep access even when the directory is unreachable. Configure it
  on the new **Settings → Authentication** page (or `obserae-cli ldap set/test`);
  the service-account password is encrypted at rest. No SSO/OIDC yet.

- **NFQL decimal literals** (`20.5`, `0.95`): the query language now accepts
  fractional numeric literals, typed `DOUBLE` and comparable with integer/bigint
  values. This makes the statistical aggregates finally usable in a filter —
  `... | STATS sd = STDDEV(bytes) BY src_addr | HAVING sd > 20.5` — where before a
  `DOUBLE` from `STDDEV`/`MEDIAN`/`PERCENTILE` could not be compared to any
  threshold. No scientific notation; `PERCENTILE`'s rank stays an integer `1..99`.

- **Rule-set dry-run reports every broken rule at once**: validating a rule
  pack now compiles *all* rules and lists every NFQL compile error together,
  instead of stopping at the first. An author of a large pack fixes the whole
  batch in one pass. The Rule Sets page shows the full list and disables
  **Install** until the pack is clean; import still refuses a pack with any
  failing rule.

- **improve rule sets** community and enterprise.

- **Alert rules now evaluate in parallel** (performance): within each evaluation
  cycle the due rules' NFQL queries run concurrently — fanned out across a worker
  pool bounded by `storage.reader_conns` (default 4) — instead of strictly one at
  a time. A cycle's wall-clock drops from *sum of all due rules* to roughly *that
  sum ÷ reader_conns*, so deployments with many or heavy rules stop triggering the
  *"alert evaluation over budget"* warning. Results are still folded back in rule
  order and written in a single transaction per cycle (unchanged atomicity), and a
  slow/failing rule still can't starve or fail the cycle. Note: DuckDB already
  parallelises each individual query across cores, so on a CPU-bound host with many
  heavy rules you may want to lower `storage.max_threads` or space heavy rules out.

- **Unified daemon status snapshot** (`GET /api/status` + `obserae-cli status`):
  the authenticated web endpoint and the CLI command now return **one shared
  payload** — build version & uptime, data-format epoch, flow/session/rule and
  **cartography** counts, NetFlow **template** diagnostics, an alert roll-up (by
  status, by severity, plus 1h/24h windows), coverage, parquet-ingestion timing,
  storage usage (DuckDB file size, free/total disk on the database mount,
  parquet-buffer and backup directory sizes), runtime memory/goroutines and the
  audit-integrity verdict. Both surfaces are served by one shared collector, so
  they can never drift; the CLI output gains everything the API had (alerts,
  ingestion, storage, runtime, coverage) and the API gains what only the CLI had
  (cartography, templates, data-format epoch). It is the authenticated
  counterpart to the public `/healthz` liveness probe and is protected by an API
  token carrying the new **`monitoring:read`** permission; a matching built-in
  **monitoring** group ships with just that permission, so you can create a
  dedicated, least-privilege supervision user (admins hold it automatically).
  When the web GUI is disabled the producer-derived live metrics read zero and
  the payload's `live_metrics_available` flag is `false` (the counts, gauges,
  storage and alerts stay accurate). *Note: this endpoint was `GET /api/overview`
  earlier in this pre-release; it was renamed to `/api/status` with no alias.*
  
- **Cartography alert count now agrees with the Detection page** (fix): hovering
  a host showed e.g. "5 medium ssh" while the Detection list looked empty. Two
  causes, both fixed: the hover counts a **30-day** window (now spelled out in
  the tooltip: "N active alerts · last 30d") while Detection defaulted to 24h, so
  the host's older alerts were simply out of view; and the "Triggers"/rule links
  from a host now open Detection on that **same 30-day window**. On top of that,
  filtering Detection **by an IP** (the *Filter by entity key* box, or a link
  from a host) now also finds alerts from rules that don't group by entity — like
  *ssh detected* — whose address lives in the sample rows rather than the entity
  key. Previously those were invisible when filtered by IP.

- **OPNsense DHCP: Kea and Dnsmasq support**: the Devices connector now reads
  DHCP leases from whichever backend your firewall runs — **Kea**, **Dnsmasq**
  or the legacy **ISC dhcpd** — automatically, instead of only ISC. If more than
  one backend answers (a misconfiguration — only one should be active), obserae
  ingests the highest-priority one (Kea › Dnsmasq › ISC) and flags the device
  row with a **yellow ⚠**; hover it for the explanation. As part of this, each
  device is polled on its own, so one unreachable firewall no longer holds up
  the others.

- **Removed the one-time 0.25.0 upgrade shims** (internal): the boot-time
  `DATA_VERSION` → `data_version` file rename and the legacy
  `secrets.key`/`auditlog.key` → `masterkey.bin` unification are gone now that
  they have done their job. **Upgrades must come from 0.25.0 or later** — an
  instance still on those legacy layouts must boot 0.25.0 once before upgrading.

## [0.25.0] — 2026-06-30

- **CSRF tokens survive restarts and redeploys** (fix): the recurring
  "csrf token missing or invalid" error — which forced you to open a private
  browser window after an obserae change — is gone. The CSRF token is now a
  signed value bound to your session (an HMAC derived from the master key), so it
  is the same before and after a restart, the same across browser tabs, and
  self-heals if the browser drops or desyncs the cookie. Security is **higher**,
  not lower (the token can no longer be forged by setting a cookie). No action
  needed; already-open tabs may need one reload right after the upgrade.

- **Data epoch file lowercased** (internal): the data-format epoch authority is
  now `data/data_version` (was `DATA_VERSION`), in step with the rest of the data
  dir. **Upgrade is automatic**: the daemon renames the file in place once at the
  first boot of this version. *This one-time rename is removed in the next
  release.*

- **Single master key** (new): obserae now keeps **one** at-rest key,
  `masterkey.bin`, instead of two separate files (`secrets.key` and
  `auditlog.key`). Everything else is derived from it with HKDF — the AES-256-GCM
  cipher that protects stored secrets (alert credentials, device API secrets,
  session keys) and the HMAC key that signs the audit-log seals. You can now
  **export** the master key (base64) to your secret manager and **import** it
  back, from *Config I/O → Master key* in the GUI or `obserae-cli masterkey
  export|import`. Importing a different key **rotates** it: every secret is
  re-encrypted and every audit seal re-signed live — no restart, no downtime.
  Offline audit verification takes the master directly:
  `verify-auditlog --master-key-file masterkey.bin` (the standalone Python
  verifier too). **Upgrade is automatic**: an instance with the old two key files
  is unified under `masterkey.bin` at the first boot of this version (the old
  files are re-keyed, then deleted) — back up the new key. *Legacy support for the
  old files is only in this version and will be removed next release.*

- **OPNsense Devices connector** (new): a Connectors → Devices page (admin-only)
  where you register your OPNsense firewalls (name, base URL, API key/secret —
  the secret is encrypted at rest and never shown again, plus skip-TLS / Root-CA
  options). obserae then polls each device every ~10 minutes (or on demand via
  the per-row **Refresh** button) for its **ARP table**, **DHCP leases** and
  **interface overview**, with a per-device OK/error status pill. The ARP and
  DHCP observations become two new NFQL tables — `arp` and `dhcp` — that you can
  query and equi-join/PIVOT against `flows.ip` / `sessions.ip` like any other
  source: the authoritative IP↔MAC↔hostname ground truth the NetFlow pipeline
  alone cannot see. The same data enriches the cartography: the DHCP hexagon
  drawer shows the firewall's hostname/MAC/manufacturer for a lease, IP Discovery
  lists ARP-seen IPs first with an `arp` tag, and Network Discovery proposes the
  firewall's interface CIDRs as candidate subnets. Network and host **names**
  come from the firewall too: a subnet detected from traffic that matches an
  interface is suggested with that interface's name (`WAN`, `LAN`, …) instead of
  a generic slug, and adopting a discovered IP names the new host after its
  ARP/DHCP hostname (falling back to the `?<ip>` placeholder when none is known
  or the name is taken). Devices are part of the **Config I/O** bundle
  (export/import); the `api_secret` is exported in its encrypted form (never in
  clear text) — re-importable on the same instance. Adding a device now collects
  it immediately (its data appears in the drawer without reloading the page),
  and the DHCP lease panel was made legible.

- **Alert rules no longer self-disable during parquet compaction** (fix): an alert
  rule could be quarantined with `IO Error: Cannot open file …sessions-*.parquet:
  No such file or directory` whenever the background compactor merged an hour's
  session files at the exact moment the rule's query was reading them. The query
  engine now retries that transient "file vanished mid-read" race (the same guard
  the cartography and health screens already used), so it never surfaces. The fix
  covers every parquet reader that lacked it: interactive NFQL queries, the alert
  evaluator, the matcher, network-discovery aggregation, and the rule match view.

- **Monitoring page** (new): a Settings → Monitoring screen for sysadmins and SOC
  engineers. It surfaces parquet **ingestion** throughput and import timing (files
  and records written, flush last/avg/max), **pipeline** saturation (channel fill +
  UDP drops), **memory** (heap in-use, RSS ceiling, goroutines, GC, sessions in RAM),
  and **database** activity shown *permanently* — the in-flight operations plus a
  recent-operations ring (like `obserae-cli ps`), not just whatever happens to be
  running at the instant you look. The DB-activity panel was removed from the Cockpit
  (which stays focused on product use); when there is a real database or ingestion
  problem a warning icon appears in the top bar, from any page, linking to Monitoring.

- **Move a whole multi-selection in the cartography** (fix): in edit mode, selecting
  several hosts/networks (shift+click or box-select) and then dragging only moved the
  node under the cursor — the rest of the selection stayed behind. Dragging any selected
  node now translates the entire selection together and persists each node's new
  position.


## [0.24.0] — 2026-06-26

- **No more silent session loss under storage pressure** (fix): when the disk or
  parquet writer fell behind, the sessionizer could mark a batch as flushed while
  only part of it had actually been written, losing the rest without a trace — and
  the final batch at shutdown could vanish entirely. Flushing now blocks until the
  writer catches up (rather than dropping records on a timeout), the shutdown drain
  reliably persists the last batch, and the rare residual loss (a genuinely wedged
  disk) is **counted and surfaced** in the cockpit as a "Session data loss" banner
  instead of being invisible.

- **Human-readable memory limit** (config, **breaking**): `storage.memory_limit_mb`
  is renamed to `storage.memory_limit` and now accepts a size (`512MB`, `4GB`), a
  percentage of physical RAM (`50%`), a bare number (= MB), or `0`/`""` for DuckDB's
  default. The shipped configs default to `50%`. Percentages are resolved against
  physical RAM at boot (DuckDB has no `%` unit). **Action required:** rename the key
  in your config — the old `memory_limit_mb` is no longer read and would be silently
  ignored, reverting the cap to DuckDB's ≈80%-of-RAM default.

- **Cockpit stays fast on long-running instances** (perf): the live cockpit health
  panel refreshes every 2 seconds, and several of its counters look at the rule
  matches. Those lookups used to scan the entire match history on every refresh,
  so on an instance left running for a day or two the CPU climbed and memory grew
  without bound. They now only read the recent time window (the same partition
  pruning already used elsewhere), keeping the cost flat regardless of uptime.

- **Automatic data migration on upgrade** (OBS-MIG): obserae no longer loses your
  data when the schema changes between versions. The whole data directory
  (DuckDB + parquet stores + JSONL journals) now carries a single version stamp
  (`DATA_VERSION`), and deploying a newer build converts the previous version's
  data to the new format automatically at startup — across all three storage
  formats, not just SQL. The conversion is gated by a selective on-disk backup
  (`migration_backup/`, only the data a given migration actually rewrites, never
  your keys) with a disk-space pre-check that refuses loudly rather than running
  out of room half-way, and a crash marker that stops the daemon booting on a
  half-finished migration. Additive changes (a new column/field) cost no copy at
  all. `obserae-cli status` shows the current data version; `obserae migrate
  status` and `obserae migrate restore` inspect and roll back from the command
  line. See [Data migrations](https://obserae.com/docs/migrations).

- **Interactive query path extracted to a testable service** (OBS-AUD-012): the
  NFQL execution logic behind the Investigation page (snapshot lock, as-of
  anchoring, bounded scan, truncation) moved out of the HTTP handler into a pure
  `query/interactive` service, unit-tested without an HTTP stack. No behaviour
  change — a refactor that makes the security-sensitive query path easier to
  review and verify.

- **CLI actions record the OS user** (OBS-AUD-011): on Linux, admin actions made
  through the control socket now carry the connecting process's UID/GID (read via
  SO_PEERCRED) in the audit log, giving a finer trail than the single "cli"
  principal on a multi-admin host. Other events are unchanged.

- **Interrupted restores are detected at boot** (OBS-AUD-009): a restore writes
  a marker before swapping the database and its on-disk stores, and removes it
  only once both are in place. If the daemon dies mid-swap, the next start
  refuses to boot with an actionable message instead of silently running on a
  possibly inconsistent database/stores pair — re-run the restore or clear the
  marker after verifying.

- **CSRF protection on GUI mutations** (OBS-AUD-005): every state-changing
  request made with the session cookie now requires a double-submit token (an
  `obserae_csrf` cookie echoed in the `X-CSRF-Token` header or a `csrf_token`
  form field). The GUI wires this automatically for HTMX, island `fetch`, and
  native forms; API-token (Bearer) clients are unaffected. A forged cross-site
  POST can no longer trigger config import, backup, output or user changes.

- **Interactive NFQL queries bounded at the engine** (OBS-AUD-007): a broad
  query typed in the Investigation page without a `LIMIT` is now capped at the
  SQL level (DuckDB stops scanning at the display cap) instead of loading the
  whole result set into memory before truncating. Programmatic queries
  (detection engines, CLI) and queries with an explicit `LIMIT` are unaffected.

- **Write-lock contention is now observable** (OBS-AUD-008): when a bulk writer
  (enrichment refresh, config import) has to wait on long-running NFQL reads to
  finish, that wait is counted and — past the DB-wait threshold — logged as a
  warning, instead of being silent. Helps explain a sporadically slow admin
  action under heavy query load.

- **XSS defence pinned by tests** (OBS-AUD-006): the strict Content-Security-Policy
  keeps `'unsafe-eval'` (required by Alpine.js), so server-side `html/template`
  auto-escaping is the primary defence. A new test stores a `<script>` payload in
  an operator-controlled field and proves the rendered HTML escapes it, alongside
  the existing test that forbids `'unsafe-inline'` on `script-src`. The remaining
  `'unsafe-eval'` is documented as accepted tech debt.

- **Docs reflect the real auth posture** (OBS-AUD-010): stale comments and docs
  that wrongly implied the GUI was unauthenticated / assumed a single operator
  are corrected — the GUI requires a login backed by users, groups, RBAC and
  API tokens. A guard test fails the build if such a claim reappears.

- **Audit source IP no longer spoofable** (OBS-AUD-004): the `X-Forwarded-For` /
  `X-Real-IP` headers are now honoured for the audit log's source IP only when
  the request's immediate peer is a configured trusted proxy (`web.trusted_proxies`,
  CIDRs or bare IPs). A direct client can no longer forge its IP in the journal.
  The real client is taken as the rightmost non-proxy hop, so a spoofed leftmost
  value is ignored. Default is to trust no proxy header.

## [0.23.0] - 2026-06-24

- **Signed releases with SBOM and provenance**: every release now ships keyless
  (Sigstore/cosign) signatures, a per-archive SBOM, and a SLSA build-provenance
  attestation for both the tarballs and the Docker images. Because obserae is
  closed-source, these artifacts let you prove a download's integrity,
  authenticity and origin before running it. No key to manage — verification uses
  the public Rekor transparency log. See the new
  [Verify a Release](https://obserae.com/docs/verify) guide.
  
- **Secrets encrypted at rest**: alert-output credentials (Slack/Telegram/SMTP/
  webhook tokens, Splunk/PagerDuty/Elasticsearch keys) and the session-signing
  key are no longer stored in clear text in the database. On first boot the
  daemon generates a 32-byte master key (`<data_dir>/secrets.key`, mode `0400`,
  configurable via `secrets.master_key_file`) and seals those columns with
  AES-256-GCM. Existing clear-text values are migrated automatically at the next
  startup. **Back up `secrets.key` offline alongside the database** — losing it
  makes encrypted credentials unrecoverable and invalidates all sessions.
  Password and API-token hashes are unchanged (already one-way).

- **Rule Sets — per-rule disable now survives config import**: disabling an
  individual rule inside a pack used to be lost the moment you imported any
  config bundle that also carried an *Alerting* section — the export right after
  showed every rule re-enabled. The alerting import now leaves pack-owned rules
  untouched (it only ever owned your own queries and rules), so a per-rule
  enable/disable choice round-trips through export/import and persists across
  later imports of other sections. Rebuild the database after upgrading.

- **Rule Sets — packs auto-install on config import**: a `rule_sets` section that
  references the bundled **community** pack now installs it automatically during
  config import, so restoring a configuration no longer requires installing the
  pack by hand first. Operator-uploaded packs that are not present still warn
  ("upload it first") because their content is not part of the config bundle.

- **Community pack — four new vendor-neutral detections** (`std.community` 0.2.0):
  *iot-to-remote-admin* (an IoT device opening SSH/RDP/WinRM/VNC/Telnet sessions —
  lateral movement), *dns-tunneling-volume* (high-volume DNS to one Internet
  destination — tunnelling/exfiltration), *ssh-bruteforce-or-scan* (a burst of SSH
  sessions against one host — brute-force/scan), and *iot-internet-connection-burst*
  (an IoT device fanning out to many Internet destinations — beaconing/C2). All
  thresholds are tunable.

- **Cartography read-only is now truly read-only**: when the map is read-only
  (you haven't taken the edit lease, or another admin holds it), dragging a node
  no longer moves it on screen and the **Edit** buttons on documentation are
  hidden. Previously a node would shift during the drag and only snap back after
  a round-trip, and the documentation editor could be opened (the save was
  refused by the server, but only after the fact). Both actions are now gated up
  front. No database change.

## [0.22.0] — 2026-06-22

- **Flow Matrix — clearer interface/service mismatch error**: scoping a rule to
  an interface that doesn't carry the chosen service used to fail with a vague
  "service resolves to no interface". The live preview now names the interface
  and where the service actually binds — e.g. *service "https" is not bound to
  interface "eth1" (bound on eth0)* — so the fix is obvious without saving.

- **Flow Matrix — interface qualifier in the entity picker**: scoping a rule to
  one NIC of a multi-homed host is now a single, discoverable action. The
  separate **Interface** field is gone; instead the src/dst entity picker
  suggests interface-qualified refs (`host:web-01:eth0`, `host:web-01:eth1`…) as
  you type a host name — pick one and the rule targets just that interface's IP.
  Rules saved with the older two-field shape still open and edit correctly. No
  database change.

- **Interface-scoped queries are now discoverable**: the engine has always
  resolved `"host:NAME:IFACE"` (e.g. `"host:dns:eth0"`) to a single interface's
  IP, but nothing surfaced the syntax. The Investigation page's schema sidebar
  now has an **Interfaces** section listing every host's named interfaces —
  click one to drop the `"host:NAME:IFACE"` token at the caret and scope a query
  to one NIC of a multi-homed host. No database change.

- **Cartography edit lock (one editor at a time)**: when several admins are
  logged in, the cartography no longer lets them silently overwrite each other.
  The page is **read-only by default**; click **Edit** to take the **edit lease**
  (an *Editing* badge) and **Done** to release it — changes save as you go.
  Everyone else is then **read-only** with a banner naming the current editor,
  disabled controls and a **Request edit** button. **Only one editing session
  can be open at a time**, including the same admin in two windows: the second
  window's Edit is refused until the first clicks Done — so you can't reproduce
  the double-edit problem by opening two tabs. The lease **expires after 90 s**
  if a tab crashes, and the rule is enforced on the server too (a carto change
  from a non-holder is refused). No database change.

- **Docker data-volume permissions**: the images now create
  `/var/lib/obserae/data` and `chown` the whole `/var/lib/obserae` tree to the
  non-root user (UID 65532) at build time, so the daemon can write its database,
  parquet store and cache out of the box — no manual `chown` on the host bind
  mount before the first start.

- **Alert outputs — eleven new destinations**: alerts can now be delivered far
  beyond webhook/Gotify. **Messaging**: Slack, Mattermost and Telegram (bot
  token + API). **SIEM**: Syslog (RFC5424 over UDP/TCP/TLS, as JSON, **CEF** for
  ArcSight or **LEEF** for QRadar), Splunk HEC, and Elasticsearch/OpenSearch
  (basic or API-key auth). **Incident**: PagerDuty (Events API v2) and Opsgenie
  (US/EU), both de-duplicating on the rule name. **Email**: SMTP with
  STARTTLS / implicit TLS and optional auth. Every type rides the existing
  reliable outbox (retry with backoff, delivery audit) and the SSRF egress
  guard — now extended to the raw syslog/SMTP connections too — with secrets
  redacted on read as before. New destinations are picked from the type
  dropdown on the **Outputs** page; **Send test** works for each.

- **Richer alert payloads**: deliveries now also carry the rule's **tags**, a
  threshold rule's **observed value**, and a group-by rule's **key** — included
  only when the rule produced them. They flow into the webhook JSON, Splunk
  events, Elasticsearch documents, syslog JSON, and PagerDuty/Opsgenie details,
  and map to native fields where it helps (Opsgenie **tags**; CEF/LEEF carry the
  observed value and tag list). Message templates expose `{{.RuleTags}}`,
  `{{.ObservedValue}}` and `{{.KeyJSON}}`.

  > ⚠️ **Database wipe required.** This release adds columns to the output
  > delivery outbox (DuckDB schema change). Delete the DuckDB database file and
  > let the daemon recreate it on next start. **Your YAML config (cartography,
  > rules, alerting, outputs, …) is unaffected and re-imports cleanly.**

## [0.21.0] — 2026-06-21

- **Rule sets (rule packs)**: install ready-made, vendor-neutral detection
  bundles. A rule set adds a **standard vocabulary** to the cartography —
  `zone`/`environment` on networks, `role` on hosts, `purpose` on services —
  and ships rules written against it, so the same pack works on any
  deployment regardless of your naming. These attributes are queryable in
  NFQL (`zone:dmz`, `role:workstation`, and `port_proto == "purpose:std.dns"`
  for the port/protocol-based `purpose`). A new **Rule Sets** page installs
  packs (with a dry-run preview), enables/disables a whole pack, and shows a
  full impact screen before deletion; packs can depend on one another with
  version constraints. Pack rules land on the Alerting page as read-only
  (enable/disable or **Duplicate** to customise). Ships with the
  **community** pack: ten common detections (cleartext protocols, exposed
  RDP, DNS hygiene, direct database access, …). Config export records which
  packs are installed and their enabled-state — never the pack contents.

  > ⚠️ **Database wipe required.** This release changes the DuckDB schema
  > (new rule-pack tables, plus `zone`/`environment`/`role`/`purpose`
  > columns on the cartography). Delete the DuckDB database file and let the
  > daemon recreate it on next start. **Your YAML config (cartography,
  > rules, alerting, …) is unaffected and re-imports cleanly** — export it
  > first if needed, then re-import after the wipe.

- **Cartography discovery funnel**: build the map straight from observed
  traffic in two stages. **Network Discovery** (new) proposes candidate
  **subnets** clustered from non-routable (private) flows — `/24` per LAN,
  widening to `/23`–`/16` on contiguous ranges — and **+ Declare**
  pre-fills the network form. **IP Discovery** (the renamed *Orphan IPs*
  drawer) then surfaces the individual IPs to add as hosts. Internal /
  external separation is preserved: Network Discovery is private-only;
  routable peers stay on `internet4`/`internet6` via IP Discovery.

- **Self-documented cartography**: every host, network and group can now
  carry its own free-form **Markdown documentation** — runbooks, ownership
  notes, escalation steps, whatever the entity needs. The drawer renders it
  as formatted, sanitized HTML with an **Expand** full-screen view and an
  **Edit** button to update it inline. The documentation lives with the
  entity in the cartography, so it travels through config export/import
  (a `documentation` field in the YAML) like the rest of your map.

## [0.20.0] — 2026-06-17

- **Append-only alerts**: alerts are now persisted as an append-only JSONL
  journal (same model as the audit log); the alerts view is folded
  event-sourced and has its own retention.
- **Tamper-evident audit log**: every journal line carries a `seq` + `prev`
  SHA-256 hash chain, and closed files are anchored by HMAC seals in a separate
  registry. The format is verifiable from Go, the CLI (`verify-auditlog`) and a
  standalone Python tool.
- **Performance**: a series of ingest- and tick-path optimisations (slow-tick
  and DB-growth fixes) for steadier throughput at high traffic.
- **Accordion sidebar**: pages are now grouped under collapsible themes —
  **Network**, **Analysis**, **Connectors** and **Settings** — with Cockpit
  and Audit log as direct links. The group for the page you're on opens
  automatically, and your expand/collapse choices are remembered.
- **Lifecycle split**: the old single Lifecycle page is now three pages under
  Settings — **Storage**, **Retention** and **Backup**.
- Removed the **Flow Simulator** and the empty **Settings** placeholder page.
- Public documentation overhaul: `docs-web/` reorganised (landing README +
  `docs/`), a comprehensive **Configuring Exporters** guide, and a
  **Licensing & transparency** page.
- Web-GUI hardening guidance (reverse-proxy TLS, secure-cookie behaviour).

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

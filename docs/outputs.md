# Outputs

Outputs send your alerts **out** of obserae — to a chat channel, an
on-call app, a ticketing system or a SIEM. Where [Alerting](alerting.md)
decides *when* an alert fires, an output decides *where it goes*.

obserae ships these kinds of output:

- **Webhook** — an HTTP `POST` (or `PUT`/`PATCH`) to any URL. Works with
  incoming webhooks, automation platforms, or your own endpoint.
- **Gotify** — a push to a [Gotify](https://gotify.net/) server.
- **Slack** — a message to a channel via the Slack API (bot token).
- **Mattermost** — a post to a channel via the Mattermost API (access token).
- **Telegram** — a message to a chat or channel via the Telegram Bot API.
- **Syslog** — an RFC5424 message to a SIEM over UDP/TCP/TLS, as JSON, **CEF**
  (ArcSight) or **LEEF** (QRadar).
- **Splunk HEC** — an event to a Splunk HTTP Event Collector.
- **Elasticsearch / OpenSearch** — one document per alert into an index.
- **PagerDuty** — raises an on-call incident (Events API v2).
- **Opsgenie** — raises an Opsgenie alert (US or EU region).
- **Email (SMTP)** — sends an email through your SMTP server.

Open the **Outputs** page from the sidebar (after **Detection**).

---

## Create an output

Click **+ New output** and fill in the form.

**For a webhook:**

- **URL** — where to POST the alert (if it's on your own network, see
  **Internal destinations** below).
- **Method** — `POST` (default), `PUT` or `PATCH`.
- **Custom headers** — one `Key: Value` per line (e.g.
  `Authorization: Bearer …`).
- **Body template** — leave empty to send obserae's default JSON
  (`id`, `rule_name`, `severity`, `fired_at`, `matched_count`, `detail`, plus
  the enriched `rule_tags` / `observed_value` / `key` when the rule has them —
  see *What's in an alert* below), or write your own using `{{.RuleName}}`,
  `{{.Severity}}`, `{{.FiredAt}}`, `{{.MatchedCount}}`, `{{.Detail}}`, `{{.ID}}`.
- **Signing secret** — optional. When set, every request is signed so the
  receiver can verify it really came from obserae (see *Verifying
  webhooks* below).

**For Gotify:**

- **Server URL** — your Gotify base URL (e.g. `https://gotify.example.com`).
- **App token** — the Gotify application token.
- **Priority** — leave at `0` to derive it from the alert severity, or pin
  a fixed `0–10`.
- **Title / Message templates** — optional. Leave empty for the defaults:
  - title → `[HIGH] postgres-present` (`[<SEVERITY>] <rule name>`)
  - message → `Alert "postgres-present" fired at 2026-06-04T12:00:00Z (7 matched).`

  Or write your own with the same fields as the webhook body:
  `{{.RuleName}}`, `{{.Severity}}`, `{{.FiredAt}}`, `{{.MatchedCount}}`,
  `{{.Detail}}`, `{{.ID}}`. **The default message does not show the matched
  rows** — to include them, add `{{.Detail}}` to your message template, e.g.
  `{{.MatchedCount}} match(es): {{.Detail}}`.

**For Slack:**

- **Channel** — the channel id or `#name` your bot is allowed to post to.
- **Bot token** — the bot user OAuth token (`xoxb-…`) with `chat:write`.
- **Message template** — optional; leave empty for a compact one-line default
  (`[HIGH] postgres-present — 7 matched at …`).

**For Mattermost:**

- **Server URL** — your Mattermost base URL (e.g. `https://mm.example.com`).
- **Channel ID** — the channel's **id** (not its display name; copy it from the
  channel's *View Info*).
- **Access token** — a personal or bot access token.
- **Message template** — optional (same default as Slack).

**For Telegram:**

- **Chat ID** — the numeric chat id, or `@channelusername` for a public channel.
  (Message [@userinfobot](https://t.me/userinfobot) to find a numeric id.)
- **Bot token** — the token [@BotFather](https://t.me/BotFather) gave you. The
  token is kept secret and is never shown again after saving.
- **Parse mode** — `Plain text`, `MarkdownV2`, `HTML` or legacy `Markdown`.
- **Message template** — optional (same default as Slack).

The **message template** for Slack/Mattermost/Telegram uses the same fields as
the webhook body — `{{.RuleName}}`, `{{.Severity}}`, `{{.FiredAt}}`,
`{{.MatchedCount}}`, `{{.Detail}}`, `{{.ID}}`.

**For Syslog:**

- **Collector address** — `host:port` of your syslog receiver / SIEM.
- **Transport** — `UDP`, `TCP`, or `TCP + TLS` (use TLS for an encrypted feed;
  the TLS options below then apply).
- **Format** — `JSON`, `CEF` (for ArcSight) or `LEEF` (for QRadar).
- **Facility** — syslog facility `0–23` (default `16` = local0).
- **App name** — the RFC5424 APP-NAME (default `obserae`).

  Syslog has no token to enter. (Internal collector on your LAN? See
  **Internal destinations** below.)

**For Splunk HEC:**

- **HEC base URL** — e.g. `https://splunk.example.com:8088`.
- **HEC token** — your HTTP Event Collector token.
- **Index / Sourcetype / Source** — optional routing for the event.

**For Elasticsearch / OpenSearch:**

- **Cluster base URL** — e.g. `https://es.example.com:9200`.
- **Index** — where to write (one document per alert).
- **Authentication** — `Basic` (username + password) or `API key`.
- **Password / API key** — the credential for the chosen mode.

**For PagerDuty:**

- **Integration (routing) key** — the Events API v2 key from your PagerDuty
  service.
- **Source** — optional label shown on the incident (default `obserae`).

  Repeated fires of the same rule update **one** incident (de-duplicated on the
  rule name) instead of paging on every tick.

**For Opsgenie:**

- **API key** — your Opsgenie API integration key.
- **Region** — `US` (`api.opsgenie.com`) or `EU` (`api.eu.opsgenie.com`).

  The alert priority is derived from severity (critical→P1 … info→P5), and
  repeated fires de-duplicate onto one alert (by rule name).

**For Email (SMTP):**

- **SMTP host / Port** — your mail server, e.g. `smtp.example.com` / `587`.
- **Connection security** — `STARTTLS` (587, recommended), `Implicit TLS`
  (465), or `None` (plaintext — lab only).
- **From** — the sender address.
- **To / Cc** — recipients, comma-separated.
- **Auth username / password** — leave the username empty to send without
  authentication; otherwise the password is stored securely.
- **Subject / Body templates** — optional. Defaults to `[HIGH] rule-name` and a
  compact summary; use `{{.RuleName}}`, `{{.Severity}}`, `{{.MatchedCount}}`,
  `{{.Detail}}`, etc. for your own.

> **Internal destinations.** For every output where **you** supply the address —
> webhook, Gotify, Mattermost, Splunk, Elasticsearch, syslog and SMTP — obserae
> refuses an **internal** target by default (localhost, `10.x` /
> `172.16.x` / `192.168.x`, the `169.254.x` cloud-metadata address, …) as an
> SSRF safety guard: saving one returns an error. To reach a destination on your
> own network, add its CIDR to `outputs.egress_allow_cidrs` in the config (see
> [configuration.md](configuration.md)). The fixed-endpoint outputs (Slack,
> Telegram, PagerDuty, Opsgenie) always go to the provider and are unaffected.

Then set the **routing** (below) and tick **Enabled**.

---

## What's in an alert

Every output sends the **same alert content**, shaped to fit the
destination — a JSON body for a webhook, Splunk event or Elasticsearch
document; a chat message for Slack / Mattermost / Telegram / Gotify; a
syslog line (JSON / CEF / LEEF); an incident for PagerDuty / Opsgenie; an
email for SMTP. An alert carries:

| Field | What it is |
|-------|------------|
| `rule_name` | the rule that fired |
| `severity` | `info` / `low` / `medium` / `high` / `critical` |
| `fired_at` | when it fired (UTC) |
| `matched_count` | how many rows the rule's query returned |
| `detail` | a **sample of the matched rows** — the rule's actual output |
| `id` | a unique alert id (handy to ignore duplicates) |
| `rule_tags` | the rule's tags — only if the rule has any |
| `observed_value` | the measured value — only for **threshold** rules |
| `key` | the group the alert fired on — only for **group-by** rules |

The last three only appear when the rule produced them. They reach the
richer destinations too: Splunk events, Elasticsearch documents, syslog
JSON, PagerDuty `custom_details`, Opsgenie `details` (Opsgenie also gets the
tags as native **tags**), and the CEF/LEEF SIEM formats.

### The matched rows (`detail`)

This is the part that tells you **what** tripped the rule, not just that it
tripped. `detail` is the first **10 rows** the rule's query returned, as a
list of value-lists in the order of the query's `KEEP`:

```json
[["10.0.0.50", 5432], ["10.0.0.51", 5432]]
```

A few things to know:

- It's **capped at 10 rows** — `matched_count` tells you the real total.
- The values have **no column names** (they're positional). If the columns
  aren't obvious, put a hint in the rule name or your message template.
- It's a snapshot taken **the moment the alert fired** — it always reflects
  exactly what the rule saw.
- A **heartbeat** rule fires when its query returns *nothing*, so its
  `detail` is empty.

To surface these rows in a notification, reference `{{.Detail}}` in your
webhook body or Gotify message template (the Gotify default leaves them
out).

---

## TLS (internal / self-signed endpoints)

Many outputs talk to a server over TLS — an **HTTPS** webhook, Gotify,
Mattermost, Splunk or Elasticsearch endpoint, a syslog **TCP + TLS** feed, or
SMTP over **STARTTLS** / **Implicit TLS**. If that server presents a
certificate obserae doesn't trust by default (a private/internal CA, or a
self-signed certificate), the form offers two options at the bottom — they
apply to **whichever** of those encrypted transports the output uses:

- **Custom CA certificate** — paste the PEM of your CA (or the
  self-signed cert). obserae will trust it in addition to the public
  roots and verify the connection normally. **Recommended.**
- **Skip TLS certificate verification (insecure)** — turns off
  certificate checking entirely. A **warning** appears as soon as you tick
  it: with verification off, obserae **cannot confirm** it's really
  talking to your server, and the connection could be intercepted. Use it
  only for a trusted lab/internal endpoint while getting started, and
  switch to a custom CA for anything that matters.

(Outputs with a fixed public endpoint — Slack, Telegram, PagerDuty, Opsgenie —
always use the provider's certificate, so these options don't apply to them.)

## Choose which alerts go where (routing)

Each output receives an alert only when **all** of these match:

- **Minimum severity** — e.g. set `high` so an output only gets
  high/critical alerts.
- **Rule names** *(optional)* — a comma-separated allow-list; leave empty
  for any rule.
- **Rule tags** *(optional)* — comma-separated; the alert's rule must
  carry at least one of these tags. Leave empty for any tag.

So you can send everything to an audit webhook (`min severity = info`),
while only paging the on-call Gotify on `high`+ alerts tagged `prod`.

---

## Test it

Open an output and click **Send test**. obserae delivers a sample alert
straight away and tells you whether it succeeded — or shows the exact
error (bad URL, auth rejected, server down). Use it to confirm everything
is wired before a real alert depends on it.

---

## Watch deliveries

The output's drawer shows **Recent deliveries** with a status for each:

- **sent** — delivered successfully.
- **failed** — the last attempt errored; obserae will retry automatically
  with increasing back-off.
- **dead** — given up (too many failures, or a permanent error like a
  `404`/auth failure that won't fix itself).

Deliveries are **reliable**: every alert is queued the instant it fires
and retried until it lands, so a brief network blip or a receiver restart
never loses a notification. Retrying happens in the background and never
slows down alerting.

---

## Verifying webhooks

If you set a **signing secret**, each webhook request carries:

- `X-Obserae-Timestamp` — when it was sent (Unix seconds).
- `X-Obserae-Delivery` — a unique id you can use to ignore duplicates.
- `X-Obserae-Signature` — `sha256=<hex>`, an HMAC-SHA256 of
  `"<timestamp>.<rawBody>"` using your secret.

Your receiver verifies a request by recomputing that HMAC over the
timestamp and the exact raw body and comparing it to the header. Because
the timestamp is signed, an old captured request can't be replayed.

---

## A note on secrets

Every credential you enter — a webhook signing secret, a Gotify /
Slack / Mattermost / Telegram bot token, a Splunk HEC token, an
Elasticsearch password or API key, a PagerDuty routing key, an Opsgenie API
key, an SMTP password — is stored by obserae and used only to sign or
authenticate its outgoing requests. They are **never shown again** in the
interface or the API (you'll see "secret is set"), and never appear in logs.
When editing an output, leave the secret field blank to keep the existing
one, or type a new value to replace it. (Syslog has no credential to store.)

---

See also: [Alerting](alerting.md) · [NFQL](nfql.md) ·
[Configuration](configuration.md).

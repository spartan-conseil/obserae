# Outputs

Outputs send your alerts **out** of obserae — to a chat channel, an
on-call app, a ticketing system or a SIEM. Where [Alerting](alerting.md)
decides *when* an alert fires, an output decides *where it goes*.

obserae v1 ships two kinds of output:

- **Webhook** — an HTTP `POST` (or `PUT`/`PATCH`) to any URL. Works with
  Slack/Teams/Discord incoming webhooks, automation platforms, or your
  own endpoint.
- **Gotify** — a push to a [Gotify](https://gotify.net/) server.

Open the **Outputs** page from the sidebar (after **Detection**).

---

## Create an output

Click **+ New output** and fill in the form.

**For a webhook:**

- **URL** — where to POST the alert.
- **Method** — `POST` (default), `PUT` or `PATCH`.
- **Custom headers** — one `Key: Value` per line (e.g.
  `Authorization: Bearer …`).
- **Body template** — leave empty to send obserae's default JSON
  (`id`, `rule_name`, `severity`, `fired_at`, `matched_count`, `detail`),
  or write your own using `{{.RuleName}}`, `{{.Severity}}`,
  `{{.FiredAt}}`, `{{.MatchedCount}}`, `{{.Detail}}`, `{{.ID}}`.
- **Signing secret** — optional. When set, every request is signed so the
  receiver can verify it really came from obserae (see *Verifying
  webhooks* below).

**For Gotify:**

- **Server URL** — your Gotify base URL (e.g. `https://gotify.example.com`).
- **App token** — the Gotify application token.
- **Priority** — leave at `0` to derive it from the alert severity, or pin
  a fixed `0–10`.
- **Title / Message templates** — optional; sensible defaults otherwise.

Then set the **routing** (below) and tick **Enabled**.

---

## TLS (internal / self-signed endpoints)

If your destination is served over HTTPS with a certificate obserae
doesn't trust by default (a private/internal CA, or a self-signed
certificate), the form offers two options:

- **Custom CA certificate** — paste the PEM of your CA (or the
  self-signed cert). obserae will trust it in addition to the public
  roots and verify the connection normally. **Recommended.**
- **Skip TLS certificate verification (insecure)** — turns off
  certificate checking entirely. A **warning** appears as soon as you tick
  it: with verification off, obserae **cannot confirm** it's really
  talking to your server, and the connection could be intercepted. Use it
  only for a trusted lab/internal endpoint while getting started, and
  switch to a custom CA for anything that matters.

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

Webhook secrets and Gotify tokens are stored by obserae and used only to
sign/authenticate outgoing requests. They are **never shown again** in
the interface or the API (you'll see "secret is set"), and never appear
in logs. When editing an output, leave the secret field blank to keep the
existing one, or type a new value to replace it.

---

See also: [Alerting](alerting.md) · [NFQL](nfql.md) ·
[Configuration](configuration.md).

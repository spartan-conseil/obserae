# Alerting

obserae turns the **NFQL** query language into a simple, powerful
alerting system. You write a query that describes something you want to
watch for, save it, and wrap an **alert rule** around it. obserae runs
your rules in the background and raises an **alert** whenever one
matches.

The idea in one sentence: **the query does the detecting, the rule
decides when that counts as an alert.**

Three pages work together:

- **Investigation** — write, test and **save** your NFQL queries.
- **Rules** — build alert rules on top of saved queries.
- **Detection** — see, triage and clear the alerts that fired.

---

## 1. Write and save a query

Open **Investigation**, write a query, and press **Run** to check it
returns what you expect. For example, "SSH sessions reaching one of my
servers":

```
FROM sessions
| LAST 300
| WHERE server_port == 22
| KEEP ip_a, ip_b
```

When you're happy, use **Saved ▾ → Save as…** to store it with a name
and (optionally) some tags. Saved queries keep a creation/modification
date and a revision number that ticks up every time you change them — so
you always know which version is live.

> **Tip — the `LAST` window is required.** An alert query must include a
> `LAST <seconds>` clause (here `LAST 300` = the last 5 minutes).
> Without it, the rule would re-scan your whole history on every run.
> Pick a window at least as long as how often the rule will run.

---

## 2. Build a rule

Open **Rules → + New rule** and fill the form. The field names below
match the form exactly:

1. **Name** and **Description**.
2. **Saved query** — the query the rule runs. Start typing to search
   your saved queries: a plain word matches the name, description, tags
   or query text, and you can target a field with `name:…` or `tag:…`
   (e.g. `tag:critical`). Each result shows the query's name, revision,
   tags and a preview of its NFQL — click one to pick it. The query must
   contain a `LAST <window>` clause and no `?` parameters; the form
   rejects it otherwise.
3. **Condition** — how it should fire:

   | Condition (as shown in the dropdown) | Fires when… | Good for |
   |--------------------------------------|-------------|----------|
   | **Presence** — fire when the query returns any row | the query returns at least one row | "this happened at all" — SSH from the internet, a connection to a forbidden service |
   | **Threshold** — fire when the row count crosses a bound | the **row count** satisfies the operator + value you set (the field is labelled *Value (row count)*) | volume-based detections — port scans, brute-force, data exfiltration |
   | **First seen** — fire on a never-seen-before result | a result row that has never appeared before shows up | spotting change — a new source→destination pair, a new external IP |
   | **Heartbeat** — fire when a primed query goes silent | the query returns **nothing** after it has previously returned data | catching outages — "my log collector went quiet" |

   For **Threshold** you also pick an **Operator** (`>`, `<`, `>=`,
   `<=`, `==`) and a **Value (row count)**. For **First seen** you can
   set an optional **Seen retention** in seconds.
4. **Severity** — info, low, medium, high, or critical.
5. **Cadence** — how often the rule runs. The dropdown offers `10s`,
   `30s`, `1m`, `5m`, `15m`, `1h`. Run cheap, time-sensitive rules
   often; run heavy rules rarely.
6. **Cooldown** — after a rule fires, it stays quiet for this long so
   you aren't flooded by the same alert. Choose from `None`, `5m`, `15m`,
   `30m`, `1h`, `6h`, `24h` (`None` disables the throttle — useful for
   *First seen* / *Heartbeat*, where duplicates are already prevented).
7. **Remediation** (optional) — a note your on-call analyst sees when
   the alert fires.
8. **Tags** and the **Enabled** checkbox.

That's it. obserae starts running the rule on its cadence.

> **Two conditions that "learn" first.** *First seen* and *Heartbeat*
> need to know the normal state before they can fire. On a rule's first
> runs they quietly learn (they won't alert), then start firing on
> what's genuinely new or newly missing. This is automatic — there's
> nothing to configure.

---

## 3. Read and triage alerts

Open **Detection** to see everything that fired. Each alert shows when
it happened, its **severity**, the rule that raised it, and how many
rows matched. Click an alert to see a **sample of the matching rows**
and jump to its rule.

You can:

- **Filter** by severity, status, rule, or time window.
- **Advance an alert's status** with the **Acknowledge** then **Close**
  button (the status walks `new` → `ack` → `closed`).
- **Delete** alerts individually or in bulk.

The Detection page updates live — a new alert appears without a reload.

---

## Keeping an eye on your rules

Every rule keeps a short history. Open a rule's panel on the **Rules**
page to see its **recent runs**: when each ran, whether it fired, how
many rows it saw, and **how long the query took**. The Rules list also
shows a **Last exec** column you can sort on — a quick way to find a
"heavy" rule whose query is slow and should be tightened or run less
often. The **Cockpit** summarises the whole picture: how many rules are
active, how many alerts fired in the last hour, and whether any rules
are running slowly.

obserae is careful to run alerting **without slowing down traffic
collection**: queries run on a separate read path, heavy rules can be
spaced out, and the system warns you in the logs if alerting ever starts
to take up too much room.

---

## Sharing rules between environments

A rule needs its query to work — the two travel together. They live as
the **`alerting:`** block of the single configuration file you export and
import from the **Config I/O** page (`⇄` in the sidebar):

- **Export configuration** downloads one file holding everything obserae
  is configured with — including all your saved queries and rules — to
  keep in version control or hand to another obserae.
- **Import file…** loads such a file. If it carries an `alerting:`
  section, **that replaces all your current saved queries and rules**
  with the file's contents (obserae asks you to confirm first, and a
  section left out of the file is kept untouched). Your past alerts are
  kept — only the queries and rules are swapped. If the file has a
  mistake, nothing is changed and you get a clear error.
- **Validate file…** checks a file is correct without importing it.

---

## Good to know

- **Editing a saved query updates every rule that uses it** — on the
  next run, automatically. The rule always uses the latest version.
- **You can't delete a query a rule still uses.** obserae tells you
  which rules depend on it; detach or delete those first.
- **If a query stops working** (for example you renamed something in the
  cartography it referred to), its rule is *quarantined*: it's skipped
  with the error shown on the Rules page, and the rest keep running.
  Fix the query and the rule heals itself on the next run.

See also: [NFQL](nfql.md) for the query language, and
[Detection rules](rules.md) for the Flow-Matrix connectivity rules
(a different, complementary feature).

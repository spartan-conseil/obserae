# Security Policy

obserae is a network-security product, so we take vulnerabilities in it
seriously. Thank you for helping keep obserae and its users safe.

## Reporting a vulnerability

**Please report security issues privately. Do not open a public GitHub issue,
pull request or discussion for a vulnerability.**

Email **<security@spartan-conseil.fr>** and include as much of the following as
you can:

- a description of the issue and its **impact**;
- the **affected version** (GUI footer, or `obserae-cli --socket <path> status`)
  and how it was deployed (Docker image / release tarball, OS and CPU);
- **steps to reproduce**, or a proof-of-concept;
- any logs or configuration relevant to the finding.

If you want to encrypt your report, send a short plain-text message first and
we'll arrange a key.

## What to expect

obserae is built by a small team, so these are good-faith targets, not a
contractual SLA:

- **Acknowledgement** of your report within **5 business days**.
- An initial **assessment** (severity, affected versions, whether we can
  reproduce) soon after, then **status updates** as we work on a fix.
- **Coordinated disclosure**: we agree a disclosure date with you and credit you,
  with your permission, once a fix is available. We ask for a reasonable embargo —
  typically up to **90 days** — and move faster for issues under active
  exploitation.

There is no paid bug-bounty programme; we are nonetheless grateful for responsible
reports and will gladly acknowledge you publicly if you wish.

## Supported versions

obserae is in **beta** (pre-1.0). Security fixes land on the **latest release
only**, and ship as a new release rather than a patch to an older one — please
reproduce on the most recent version before reporting.

## Safe harbour

We consider security research carried out in **good faith** and in line with this
policy to be authorised, and we will not pursue or support legal action against
you for it. To the extent this policy permits actions the EULA would otherwise
restrict (art. 5), this policy is your written authorisation from Spartan Conseil
for that good-faith research. In return, please:

- test **only against your own obserae deployment** — never another user's, and
  never Spartan Conseil's own infrastructure;
- **do not** run volumetric denial-of-service, spam, or social-engineering
  attacks;
- **do not** access, modify or exfiltrate data that isn't yours, and stop as soon
  as a vulnerability is demonstrated;
- give us reasonable time to fix the issue before disclosing it publicly.

## Out of scope

Unless you can demonstrate real impact, the following are usually not treated as
vulnerabilities on their own:

- volumetric or resource-exhaustion denial-of-service;
- findings from automated scanners with no working proof-of-concept;
- missing hardening headers or "best practices" without a demonstrated exploit;
- issues that require an already-compromised host or physical access;
- the security of a deployment's own reverse proxy, TLS or OS configuration —
  that is the operator's responsibility (see [Operations](https://obserae.com/docs/operations)
  and [Installation](https://obserae.com/docs/installation)).

## Source access for review

Qualified reviewers can request source access for security review under NDA — see
[Licensing & transparency](LICENSING.md). For non-security questions and bug
reports, see [SUPPORT.md](SUPPORT.md).

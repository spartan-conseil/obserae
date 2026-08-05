# Support

obserae is in **beta** and running in production at early-adopter sites, and
feedback genuinely shapes it — questions, bug reports and suggestions are all
welcome. This page explains where to get help and what to expect.

## Before you reach out

A quick check often answers it faster than a round-trip:

- **The documentation** — the full guides live at
  [obserae.com](https://obserae.com): start with Installation, then Configuring
  Exporters, Operations & troubleshooting, and the Configuration reference.
- **Common gotchas** — the login loop over plain HTTP and the NetFlow v9 /
  IPFIX template warm-up (flows visible in `tcpdump` but the counter stays at 0)
  are documented in Installation and Configuring Exporters.
- **Support** — if the documentation does not answer the question, write to
  <support@spartan-conseil.fr>.

## Reporting a bug or requesting a feature

Email <support@spartan-conseil.fr>.

To get a useful answer quickly, please include:

- the **version** (GUI footer, or `obserae-cli --socket <path> status`);
- **how you installed it** (Docker image or release tarball) and your **OS / CPU**
  (`amd64` or `arm64`);
- a **minimal config** snippet and the **daemon logs** around the problem;
- **steps to reproduce**, and what you expected to happen instead.

obserae does not accept code contributions (see [CONTRIBUTING](CONTRIBUTING.md)),
but issues — bugs and ideas alike — are exactly what helps.

## Reporting a security issue

Please **do not** open a public issue for a vulnerability. Email
<security@spartan-conseil.fr> with `[SECURITY]` in the subject and give us a
reasonable window to fix it before any public disclosure.

## What support to expect

- **Free / beta** — best-effort help by email, with no service-level
  guarantee (EULA art. 8). obserae is built by a small shop, so please be patient.
- **Commercial license** — technical support, priority fixes, SLAs and custom
  development are part of a commercial agreement. See
  [Licensing & transparency](LICENSING.md) or write to
  <licensing@spartan-conseil.fr>.

## Licensing & source access

Questions about who pays, commercial use, or source access for security review
are answered in [Licensing & transparency](LICENSING.md)
(<licensing@spartan-conseil.fr>).

<!-- Rendered from tools/community/SECURITY.md.tpl by tools/render-community.py: edit the template, not this file. -->

> **Draft: a contact address is not set yet** ([CONTACT NOT SET] below). Reports cannot be made by email until it is. This notice is removed when `tools/contacts.conf` is filled in.

# Security policy

## Reporting a vulnerability

**Do not open a public issue for a vulnerability.** Report it privately, by either of these:

1. **GitHub private vulnerability reporting:** use the "Report a vulnerability" button on the [Security tab of this repository](https://github.com/slash-builder/kit-book/security/advisories/new). Only the maintainer and you see the report.
2. **Email:** [CONTACT NOT SET], for when GitHub's form is not an option for you.

Please include:

* what you found and where (file, command or page);
* the commit of `main` you looked at (`git rev-parse HEAD`) and your operating system;
* steps to reproduce it, or a short proof of concept;
* what you think the impact is, and whether anyone else knows.

## What to expect

You get an **acknowledgement within 7 days**, from a person. Nothing else is promised: this project has one maintainer, no paid support and no fixed fix time. If the report is valid, the reply says what happens next; if it is not, it says why.

## Supported versions

This repository has no releases and is pre-1.0. **Only the latest commit of `main` is supported.** An older commit gets no fixes; update to `main`.

## Scope

In scope: the code and documentation in **this repository**: the Makefile, the scripts in `tools/`, the demo apps in `apps/` and `labs/`, and the pages of the book.

Out of scope: third-party services and software (GitHub, GitHub Pages, Cloudflare, Flutter, Rust and their packages), and the Kits themselves, which have their own repositories and their own reporting instructions. A problem in a Kit belongs in that Kit's repository. If you are not sure where something belongs, report it here, privately.

# Introduction

## What a Kit is

A **Kit** is a focused piece of SlashBuilder's platform that owns one job and says plainly what it will not do. The App Context Kit owns an app's identity, its folders for files and settings, test and scratch modes, and a presence entry other apps can read. The Venue (a resource broker) owns machine time on a shared computer. A storage Kit owns where bytes live; an identity Kit owns who is allowed to do what. Each Kit lives in its own repository with its own tests and documentation, and an app is built by composing the ones it needs.

The names *App Context Kit* and *Venue* are provisional; they may change.

## What this repository is

This repository is **the book, not a Kit.** It is the starting point for using the Kits: it holds this documentation, a set of demo apps that compose Kits, and a Makefile that prepares your computer, runs every test and builds the apps. It never appears in the Kit registry or the catalog, and nothing depends on it.

The Kits themselves are not copied in. `make setup` downloads each one, at the commit named in [`kits.lock`](../kits.lock), into a folder called `.kits/`. That keeps the Kits' own repositories as the single place their code changes, and it keeps this book honest: the demos build against exactly the versions the book describes.

## How to use this book

* **Read [Start here](10-start-here.md) first.** It takes you from an empty folder to a running app in four commands.
* **Then read the guides** in `20-guides/`. The [demo apps guide](20-guides/demo-apps.md) shows the Kits composed into real apps, with measurements of what each Kit saved. The [guide on fitting the App Context Kit to other Kits](20-guides/fitting-the-app-context-kit-to-other-kits.md) shows where its design meets its neighbours.
* **Reference pages** live in `90-reference/`: every [make target](90-reference/make-targets.md) and a [glossary](90-reference/glossary.md).
* **The Kit catalog** lives in `30-kits/`: a status card for every Kit in the registry, including the ones that are not public yet. See [Kits](30-kits/README.md). A Kit's own reference pages are pulled into the book from the Kit, so you never need its repository to read them; today that is the [App Context Kit's reference](30-kits/app-context-kit/index.md), and the others are still to come.

## What is written and what is not

| Section | State |
|---|---|
| Introduction, start here | Written |
| Demo apps guide, fitting the App Context Kit to other Kits | Written; moved here from the App Context Kit's own documentation and reworded for a wider audience |
| Make targets, glossary | Written |
| Kit catalog | Written, and generated from the registry |
| Per-Kit reference | Pulled from the Kits themselves (see [Make targets](90-reference/make-targets.md#docs-pull)). The App Context Kit's is in; no other Kit has reference pages yet |
| A demo app with a Rust core | Written: [notes_rust](../apps/notes_rust/README.md), the seventh demo app. The other six are Flutter on a Dart core |

## How much to trust it

Every number in the guides says what it was measured on. A claim that was reasoned but not tested says so. Where something is not known, the page says that instead of guessing. If you find a page that does not do this, that is a bug; see [CONTRIBUTING](../CONTRIBUTING.md).

# The Kit Book

**[Introduction](00-introduction.md)** · **[Start here](10-start-here.md)** · **[Demo apps](20-guides/demo-apps.md)** · **[Fitting the App Context Kit to other Kits](20-guides/fitting-the-app-context-kit-to-other-kits.md)** · **[Kits](30-kits/README.md)** · **[Make targets](90-reference/make-targets.md)** · **[Glossary](90-reference/glossary.md)** · **[Repository home](../README.md)**

---

Developer documentation and composed demos for every SlashBuilder Kit. A Kit is a focused piece of SlashBuilder's platform that owns one job, such as an app's identity and files, or machine time on a shared computer. This book explains the Kits, shows them working together in small apps, and gives you the commands to build and run it all.

The book is a skeleton at the moment. It says what is written and what is still to come, page by page. The Kit catalog is written: it is generated from the Kit registry and lists every Kit, public or not.

## Start here

| I want to... | Read |
|---|---|
| know what a Kit is and how this book is organised | [Introduction](00-introduction.md) |
| get everything running on my computer | [Start here](10-start-here.md) |
| see Kits composed into real apps | [Demo apps](20-guides/demo-apps.md) |
| understand how the App Context Kit meets its neighbours | [Fitting the App Context Kit to other Kits](20-guides/fitting-the-app-context-kit-to-other-kits.md) |
| look up a command | [Make targets](90-reference/make-targets.md) |
| look up a word | [Glossary](90-reference/glossary.md) |
| find the reference for one Kit | [Kits](30-kits/README.md), the catalog of every Kit with a status card each |

## Every page

### Learn
| Page | What you get |
|---|---|
| [Introduction](00-introduction.md) | What a Kit is, what this repository is and is not, how to use the book |
| [Start here](10-start-here.md) | The exact commands from an empty folder to a running app |

### Guides
| Page | What you get |
|---|---|
| [Demo apps](20-guides/demo-apps.md) | Seven apps (calculator, minesweeper, notepad, stopwatch, render queue, launcher, and notes_rust, the one with a Rust core), what each tested, how much code the App Context Kit saved, and how to run two copies and watch them find each other |
| [Fitting the App Context Kit to other Kits](20-guides/fitting-the-app-context-kit-to-other-kits.md) | What fitting the App Context Kit to the transport, messaging, storage, identity and UI Kits showed |

### Kits
| Page | What you get |
|---|---|
| [Kits](30-kits/README.md) | The generated catalog: one status card for every Kit in the registry, with its status, language, what it owns and what it will not do. Also [the status vocabulary](30-kits/status-vocabulary.md) and [what is not in the registry](30-kits/not-in-the-registry.md). The [App Context Kit's own reference](30-kits/app-context-kit/index.md) is pulled in from the Kit; no other Kit has reference pages yet |

### Reference
| Page | What you get |
|---|---|
| [Make targets](90-reference/make-targets.md) | Every target and variable of the Makefile, and the format of `kits.lock` |
| [Glossary](90-reference/glossary.md) | The words these pages use |

## Reading this book as a website

`make site` builds the book as an HTML site if [mdBook](https://rust-lang.github.io/mdBook/) is installed. On GitHub it reads fine without that. Links from the guides into `apps/` and `labs/` work on GitHub but not in the generated site, because those folders are outside the book.

## Conventions

* Page names are stable; sections are linked by their headings. `make docs` checks every relative link and heading anchor.
* Code blocks are checked against the repository where they say `copied-from=`. Where a block is illustrative, it says so.
* "Verified" means a test, a command or a measurement was run for that page. Anything else is labelled as reasoned or reported.
* Numbers come with what they were measured on (macOS debug builds, loopback, a throwaway local broker). They are not benchmarks.
* The names App Context Kit and Venue (a resource broker) are provisional.

---

[Repository home](../README.md) · [Demo apps](../apps/) · [Licence: documentation CC BY 4.0](../LICENSE-docs), [code Apache-2.0](../LICENSE)

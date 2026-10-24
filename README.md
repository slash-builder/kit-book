# The Kit Book

Developer documentation and composed demos for every SlashBuilder Kit.

This repository is the place to start when you want to use SlashBuilder's Kits. It holds three things:

* **A book** (in [`book/`](book/README.md)): narrative guides and reference pages for the Kits.
* **Demo apps** (in [`apps/`](apps/)): six small Flutter desktop apps that compose Kits, each chosen because it asks something different of them.
* **A Makefile** that sets up the build environment, runs the tests and builds the apps, so you do not have to learn each Kit's toolchain first.

> **Status: being set up.** Some of the Kits the demos use are not public yet, and the names *Application Kit* and *Venue* (a resource broker) are provisional. The book is a skeleton: the introduction, a quick start, two guides, a reference and the Kit catalog (a status card for every Kit in the registry, including those that are not public) are written; the Application Kit's own reference pages are pulled in from the Kit, and no other Kit has reference pages yet. This repository is the book, not a Kit.

## Quick start

You need a computer with `make`, [Flutter](https://docs.flutter.dev/get-started/install) and [Rust](https://www.rust-lang.org/tools/install). You do not need git to fetch the Kits.

```sh
make doctor     # check your tools; it tells you what to install and installs nothing
make setup      # fetch the Kits and each project's packages (make setup KITS=all while some Kits are private)
make test-fast  # run every test
make run APP=calculator
```

`make` on its own lists every target. The same steps with explanations are in [Start here](book/10-start-here.md).

## What is in here

| Folder | What it is |
|---|---|
| [`book/`](book/README.md) | The book. Open [`book/README.md`](book/README.md) for the table of contents |
| [`apps/`](apps/) | Six demo apps: [calculator](apps/calculator/README.md), [minesweeper](apps/minesweeper/README.md), [notepad](apps/notepad/README.md), [stopwatch](apps/stopwatch/README.md), [render-queue](apps/render-queue/README.md), [launcher](apps/launcher/README.md) |
| [`labs/interface_candidates`](labs/interface_candidates/README.md) | Components proposed for the shared UI Kit, built from what the demo apps duplicate. Plain Material |
| [`tools/`](tools/) | The scripts behind the Makefile (POSIX `sh` and Python 3 only; the maintainer-only catalog generator also needs PyYAML) |
| [`kits.lock`](kits.lock) | Which Kits the apps use, each pinned to one commit. `make setup` downloads them into `.kits/` |

The Kits are not copied into this repository and are not git submodules. A script downloads each one at its pinned commit as a plain archive, so nothing here asks you to run a recursive git command.

## The demo apps

A calculator, minesweeper, a notepad, a stopwatch, a render queue and a launcher. The calculator is the floor: it barely needs the Application Kit and says so. The notepad is the ceiling: it syncs notes between copies of itself and resolves conflicts. [The demo apps guide](book/20-guides/demo-apps.md) has the measurements and the walkthroughs.

What the demos do not cover is said plainly there: **no demo app has a Rust core yet.** All six are Flutter on a Dart core, so the intended shape (a Flutter interface over a Rust core that uses several Kits) has not been exercised end to end.

## About the book

The book is meant to be read in order the first time and used as a reference after that. Narrative guides come first, then one section per Kit, then reference pages. In the spirit of the Be Book, the reference that documented every Kit of an operating system in one place. The [catalog of Kits](book/30-kits/README.md) lists every Kit in the registry, including those that are not public yet, as honest status cards.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Before you send a change, run `make docs`, `make check-public` and `make test-fast`.

## Licence

* **Documentation** is licensed under [Creative Commons Attribution 4.0 (CC BY 4.0)](LICENSE-docs). That covers `book/`, this README, [CONTRIBUTING.md](CONTRIBUTING.md) and every `README.md` inside `apps/` and `labs/`.
* **Code and tooling** is licensed under the [Apache License 2.0](LICENSE). That covers the Makefile, `tools/`, `apps/` and `labs/` (including the sample code in them).
* `kits.lock` is configuration and falls under Apache-2.0. The Kits that `make setup` downloads into `.kits/` keep their own licences.

Attribution: SlashBuilder / Douglas Lockamy.

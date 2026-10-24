# Make targets

Everything is driven from the `Makefile` at the repository root. It works with the system `make` on macOS (3.81) and Linux and uses nothing newer. `make` on its own runs `make help`, which lists every target with one line. The Makefile follows the convention of the Kit repositories (`help`, `all`, `build`, `lint`, `test`, `fmt`) so the CI job and people use the same names.

The scripts behind the targets are in [`tools/`](../../tools/). They are plain POSIX `sh` (and Python 3 for the link checker), so they run on the `/bin/sh` and `/bin/bash 3.2` that ship with macOS. The one exception is the catalog generator behind `docs-catalog`, a maintainer tool that also needs PyYAML; nothing a reader runs depends on it. `docs-pull` is also a maintainer tool, but it is Python 3 standard library only.

## Variables

| Variable | Used by | Meaning |
|---|---|---|
| `KITS` | `setup`, `fetch` | `public` (default) fetches only public Kits. `all` also fetches private Kits and needs a GitHub login |
| `SETUP_INSTALL` | `setup` | `1` prints the install commands for missing required tools and runs them after a y/N question. Default: never installs |
| `APP` | `app`, `run` | An app folder name under `apps/`: `calculator`, `minesweeper`, `notepad`, `stopwatch`, `render-queue`, `launcher` |
| `KIT` | `lock` | A Kit name from `kits.lock`. Empty means every Kit |
| `LOCK_YES` | `lock` | `1` skips the y/N question before `kits.lock` is rewritten (the difference is still printed) |
| `GITHUB_TOKEN` | `fetch`, `lock` | A token that can read private Kits, used when the GitHub CLI is not logged in |
| `VENUE_TOKEN_FILE` | `test`, `test-integration` | A resource-broker token file. When set, the render-queue tests that need a running broker run for real instead of skipping |
| `CHECK_PUBLIC_STRICT` | `check-public` | `1` also fails while `kits.lock` lists private Kits |
| `REGISTRY` | `docs-catalog` | Maintainers only: the path of the Kit registry file (`kits.yaml`). If empty, `KITS_REGISTRY` from the environment is used. With neither, `docs-catalog` stops with a message |
| `KITS_REGISTRY` | `docs-catalog` | The same path, from the environment, for people who regenerate often |
| `REGISTRY_COMMIT` | `docs-catalog` | The commit of the registry the catalog is generated from; the catalog index prints it as "Generated from registry commit abc1234" |
| `OFFLINE` | `docs-catalog` | `1` does not ask GitHub who is public and reuses `tools/kit-visibility.tsv` as it is |
| `PYTHON` | `docs-catalog`, `test-tools`, `test-fast` | The Python 3 to use for the catalog generator and the tool tests (default `python3`). For `docs-catalog` it must have PyYAML; `docs-pull` always uses plain `python3` |
| `NO_COLOR` | all | Turns off colours in the output |
| `KITS_LOCK` | the scripts in `tools/` | Read a different lock file (used for testing the fetch script) |

## Targets

### `help`

The default. Prints every target with a one-line description.

### `all`

What CI runs: `lint`, then `test-fast`, then `build`.

### `doctor`

Checks the toolchain and prints a table: tool, whether it is required, status, the version found and the version wanted. For each missing or too-old tool it prints the install command for your system (Homebrew on macOS, `apt` on Debian and Ubuntu). It installs **nothing** and exits non-zero only when a **required** tool is missing or too old.

* **Required:** Flutter and Dart (the minimum Dart is read from the apps' `pubspec.yaml` files), Rust and Cargo (the minimum is read from the Rust crate), `curl`, `tar`, Python 3, and on macOS the Xcode command line tools.
* **For apps:** needed only to build and run the demo apps. On macOS, the full Xcode app. On Linux, `clang`, `cmake`, `ninja`, `pkg-config` and the GTK 3 development files. `make apps` requires them; `make test-fast` does not.
* **Optional:** Docker (for the Linux container checks), `redis-server`, `protoc`, `flutter_rust_bridge_codegen`, the GitHub CLI (`gh`, for private Kits) and `mdbook` (for `make site`).

### `setup`

Runs `doctor`, then `fetch`, then `flutter pub get` or `dart pub get` for every app and package, then `cargo fetch` for each Rust crate. Safe to run again. `KITS=all` also fetches private Kits. `SETUP_INSTALL=1` offers to run the install commands for missing required tools; the default never installs.

### `fetch`

Reads [`kits.lock`](#kitslock) and, for each Kit, downloads the archive at the pinned commit into `.kits/<name>/`. Public Kits come from a plain `curl` download. Private Kits come from the GitHub CLI (`gh api`) when it is logged in, else from `GITHUB_TOKEN`; with neither, the Kit is skipped with a one-line explanation. After unpacking it writes `.kits/<name>/.fetched` containing the commit, and skips the Kit next time when that matches. It checks that the archive really is the commit asked for. No git and no submodules are involved. One line per Kit: `fetched`, `up to date`, or `skipped (why)`.

### `lock`

Shows how the pins would move: for each Kit it asks GitHub for the newest commit of the default branch and prints `old -> new` with a compare link. It rewrites `kits.lock` only after you answer `y`. `make lock KIT=application-kit` does one Kit. After it, run `make setup` and `make test-fast`.

### `test`

Runs every fetched Kit's own test suite, then `labs/interface_candidates`, then every demo app, then the integration suites that can run on this computer. A Kit with a `Makefile` is tested with its own `make test-fast` (or `make test`); a Kit without one is tested with its native commands (`dart test`, `flutter test`, `cargo test`). Prints a table with each suite's passed, failed and skipped counts and its seconds; logs are in `build/test-logs/`. Exits non-zero when any suite that ran has a failure.

### `test-fast`

The same as `test` without anything that needs Docker, Redis or a running daemon. This is the everyday command. It also runs the unit tests of the maintainer tools (see [`test-tools`](#test-tools)) when PyYAML is installed, and skips them with a message when it is not.

### `test-integration`

Only the suites that need Docker, Redis or a daemon. Each one skips with a clear message when its tool is absent; skipping is never a failure.

| Suite | Needs | What it does |
|---|---|---|
| Linux containers | The Docker daemon running | Runs a Kit's Dart and Rust cores in throwaway Linux containers, if the Kit ships a script for it (the Application Kit does) |
| Resource-broker daemon tests | `VENUE_TOKEN_FILE` set to a token for a running broker | Runs the render-queue tests that otherwise skip themselves |
| Message-hub probes | Redis | These run in a private repository; nothing here runs yet |

### `apps`

Builds every demo app in debug mode for this computer (macOS or Linux desktop). Needs the "for apps" tools from `doctor` and a fetched Application Kit.

### `app`

Builds one app: `make app APP=notepad`.

### `run`

Runs one app on this computer: `make run APP=notepad`.

### `build`

An alias for `apps`.

### `lint`

Runs `flutter analyze` over `labs/interface_candidates` and every app, then `docs` and `check-public`.

### `fmt`

Runs `dart format` over `apps/` and `labs/`.

### `docs`

Checks every relative link and heading anchor in `book/` and in the README files (`tools/check-links.py`), using GitHub's heading slugs. A code fence whose opening line says `copied-from=<path>` is also checked against that file. It also checks that every Makefile target is described on this page. It writes nothing.

### `docs-catalog`

**For maintainers; readers never need it.** Regenerates the Kit catalog in `book/30-kits/` from the Kit registry, then runs `docs` and `check-public` on the result. The registry is in a private repository, so the generated pages are committed here and `make docs` never asks for it.

```sh
python3 -m pip install pyyaml            # once; only this tool needs PyYAML
gh auth login                            # once; the tool asks GitHub which repositories are public
make docs-catalog REGISTRY=/path/to/kits.yaml REGISTRY_COMMIT=abc1234
make docs-catalog REGISTRY=/path/to/kits.yaml OFFLINE=1     # no GitHub calls: reuse tools/kit-visibility.tsv
```

With neither `REGISTRY` nor `KITS_REGISTRY` set it stops and says so. It runs `tools/gen-catalog.py`, which writes:

* one status card per Kit in the registry (`book/30-kits/<name>.md`), for **every** Kit: public, private, banked and archived; this repository is the book, not a Kit, and is never listed;
* the catalog index (`book/30-kits/README.md`), the [status vocabulary](../30-kits/status-vocabulary.md) and the page for [things that are not in the registry](../30-kits/not-in-the-registry.md);
* the block of `book/SUMMARY.md` between `<!-- catalog:start -->` and `<!-- catalog:end -->` (the markers are added if missing; nothing else in that file is touched);
* `tools/kit-visibility.tsv`: for each Kit (by name), `public`, `private`, `missing` (the repository does not exist) or `unknown`, whether a public repository has a README or `docs/`, and the day that was checked. It never records where a Kit lives: no repository name and no organisation, so it is safe in a public repository. A repository link appears on a card only for `public`, and the repository is read from the registry each time.

Running it twice gives identical files: nothing in the output carries a time. Prose from the registry passes through a sanitiser that drops, rather than rewords, any sentence or parenthetical that names people, roles, agents, tickets, hostnames, local paths, notes-vault paths, Jira or dates, and `check-public` scans the result again. A card that comes out thin is thin because the registry entry behind it is.

### `docs-pull`

**For maintainers; readers never need it.** Pulls each Kit's own reference documentation out of the fetched Kit (`.kits/<name>/`) into the book, then runs `docs` and `check-public` on the result. The Kits keep their documentation with their code, so it versions with the code; the book copies it in at the commit `kits.lock` pins, and the copies are **committed**, so a reader needs neither `make setup` nor access to a private Kit's repository to read them. `make docs` never needs `.kits/`.

```sh
make setup KITS=all     # once, and after every pin move: the Kit must be fetched at the pinned commit
make docs-pull          # then commit book/ (the pulled pages and the docs-pull block of SUMMARY.md)
```

It runs `tools/pull-docs.py` (Python 3 standard library only), which reads `kits.lock` and `tools/docs-pull.conf`. For each Kit with a section in the configuration, the configuration says where the pages land, which source files are pulled, their order in the table of contents, and whether the Kit is public (`auto` reads the visibility column of `kits.lock`). Today only the Application Kit is pulled; because it is not in the registry its pages land in `book/30-kits/application-kit/`. A Kit in the registry lands in `book/30-kits/<slug>/reference/`, and its catalog card then lists the pages.

What it writes, and nothing else:

* `index.md`: the Kit's `docs/README.md`, followed by a generated table of every pulled page (title from the page's first heading, one line from its first paragraph);
* one page per pulled source file, named in lower case with `docs/` dropped (`docs/GETTING-STARTED.md` becomes `getting-started.md`, a folder's `README.md` is named after the folder), and any images those pages use under `assets/`;
* the block of `book/SUMMARY.md` between `<!-- docs-pull:start -->` and `<!-- docs-pull:end -->`, which nests the pages under one entry per Kit. It sits in its own part, "Kit reference", after the catalog (the part and the markers are added before "Reference" if missing). It is not inside the catalog's list because mdBook drops the first of two lists in one item when an HTML comment separates them, which would delete the catalog from the contents.

Every pulled page starts with a banner comment and carries the visible line "Reference page pulled from `<kit>` at commit `<sha7>`. Edit it in the Kit, not here." Do not edit a pulled page: the next pull overwrites it, and a content fix belongs in the Kit. The tool changes the Kit's text only by rewriting links:

| A link in a Kit page that points to... | becomes |
|---|---|
| a web address, a mail address, or a heading on the same page | itself, unchanged |
| a pulled page, or a folder whose `README.md` is pulled, or the Kit's `docs/README.md` | a relative link to the pulled copy, with its `#anchor` kept (the headings are not changed, so the anchors still exist) |
| anything else in the Kit (code, other folders), when the Kit is **private** | plain text: the link text stays, the link goes |
| anything else in the Kit, when the Kit is **public** | a GitHub address at the pinned commit (`blob` for a file, `tree` for a folder), with any `#anchor` or `#L10` kept |
| a place outside the Kit, or a file the Kit does not have | plain text, and a warning naming the page, so it can be fixed in the Kit |
| an `#anchor` that is not a heading of the page it names | the link to the page without the anchor, and a warning |
| an image that exists in the Kit | a copy under `assets/`, linked there |
| an image that does not exist | dropped, with the visible note "image not included" |

Code blocks and code spans are never touched. Running it twice gives identical files: nothing in the output carries a time.

It **refuses to run** if `.kits/<name>/.fetched` is not exactly the commit `kits.lock` pins (or the Kit is not fetched at all), so the book never mixes versions. It says so, writes nothing, and prints the fix: `make fetch` (with `KITS=all` for a private Kit). It exits with status 2 on a refusal and on a configuration error.

### `docs-pull-check`

**For maintainers.** Pulls in memory exactly as `docs-pull` does and writes nothing; it fails (status 1) and prints each file that differs, is missing, or is stale, with the first changed lines, if the committed pages are not what a fresh pull would give. Use it to see that nobody edited a pulled page by hand and that the pages were re-pulled after a pin moved. A Kit that is not in `.kits/` is skipped with a message (and the `SUMMARY.md` block is then not judged), so it is safe to run anywhere. A Kit fetched at a different commit than the pin is a refusal, as for `docs-pull`.

### `test-tools`

**For maintainers.** Runs the unit tests of the tools in `tools/`:

* the catalog generator, `tools/tests/test_gen_catalog.py`: sanitising, idempotence, the public/private link rule, the missing-repository note, status grouping, the rewrite of the `SUMMARY.md` block and the listing of pulled reference pages on the cards. They need PyYAML and skip themselves with a message when it is missing;
* the reference-docs puller, `tools/tests/test_pull_docs.py`: each class of link rewrite, the banner, anchors, idempotence, the pin refusal and `--check`. They need nothing beyond Python 3.

Plain `python3 -m unittest` from the repository root runs the same tests.

### `site`

Builds the book as an HTML website with [mdBook](https://rust-lang.github.io/mdBook/) into `build/site/`. If mdBook is not installed it prints how to install it and exits 0. Links from the guides into `apps/` and `labs/` do not work in the generated site because those folders are outside the book; they do on GitHub.

### `check-public`

Scans every file in the tree except `.kits/` and build output for anything that must not be public: internal hostnames, ticket ids, local paths that contain a user name (except the invented user name `ada` that the Kits' reference pages use in examples), notes-vault paths, references to agent instruction files, repository URLs that are not public Kits in `kits.lock` or on the card of a Kit that `tools/kit-visibility.tsv` marks public, people named in credits or licence text other than the author, and secret patterns. The generator `tools/gen-catalog.py` and its tests are not scanned, because they spell the patterns out; what they generate, including `tools/kit-visibility.tsv`, is. It prints `file:line` for every hit and exits non-zero on any. While `kits.lock` lists private Kits it also prints a note that each must become public (or stop being needed) before this repository is made public.

### `clean`

Removes build output: `build/`, each app's and lab's `build/` and `.dart_tool/`, and Rust `target/` folders inside `.kits/`. Keeps the fetched Kits.

### `clean-all`

`clean`, and also deletes `.kits/`. Run `make setup` to fetch again.

## `kits.lock`

One line per Kit, five fields separated by spaces; lines starting with `#` are comments.

```text
name  repo-url  commit  visibility  role
```

| Field | Meaning |
|---|---|
| `name` | The folder it is fetched into: `.kits/<name>/` |
| `repo-url` | `https://github.com/<org>/<repo>` |
| `commit` | The full 40-character commit id. A branch name is not accepted, so a pin never moves by itself |
| `visibility` | `public` (plain download, no account) or `private` (needs a GitHub login and `KITS=all`) |
| `role` | `core` (documented here, tests run by `make test`), `app-dep` (another Kit needs it to build; fetched, not tested) or `reference` (documented here, not needed to build the apps) |

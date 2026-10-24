# Make targets

Everything is driven from the `Makefile` at the repository root. It works with the system `make` on macOS (3.81) and Linux and uses nothing newer. `make` on its own runs `make help`, which lists every target with one line. The Makefile follows the convention of the Kit repositories (`help`, `all`, `build`, `lint`, `test`, `fmt`) so the CI job and people use the same names.

The scripts behind the targets are in [`tools/`](../../tools/). They are plain POSIX `sh` (and Python 3 for the link checker and the website tools), so they run on the `/bin/sh` and `/bin/bash 3.2` that ship with macOS. The one exception is the catalog generator behind `docs-catalog`, a maintainer tool that also needs PyYAML; nothing a reader runs depends on it. `docs-pull` is also a maintainer tool, but it is Python 3 standard library only.

## Variables

| Variable | Used by | Meaning |
|---|---|---|
| `KITS` | `setup`, `fetch` | `public` (default) fetches only public Kits. `all` also fetches private Kits and needs a GitHub login |
| `SETUP_INSTALL` | `setup` | `1` prints the install commands for missing required tools and runs them after a y/N question. Default: never installs |
| `APP` | `app`, `run` | An app folder name under `apps/`: `calculator`, `minesweeper`, `notepad`, `stopwatch`, `render-queue`, `launcher`, `notes_rust` |
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
| `SITE_DOMAIN` | `site`, `site-check`, `publish-site` | The domain the website is served at (default `kits.slashbuilder.com`). It is written into the `CNAME` file of the published branch. Set in the Makefile, in one place |
| `SITE_TITLE` | `site` | The title shown on every page of the website (default `The Kit Book`) |
| `SITE_REPO_URL` | `site` | The repository address used for the "edit this page" links and for the rewritten links into `apps/` and `labs/` (default `https://github.com/slash-builder/kit-book`) |
| `SITE_REPO_BRANCH` | `site`, `publish-site` | The branch those links point at (default `main`); `publish-site` only pushes from this branch |
| `SITE_REWRITE_REPO_LINKS` | `site` | `1` (default) rewrites links from the book to files outside `book/` into GitHub addresses; `0` leaves them as relative links, which do not work on the website |
| `SITE_INDEXABLE` | `site`, `site-check`, `publish-site` | `0` (default) puts `<meta name="robots" content="noindex">` on every page; `1` leaves it out so search engines may index the site (mdBook keeps noindex on its own `print.html` and `toc.html`). Set `1` only when the site is meant to be found |
| `PUBLISH` | `publish-site` | `1` allows the push to the `gh-pages` branch, and only if the repository behind `origin` is public. Anything else is a dry run |
| `MDBOOK` | `site` | The path of the `mdbook` program to use. Otherwise `mdbook` on the `PATH`, then `~/.cache/mdbook/mdbook` |
| `NO_COLOR` | all | Turns off colours in the output |
| `KITS_LOCK` | the scripts in `tools/` | Read a different lock file (used for testing the fetch script) |

## Targets

### `help`

The default. Prints every target with a one-line description.

### `all`

What CI runs: `lint`, then `test-fast`, then `build`.

### `doctor`

Checks the toolchain and prints a table: tool, whether it is required, status, the version found and the version wanted. For each missing or too-old tool it prints the install command for your system (Homebrew on macOS, `apt` on Debian and Ubuntu). It installs **nothing** and exits non-zero only when a **required** tool is missing or too old.

* **Required:** Flutter and Dart (the minimum Dart is read from the apps' `pubspec.yaml` files), Rust and Cargo (the minimum is the highest `rust-version` among the Kits' crates and the apps' Rust cores), `curl`, `tar`, Python 3, and on macOS the Xcode command line tools. **`flutter_rust_bridge_codegen` is required while an app with a Rust core (`apps/notes_rust`) is in the tree**, at exactly the version that app pins in its `pubspec.yaml` (`flutter_rust_bridge: 2.12.0` today); it is looked for on `PATH` and in `~/.cargo/bin`, where `cargo install` puts it.
* **For apps:** needed only to build and run the demo apps. On macOS, the full Xcode app, and CocoaPods when an app has a native plugin (the Rust core's build glue is one). On Linux, `clang`, `cmake`, `ninja`, `pkg-config` and the GTK 3 development files. `make apps` requires them; `make test-fast` does not.
* **Optional:** Docker (for the Linux container checks), `redis-server`, `protoc`, `flutter_rust_bridge_codegen` (optional only when no app in the tree needs it), the GitHub CLI (`gh`, for private Kits) and `mdbook` (for `make site`).

### `setup`

Runs `doctor`, then `fetch`, then `flutter pub get` or `dart pub get` for every app and package, then `cargo fetch` for each Kit's Rust crate and for each app's own Rust core. Safe to run again. `KITS=all` also fetches private Kits. `SETUP_INSTALL=1` offers to run the install commands for missing required tools; the default never installs.

### `fetch`

Reads [`kits.lock`](#kitslock) and, for each Kit (unless [`kits.override`](#kitsoverride) names a local checkout for it), downloads the archive at the pinned commit into `.kits/<name>/`. Public Kits come from a plain `curl` download. Private Kits come from the GitHub CLI (`gh api`) when it is logged in, else from `GITHUB_TOKEN`; with neither, the Kit is skipped with a one-line explanation. After unpacking it writes `.kits/<name>/.fetched` containing the commit, and skips the Kit next time when that matches. It checks that the archive really is the commit asked for. No git and no submodules are involved. One line per Kit: `fetched`, `up to date`, or `skipped (why)`.

### `lock`

Shows how the pins would move: for each Kit it asks GitHub for the newest commit of the default branch and prints `old -> new` with a compare link. It rewrites `kits.lock` only after you answer `y`. `make lock KIT=application-kit` does one Kit. After it, run `make setup` and `make test-fast`.

### `test`

Runs every fetched Kit's own test suite, then `labs/interface_candidates`, then every demo app (an app with a Rust core runs its `cargo test` first and then `flutter test`, which uses an in-memory stand-in for the core, so it needs no native build), then the integration suites that can run on this computer. A Kit with a `Makefile` is tested with its own `make test-fast` (or `make test`); a Kit without one is tested with its native commands (`dart test`, `flutter test`, `cargo test`). Prints a table with each suite's passed, failed and skipped counts and its seconds; logs are in `build/test-logs/`. Exits non-zero when any suite that ran has a failure.

### `test-fast`

The same as `test` without anything that needs Docker, Redis or a running daemon. This is the everyday command. It also runs the unit tests of the maintainer tools (see [`test-tools`](#test-tools)) when PyYAML is installed, and skips them with a message when it is not.

### `test-integration`

Only the suites that need Docker, Redis or a daemon. Each one skips with a clear message when its tool is absent; skipping is never a failure.

| Suite | Needs | What it does |
|---|---|---|
| Linux containers | The Docker daemon running | Runs a Kit's Dart and Rust cores in throwaway Linux containers, if the Kit ships a script for it (the Application Kit does) |
| Resource-broker daemon tests | `VENUE_TOKEN_FILE` set to a token for a running broker | Runs the render-queue tests that otherwise skip themselves |
| App integration tests | A desktop to run an app on (macOS, or Linux with a display) and the Kits the app builds against | Runs an app's `integration_test/` inside the built app with `flutter test integration_test -d macos`, so a Rust core is the real native library. `apps/notes_rust` has one |
| Message-hub probes | Redis | These run in a private repository; nothing here runs yet |

### `apps`

Builds every demo app in debug mode for this computer (macOS or Linux desktop). Needs the "for apps" tools from `doctor` and a fetched Application Kit.

### `app`

Builds one app: `make app APP=notepad`.

### `run`

Runs one app on this computer: `make run APP=notepad`.

### `frb`

Regenerates the Flutter-to-Rust bridge (`flutter_rust_bridge_codegen generate`) for every app that has a `flutter_rust_bridge.yaml`, which is `apps/notes_rust` today. Run it after changing the bridge layer (`rust/src/api/*.rs`) and commit the result: the generated files are committed so that `make app` works without this tool. It refuses to run with a codegen whose version differs from the one the app pins.

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
| the Kit's root `README.md` or `CONTRIBUTING.md`, when the Kit is **private** and its section sets `home` | a link to the Kit's entry in the catalog (the page named by `home`), so "Repository home" and "Contributing" lead somewhere |
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
* the reference-docs puller, `tools/tests/test_pull_docs.py`: each class of link rewrite, the banner, anchors, idempotence, the pin refusal and `--check`. They need nothing beyond Python 3;
* the website tools: `tools/tests/test_site_stage.py` (the link rewrite and the README rename), `tools/tests/test_site_check.py` (the checks of `site-check`) and `tools/tests/test_publish_site.py` (the dry run and the push guard, against a local bare repository and a stub `gh`; needs `git`). They need nothing beyond Python 3.

Plain `python3 -m unittest` from the repository root runs the same tests.

### `site`

Builds the book as a website with [mdBook](https://rust-lang.github.io/mdBook/) into `build/site/`, ready to be served at the root of `SITE_DOMAIN`. If mdBook is not installed it prints how to install it and exits 0. How the site is built and published is in [Publishing the website](publishing.md); the steps in order:

1. **Stage the book.** `book/` is copied to `build/site-src/`, and in the copy every link to a path outside `book/` (the demo apps, the labs, `CONTRIBUTING.md` and so on) becomes a link to the file or folder on GitHub (`SITE_REPO_URL`, `SITE_REPO_BRANCH`). Links that stay inside the book are left alone. It prints how many links it rewrote. While the repository is private those addresses answer 404 for everyone without access, and `make site` says so. `SITE_REWRITE_REPO_LINKS=0` turns the rewrite off. The same step renames an in-book link to a folder's `README.md` to `index.md`, because mdBook publishes that page as `index.html`. `book/` itself is never changed.
2. **Build with mdBook.** The configuration is generated into `build/mdbook/`, so there is no `book.toml` to keep in step. The site is served at `/`, search is on, every page has an "edit this page" link, and there is a `404.html`. The default favicon is kept.
3. **Diagrams.** The `mermaid` code blocks of the pulled Kit pages are drawn in the browser by a pinned copy of mermaid that is committed in `tools/site/vendor/` and copied into the site; nothing is loaded from another host. The page's light or dark theme decides the diagram colours.
4. **Robots.** Every page gets `<meta name="robots" content="noindex">` unless `SITE_INDEXABLE=1`.
5. **Publish staging.** `build/site-publish/` is `build/site/` plus a `CNAME` file holding exactly `SITE_DOMAIN` and an empty `.nojekyll`. That folder is what `publish-site` commits.

Preview it with `python3 -m http.server -d build/site 8000`. The first line of output says how many pages were built. `make docs` does not need mdBook and is unchanged.

### `site-check`

Checks the site that `make site` built (it stops with a message if there is none) and prints one line per check. It uses only Python 3.

* **Links:** every internal link, script, stylesheet and image address in every generated page resolves to a file, and every `#fragment` is an id that exists in the page it points to. Addresses to other sites are counted but not fetched.
* **Publish folder:** `build/site-publish/` has a `CNAME` that holds exactly `SITE_DOMAIN`, an empty `.nojekyll`, an `index.html`, and the same pages as `build/site/`.
* **Robots:** with `SITE_INDEXABLE=0` every page carries the noindex tag; with `SITE_INDEXABLE=1` none does, except `print.html` and `toc.html`, which mdBook always marks noindex itself.
* **Diagrams:** the vendored `tools/site/vendor/mermaid.min.js`, the copy in the site and the copy in the publish folder all match the sha256 recorded in `tools/site/vendor/README.md`, the licence file is there, and every page with a diagram loads the init script.

Exits non-zero on any failure.

### `publish-site`

Maintainers only. Removes the old build, runs `make site` and `make site-check`, then commits the contents of `build/site-publish/` as **one orphan commit** (no parent) to a local branch `gh-pages`. The commit is built with a scratch index and no checkout, so `main`, your index and your working tree are never touched.

* **By default it is a dry run:** it prints the commit, its file count, its `CNAME`, the repository's visibility, the push it would have made, and why it did not, and exits 0.
* **It pushes only when all of these hold:** `PUBLISH=1`; `gh repo view` says the repository behind `origin` is `PUBLIC`; the working tree has no uncommitted changes; and the current branch is `SITE_REPO_BRANCH`. The push is `git push --force-with-lease=refs/heads/gh-pages:<what origin holds now> origin gh-pages:refs/heads/gh-pages`. It never pushes any other branch.
* It does not turn GitHub Pages on, change any GitHub setting, or touch DNS. Those steps, and their order, are in [Publishing the website](publishing.md#going-public-in-order).

Undo the local branch with `git branch -D gh-pages`.

### `check-public`

Scans every file in the tree except `.kits/` and build output for anything that must not be public: internal hostnames, ticket ids, local paths that contain a user name (except the invented user name `ada` that the Kits' reference pages use in examples), notes-vault paths, references to agent instruction files, repository URLs that are not public Kits in `kits.lock` or on the card of a Kit that `tools/kit-visibility.tsv` marks public, people named in credits or licence text other than the author, and secret patterns. The generator `tools/gen-catalog.py` and its tests are not scanned, because they spell the patterns out; what they generate, including `tools/kit-visibility.tsv`, is. This repository's own address (`github.com/slash-builder/kit-book`, which the website links to) is allowed. One more file is skipped: the vendored `tools/site/vendor/mermaid.min.js`, third-party minified JavaScript that nobody here edits. It is skipped only while its sha256 equals the one recorded in `tools/site/vendor/README.md`; if the file changes it is scanned like everything else, and the README and licence next to it are always scanned. It prints `file:line` for every hit and exits non-zero on any. While `kits.lock` lists private Kits it also prints a note that each must become public (or stop being needed) before this repository is made public.

### `clean`

Removes build output: `build/`, each app's and lab's `build/` and `.dart_tool/`, an app's Rust core `target/` folder, and Rust `target/` folders inside `.kits/`. Keeps the fetched Kits.

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

## `kits.override`

Optional. One line per Kit, `name  path`, with the path relative to the repository root; lines starting with `#` are comments. For a Kit named here, `make fetch` and `make setup` link `.kits/<name>/` to that local checkout instead of downloading the pin in `kits.lock`, and say so in their output, because the pin is then not what you are building against. The file exists for a Kit change that is not merged yet. It is not meant to stay: the steps for removing a line are in the file's own header comment.

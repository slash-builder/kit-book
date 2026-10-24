# Make targets

Everything is driven from the `Makefile` at the repository root. It works with the system `make` on macOS (3.81) and Linux and uses nothing newer. `make` on its own runs `make help`, which lists every target with one line. The Makefile follows the convention of the Kit repositories (`help`, `all`, `build`, `lint`, `test`, `fmt`) so the CI job and people use the same names.

The scripts behind the targets are in [`tools/`](../../tools/). They are plain POSIX `sh` (and Python 3 for the link checker), so they run on the `/bin/sh` and `/bin/bash 3.2` that ship with macOS.

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

The same as `test` without anything that needs Docker, Redis or a running daemon. This is the everyday command.

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

A hook for the generated Kit catalog. It prints "catalog generation not implemented yet" today. The rule it will follow: the catalog lists **every** Kit in the registry, public, private, banked and archived, as status cards, with a repository link only for public Kits; this repository is the book, not a Kit, and is never listed.

### `site`

Builds the book as an HTML website with [mdBook](https://rust-lang.github.io/mdBook/) into `build/site/`. If mdBook is not installed it prints how to install it and exits 0. Links from the guides into `apps/` and `labs/` do not work in the generated site because those folders are outside the book; they do on GitHub.

### `check-public`

Scans every file in the tree except `.kits/` and build output for anything that must not be public: internal hostnames, ticket ids, local paths that contain a user name, notes-vault paths, references to agent instruction files, repository URLs that are not public Kits in `kits.lock`, people named in credits or licence text other than the author, and secret patterns. It prints `file:line` for every hit and exits non-zero on any. While `kits.lock` lists private Kits it also prints a note that each must become public (or stop being needed) before this repository is made public.

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

# Start here

From an empty folder to a running app. You need `make` (it comes with the Xcode command line tools on macOS and with `build-essential` on Debian and Ubuntu) and a way to get this repository onto your computer: either `git clone`, or the "Download ZIP" button on GitHub. After that, no git is needed: the Kits are downloaded as plain archives.

## 1. Check your computer

```sh
make doctor
```

This prints a table of the tools the demos need (Flutter and Dart, Rust, a C toolchain, and a few optional ones such as Docker), what it found, and the exact install command for your system where something is missing. **It installs nothing**, and it fails only when a required tool is missing. Run the commands it prints yourself, then run `make doctor` again until the last line says everything required is installed.

If you would rather have the tool run the install commands for the required tools, `SETUP_INSTALL=1 make setup` prints them and asks "y/N" before running anything.

## 2. Fetch the Kits and the packages

```sh
make setup
```

This runs the doctor, downloads each Kit listed in [`kits.lock`](../kits.lock) into `.kits/` at its pinned commit (printing one line per Kit: fetched, up to date, or skipped and why), then fetches the Dart, Flutter and Rust packages every project needs. It is safe to run again.

While some Kits are private, fetch them too. This needs a GitHub login: install the [GitHub CLI](https://cli.github.com/) and run `gh auth login`, or set a `GITHUB_TOKEN` environment variable that can read the repositories.

```sh
make setup KITS=all
```

Without a login, private Kits are skipped with a one-line explanation. A demo app that needs a Kit that was skipped is skipped too, with a line that says which (for example `skipped apps/notes_rust: needs storage-kit (private; fetch with KITS=all)`); everything else still sets up and tests. The demo apps all need the App Context Kit, so while that is private they cannot be built or tested without a login.

## 3. Run the tests

```sh
make test-fast
```

This runs every fetched Kit's own tests, the components in `labs/`, and the tests of all seven demo apps (the Rust core of `notes_rust` is tested with `cargo test`), then prints a table: suite, passed, failed, skipped and seconds. It finishes with `OK` or `FAILED`. `make test` additionally runs the suites that need Docker, Redis or a running daemon, and skips them with a message when the tool is absent.

## 4. Build and run an app

```sh
make app APP=calculator    # a debug build for this computer
make run APP=calculator    # run it (macOS or Linux desktop)
make apps                  # build all seven
```

The apps are Flutter desktop apps. On macOS this needs the full Xcode app, not only the command line tools; on Linux it needs a few packages (`make doctor` lists them). Windows is not covered.

To see two copies of an app find each other, follow [run two copies and watch them find each other](20-guides/demo-apps.md#run-two-copies-and-watch-them-find-each-other).

## When something goes wrong

| You see | What it means | What to do |
|---|---|---|
| `make doctor` says a tool is `MISSING` or `TOO OLD` | The tool is not installed or is older than the apps need | Run the command listed under "What to do", then `make doctor` again |
| `skipped (private Kit; run: make setup KITS=all)` | That Kit is not public yet | Log in with `gh auth login`, then `make setup KITS=all` |
| `skipped (no GitHub login ...)` | You asked for private Kits without a login | Same as above, or set `GITHUB_TOKEN` |
| `skipped apps/<app>: needs <kit> (...)` | That app needs a Kit that is not fetched (it lists it in its `kits.need`). Skipping is not a failure | Nothing, or `make setup KITS=all` if the Kit is private and you have access |
| `app-context-kit is not fetched` | The demo apps need the App Context Kit | `make setup KITS=all` |
| `cargo ... skipped: could not resolve` | The Rust crate needs a Kit that is not fetched | `make setup KITS=all` |
| A test fails | Something real, or a changed Kit pin | Read the log named under the table (`build/test-logs/`); see [Make targets](90-reference/make-targets.md) |

## Where to go next

Read the [demo apps guide](20-guides/demo-apps.md) to see what each app asks of the Kits, then the [make targets](90-reference/make-targets.md) for everything else the Makefile can do.

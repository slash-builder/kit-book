# Demo apps

Seven small Flutter desktop apps in `apps/` that use the Application Kit (the name is provisional; so is the name of the resource broker the Kit talks to, Venue). They were written to measure the Kit: what it removes from an app, what it still leaves for the app to write, and where it falls short.

One rule shaped them: **an app does not edit the Kit.** If an app needs something the Kit lacks, it writes it under `lib/kit_gaps/` with a `// KIT GAP:` comment. The line count of those directories is the measurement of what the Kit is missing. When the Kit absorbs a gap, the app deletes its copy.

| App | Manifest id | Exercises | Kits in `app.json` | Tests | `main.dart` lines | Gap lines left | `lib/coordination` lines |
|---|---|---|---|---|---|---|---|
| [calculator](#calculator) | `dev.demo.calc` | The least an app can ask of the Kit | none | 32 | 5 | 0 | none |
| [minesweeper](#minesweeper) | `dev.demo.minesweeper` | Saved game state; handing a game to another copy | `peers` | 86 | 5 | 0 | 329 |
| [notepad](#notepad) | `dev.demo.notepad` | Files on disk, autosave, damaged files; syncing notes between copies | `peers` | 63 | 5 | 79 | 619 |
| [stopwatch](#stopwatch) | `dev.demo.stopwatch` | State that survives restart; a shared countdown and a signal between copies | `venue`, `peers` | 49 | 10 | 35 | 332 |
| [render-queue](#render-queue) | `dev.demo.render-queue` | A session with a resource broker: holds, refusals, waiting | `venue` | 38 passed, 5 skipped | 11 | 0 | none |
| [launcher](#launcher) | `dev.demo.launcher` | The roster: who is running on this machine | `venue` | 24 | 9 | 50 | none |
| [notes_rust](#notes_rust) | `dev.demo.notes-rust` | A Flutter UI over a **Rust core** that uses the Storage Kit and shares one Application Kit context with the UI; sync with the blocks and checks in Rust | `peers` | 29 `cargo test` + 19 + 10 integration | 35 | 81 | 416 |

How the numbers were taken for the first six apps, on 2026-10-24 with Flutter 3.41.9 and Dart 3.11.5 on macOS (Apple silicon): tests are the result of `flutter test` in each app directory; `main.dart` and gap lines are `wc -l` (raw lines, comments and blanks included) of `lib/main.dart` and `lib/kit_gaps/*.dart`; coordination lines are `wc -l` of `lib/coordination/*.dart`. The five skipped render-queue tests need a running resource-broker daemon and skip themselves when no token is set. The `venue` entry in `kits` is a label: only `peers` is checked against the `kits` list today (see the Application Kit's architecture guide, section 1).

Contents: [running and testing any app](#running-and-testing-any-app) · [the seven apps](#calculator) · [how much code the Kit saved](#how-much-code-the-kit-saved) · [run two copies and watch them find each other](#run-two-copies-and-watch-them-find-each-other)

## Running and testing any app

Each app is a standard Flutter project. Desktop runners exist for macOS and Linux; the apps were run on macOS only. Every command below assumes you are in the repository root, and that you have run `make setup` once (add `KITS=all` while the Application Kit is private) so the Kits the apps depend on are in `.kits/`.

The Makefile wraps the common cases: `make test-fast` runs every app's tests, `make app APP=stopwatch` builds one app for this computer and `make run APP=stopwatch` runs it. The plain Flutter commands work too:

```sh
cd apps/stopwatch        # or any app
flutter pub get
flutter run -d macos     # run it
flutter test             # run its tests
```

An app reads its settings from environment variables before it opens. These are the ones that matter. `PREFIX` is the app's `envPrefix`, or the last segment of its id, upper-cased: `CALC`, `MINES`, `NOTEPAD`, `STOPWATCH`, `RENDER_QUEUE`, `LAUNCHER`.

| Variable | Effect |
|---|---|
| `APPKIT_SCRATCH=/some/dir` | Puts the app's data, config, state, cache and runtime directories, and the roster, under `/some/dir`. Use it to run without touching your real settings |
| `PREFIX_MODE=mock` (or `APPKIT_MODE=mock`) | Mock mode: the resource-broker session is an in-memory fake, and peers use the fake network |
| `APPKIT_DEVICE=laptop` | The name of this copy for peers. Give each copy its own |
| `APPKIT_ACCOUNT=home` | The account half of the peer scope key. Default `local` |
| `APPKIT_PEERS_DIR=/some/dir` | Where copies on one machine announce themselves. Must be the same for every copy |
| `APPKIT_ROSTER_DIR=/some/dir` | Where the app writes its presence file. Beats `APPKIT_SCRATCH` |
| `PREFIX_DATA_DIR`, `PREFIX_CONFIG_DIR`, ... | Override one directory exactly |

Details are in the Application Kit's specification (`spec/APP-CONTEXT.md` in that Kit), sections 2 and 6.3.

`flutter run -d macos` starts the app as a child of the Flutter tool, which passes your shell's variables on (this is from reading the tool's source; no window was opened for this page). An app started from Finder or the Dock does not see your shell's variables.

**The macOS sandbox rule.** Three apps have the macOS App Sandbox on: calculator, minesweeper and notepad. The other three (launcher, render-queue, stopwatch) have it off. A sandboxed app can only write inside its own container, `~/Library/Containers/<bundle id>/Data/`, and that container also has its own `HOME` and `TMPDIR`. Two things follow:

- A path outside the container, such as `/tmp/...`, in `APPKIT_SCRATCH` or `APPKIT_PEERS_DIR` does not work for a sandboxed app. With `APPKIT_SCRATCH` the app cannot create its directories: the companion shows its startup error screen (the calculator's first version, before the companion package, crashed with an unhandled `PathAccessException`). With `APPKIT_PEERS_DIR` the process stays up and works alone, and the footer says "Peers: off (peers unavailable: ...)" (asserted in a widget test, not seen). Use a path under the container instead, for example `~/Library/Containers/dev.demo.notepad/Data/tmp/ak-scratch`. The bundle ids are `dev.demo.calc`, `dev.demo.minesweeper` and `dev.demo.notepad`.
- The default roster and peers directories are inside the container too. Two copies of one sandboxed app share the container and find each other with no variables set. Two different sandboxed apps have different containers, so they are not expected to share a roster (reasoned, not tested).

The sandboxed apps that use peers, notepad and minesweeper, also need the `com.apple.security.network.client` and `com.apple.security.network.server` entitlements; both projects have them in Debug and Release. With only the server entitlement, two copies listen but never connect, and nothing is logged. That observation was recorded in the apps' development notes (not published) and was not repeated for this page.

Everything about the sandbox is macOS-specific, and the entitlement files are native build files that a running Dart app cannot change. The Application Kit's platforms guide has the full table of what each capability needs.

## calculator

Folder: [`apps/calculator`](../../apps/calculator/README.md).

**Exercises.** The least an app can ask of the Kit. A four-function calculator with no stored state, written to find the minimum useful adoption.

**Run and test.**

```sh
cd apps/calculator
CALC_MODE=mock flutter run -d macos    # shows a "mock" chip in the app bar
flutter test                           # 32 tests
```

**What the Kit gave it.** `AppKit.run` loads `app.json` from the asset bundle and closes the app once on window close, quit, SIGINT or SIGTERM. `AppContextScope` supplies the app name for the title. `ModeBadge` shows the mock and scratch chip. `pumpKitApp` in the tests runs the app in mock mode under a scratch directory. The Kit also writes a roster entry that nothing in this app reads.

**What it still writes itself.** Nothing: `lib/kit_gaps/` does not exist. The whole of `main.dart` is:

```dart copied-from=apps/calculator/lib/main.dart
import 'package:application_kit_flutter/application_kit_flutter.dart';

import 'ui/calculator_app.dart';

Future<void> main() => AppKit.run(manifestAsset: 'app.json', app: (_) => const CalculatorApp());
```

**Did it need the Kit?** No. It is the floor: the Kit is nearly free here, and what it gives back is the app name, test isolation and a roster entry nobody reads.

## minesweeper

Folder: [`apps/minesweeper`](../../apps/minesweeper/README.md).

**Exercises.** A game saved to disk (the game in progress, high scores, two settings), and, through the peer layer, handing a game to another copy or playing one board together. It is the case where a state change has to happen on two sides.

**Run and test.**

```sh
cd apps/minesweeper
flutter run -d macos
flutter test                           # 86 tests
```

This app is sandboxed. To run two copies that find each other, see [the walkthrough](#run-two-copies-and-watch-them-find-each-other) and use paths under the container. To exercise the handoff without a window, run the probe (below).

**What the Kit gave it.** The data directory and `AppJsonFile` for the saved game and scores, `SessionSettings` for the two settings, `ctx.startPeers` to find and connect to other copies, `PeerJson` for the message bodies, `PeersIndicator` for "This copy / Peers: N", `NotesBanner` and `ModeBadge`.

**What it still writes itself.** No gap files. `lib/coordination/` (329 lines) is the game protocol: the offer, the person's yes or no, the pull of the board, the confirmation, and the checks that refuse anything inconsistent. That is the app's meaning and stays the app's.

**A probe, not a window.** `tool/peer_probe.dart` runs the app's own coordination code without a window, over the real loopback provider. Two probes on one machine, one offering a game and one accepting:

```sh
cd apps/minesweeper
dart run tool/peer_probe.dart --scratch /tmp/ak-ms/laptop  --peers /tmp/ak-ms/peers --device laptop  --for 9 --accept &
sleep 3
dart run tool/peer_probe.dart --scratch /tmp/ak-ms/desktop --peers /tmp/ak-ms/peers --device desktop --for 6 --game --offer 1:handoff
```

A run of exactly this on 2026-10-24 printed, trimmed to the lines about the handoff (the first number is epoch milliseconds):

```text
laptop:   1792851222914 HOOK message="desktop #c694 wants to send you a game." incoming=1 sharing=null
laptop:   1792851222924 ADOPT status=playing sum=649a874f5e98919e
laptop:   1792851222925 ACCEPTED -> Took over the game from desktop #c694.
desktop:  1792851221880 GAME in progress sum=649a874f5e98919e
desktop:  1792851222907 COMMAND offer handoff
desktop:  1792851222925 RELEASE to laptop #f142
```

The offer arrived 7 ms after it was sent, the board was applied 10 ms later and the sender released its game when the receiver confirmed. Both boards have the same checksum. This is two probes, not two windows, so it shows the protocol and not what a person sees.

**Did it need the Kit?** For handing a game to another copy it needs a way to find and reach that copy, and the Kit supplies it; the protocol that makes a handoff safe, and what happens when a message is lost, is the app's 329 lines.

## notepad

Folder: [`apps/notepad`](../../apps/notepad/README.md).

**Exercises.** One JSON file per note in the data directory, autosave 600 ms after the last keystroke, damaged-file handling, and the close hook that flushes unsaved typing on quit. With peers: syncing notes between copies, including conflicts and notes too large for one message. It is the heaviest user of the hook.

**Run and test.**

```sh
cd apps/notepad
flutter run -d macos
flutter test                           # 63 tests
```

This app is sandboxed; see the sandbox rule above. Two copies need different `APPKIT_DEVICE` values: notepad refuses a peer with its own device id, because two copies with one device id share one notes folder and are one replica.

**What the Kit gave it.** The data directory, `ctx.dataJson('sync.json')` and `AppJsonFile` for atomic JSON files, `SessionSettings`, `ctx.onClose` to save the last keystrokes, `ctx.startPeers`, `PeerJson`, `PeersIndicator`, `NotesBanner`, `ModeBadge`.

**What it still writes itself.** One gap file: `lib/kit_gaps/blob_pull.dart` (79 lines), a chunked transfer for notes larger than one message, pulled part by part over request and reply. It stays because only one app wants it. `lib/coordination/` (619 lines) is the sync engine: version vectors, conflict copies, the digest exchange. The hook itself, `note_sync_hook.dart`, is 29 lines.

**A probe, not a window.** Two probes over the real loopback provider; the second creates a 300-character note after the first is ready:

```sh
cd apps/notepad
dart run tool/peer_probe.dart --scratch /tmp/ak-np/laptop  --peers /tmp/ak-np/peers --device laptop  --for 10 &
sleep 3
dart run tool/peer_probe.dart --scratch /tmp/ak-np/desktop --peers /tmp/ak-np/peers --device desktop --for 7 --create 1:Shopping:300
```

A run on 2026-10-24 (trimmed):

```text
desktop: 1792851200930 COMMAND created hniggyzhs0ggau "Shopping" body=300
laptop:  1792851200960 NOTE hniggyzhs0ggau "Shopping" body=300 chars
```

The note was a file in the other copy's notes folder 30 ms after it was created. Afterwards `find /tmp/ak-np -name '*.json'` lists the same note file under both scratch directories, plus each side's `sync.json`. A person typing would add the 600 ms autosave pause to that number; that was not measured.

**Did it need the Kit?** The Kit supplied find, connect and route; replicated notes still cost about 620 lines of the app's own code (versions, conflicts, chunked transfer) that the Kit does not provide.

## stopwatch

Folder: [`apps/stopwatch`](../../apps/stopwatch/README.md).

**Exercises.** A stopwatch with laps and a countdown. Its state is a point in time plus banked time, saved on every change, so it tests the state directory, settings, and a clean quit and relaunch. With peers: one countdown shared between copies, and a "timer finished" signal announced by one copy.

**Run and test.**

```sh
cd apps/stopwatch
flutter run -d macos
flutter test                           # 49 tests
```

This app is not sandboxed, so `/tmp` paths work.

**What the Kit gave it.** The state directory and settings file, `ctx.onClose` to save, the exit path, test isolation (the "start, lap, relaunch" test is two opens on one scratch directory), `ctx.startPeers`, `PeerJson`, `PeersIndicator`, `NotesBanner`, `ModeBadge`.

**What it still writes itself.** One gap file: `lib/kit_gaps/notifier.dart` (35 lines), which shows a desktop notification through `osascript` or `notify-send`. It is not something the Application Kit should own. `lib/coordination/` (332 lines) is the shared-countdown rule.

**Did it need the Kit?** It needed the state directory, settings, the exit path and, for coordination, discovery and routing; it never needed the resource broker.

## render-queue

Folder: [`apps/render-queue`](../../apps/render-queue/README.md).

**Exercises.** A session with a resource broker. Each job takes a hold (`ctx.venue.withHoldWaiting`), runs, and releases it. It tests what the app does when the broker refuses, waits for capacity, or loses the app (a killed app keeps its hold until the lease runs out).

**Run and test.**

```sh
cd apps/render-queue
RENDER_QUEUE_MODE=mock flutter run -d macos   # an in-memory broker that grants 2 holds at once
flutter run -d macos                          # real mode
flutter test                                  # 38 passed, 5 skipped
```

In real mode, with no broker token configured, the session is a local one with no limit, and the app says so. Connecting to a real broker daemon needs a token and the daemon's address; the variables are in the Application Kit's specification (`spec/APP-CONTEXT.md` in that Kit), section 3. The daemon is not part of this repository, which is why the real-daemon tests skip. The app's behaviour when refused is a setting in `config.json`: `policy` (`wait` or `failFast`), `maxWaitSeconds`, `retrySeconds` and `leaseSeconds`.

**What the Kit gave it.** The session that hides fake, local and real, `withHoldWaiting` (retry a refusal for up to `maxWait`, with cancel), typed refusals, the settings file, `ctx.onClose` to cancel running jobs and wait for their holds to be released before the session closes, and the roster scan it uses to tell whether another copy of the app is running.

**What it still writes itself.** No gap files. The app keeps the policy (wait or fail fast) and the words the person reads.

**Did it need the Kit?** Yes, and this is the clearest case: the one thing it needed from the broker session that the Kit lacked, waiting for capacity, is now in the Kit.

## launcher

Folder: [`apps/launcher`](../../apps/launcher/README.md).

**Exercises.** The roster. The launcher lists the apps that are running on this machine, which tests whether a file-based presence list is enough.

**Run and test.**

```sh
cd apps/launcher
LAUNCHER_APPS_DIR="$PWD/.." flutter run -d macos   # also lists the manifests found in apps/*/app.json
flutter test                                       # 24 tests
```

The launcher is not sandboxed. It sees an app only if that app writes its presence file to the same roster directory. The three sandboxed apps write inside their own containers, so to see apps in the launcher run the unsandboxed ones (stopwatch, render-queue) with the same `APPKIT_ROSTER_DIR` as the launcher.

**A probe, not a window.** `tool/rows_probe.dart` prints the rows the launcher would show for a roster directory. A hand-made roster directory with one live entry and one damaged file:

```sh
mkdir -p /tmp/ak-roster
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "{\"id\":\"dev.demo.stopwatch\",\"instance\":\"a0000001\",\"name\":\"Stopwatch\",\"version\":\"0.1.0\",\"pid\":$$,\"startedAt\":\"$NOW\",\"heartbeatAt\":\"$NOW\"}" > /tmp/ak-roster/dev.demo.stopwatch@a0000001.json
echo '{broken' > /tmp/ak-roster/junk.json
cd apps/launcher && dart run tool/rows_probe.dart /tmp/ak-roster
```

It printed, on 2026-10-24 (the pid is your shell's):

```text
running  Stopwatch  dev.demo.stopwatch copy=a0000001 pid=70742 
unreadable: junk.json
```

A file whose last heartbeat is more than 15 seconds old shows as `stale`, and a file the launcher cannot parse is listed as unreadable instead of being hidden.

**What the Kit gave it.** `Roster.scan()` and `RosterRecord` (status `live`, `stale` or `unreadable`), the instance id in the file name so two copies of one app are two rows, `ctx.venue.nodes()` for the node strip, settings, and scratch isolation for the tests.

**What it still writes itself.** Two gap files, 50 lines: `manifest_scan.dart` (36), which walks a folder for `*/app.json` because nothing lists installed apps, and `pid_alive.dart` (14), which asks the operating system whether a pid is alive (`kill -0`), because `scan()` reports `live` for up to 15 seconds after a crash. Each has one user. A pid check does not work inside the macOS sandbox, and a reused pid reads as alive.

**Did it need the Kit?** For the roster, yes: `Roster.scan()` and instance ids replaced a 70-line shim (`roster_scan.dart`) and fixed two copies erasing each other's entry; the pid check, the app index and the memory of "gone" are still the launcher's own, and they are most of what makes it a launcher.

## notes_rust

Folder: [`apps/notes_rust`](../../apps/notes_rust/README.md). The only demo app with a Rust core, and the only one that uses a Kit written in Rust.

**Exercises.** The intended shape of an app: a Flutter interface over a Rust core, joined by `flutter_rust_bridge`. The core (`notes_core`) stores notes as content-addressed blocks on the **Storage Kit** and works inside the Application Kit context that the Flutter side opened. The question it answers is how two halves share one context. The Dart side opens the context once and hands the Rust side a snapshot of it; the Rust side **adopts** it (an `adopt` API added to the Application Kit for this) and so announces nothing, writes no settings, and creates files only under `data` and `state`. Notes have a version history (restoring a version writes one small manifest and copies no body). Two copies sync over the Application Kit's peer layer: Dart carries the bytes, Rust holds the blocks, checks every hash before storing anything, and reports conflicts with both versions.

**Run and test.**

```sh
make app APP=notes_rust               # needs make setup KITS=all, flutter_rust_bridge_codegen 2.12.0 and, on macOS, CocoaPods
make run APP=notes_rust
make test-fast                        # cargo test (29) and flutter test (19, in-memory stand-in for the core)
make test-integration                 # flutter test integration_test -d macos (10, the real library inside the app)
sh apps/notes_rust/tool/smoke.sh      # launch the built macOS app for 10 s, check what it wrote, SIGTERM it
```

**What the Kits gave it.** From the Application Kit: the directories and instance id (shared with Rust through the snapshot), `AppKit.run`, the config file the Dart side owns and the Rust side only reads, `ctx.startPeers` and the peer hub. From the Storage Kit: `PartitionStore`, per-partition de-duplication, hash-verified reads and the fragment trees.

**What it still writes itself.** `lib/kit_gaps/blob_pull.dart` (81 lines, copied from the notepad) for moves bigger than one message; in Rust, the head index (the Storage Kit has no mutable store implementation), a verified insert (its `put` files tampered bytes under their own hash), the child list of a list node, and the flush of the pack before a head moves. `lib/coordination/` is 416 lines of Dart; the Rust core is about 1,800 lines (plus 5,130 generated bridge lines).

**What it showed.** See the [app's README](../../apps/notes_rust/README.md#measurements) for the measurements, what the bridge made awkward and how the shared context behaved in practice.

**Did it need the Kits?** The Storage Kit supplied what a notes store is made of; the Application Kit's adopt API is what made one app with two runtimes possible without announcing twice. Neither supplied the sync protocol, the conflict policy or the head index.

## What the demo apps do not cover

* **One Rust core, not a family.** Only `notes_rust` has a Rust crate and a `flutter_rust_bridge` dependency; the other six are Flutter on a Dart core. It was built and run on **macOS**; its Linux runner exists and was not built. The bridge was not tried with a Rust-to-Dart stream, hot reload, or a second Rust core in the same app.
* **Two Kits used from Rust, the rest not.** `notes_rust` uses the Application Kit's Rust crate and the Storage Kit. Identity, messaging and transport Kits were probed in separate Rust packages in a private repository (the public-safe summary is [Fitting the Application Kit to other Kits](fitting-the-application-kit-to-other-kits.md)), and the other apps' own sync, conflict handling and large-note transfer are written in Dart. Even in `notes_rust` the transport is Dart: the peer layer has no Rust half.
* **No real network.** Peers find each other through announcement files and loopback sockets on one machine.

## How much code the Kit saved

The measurement is the size of `lib/kit_gaps/` across the six apps (raw `wc -l`), and the length of each `main.dart`.

| Stage | Gap lines, six apps | `main.dart` lines |
|---|---|---|
| Before the Kit had a Flutter companion (first round) | **727** | 13 to 19 |
| After migrating to the Kit and its companion | **330** | 5 to 11 |
| After adding coordination to three apps | **777** | 5 to 11 |
| After moving the repeated parts into the Kit | **164** | 5 to 11 |

| App | Gap lines: before | after migration | after coordination | now | `main.dart`: before | now |
|---|---|---|---|---|---|---|
| calculator | 28 | 0 | 0 | 0 | 13 | 5 |
| minesweeper | 149 | 78 | 200 | 0 | 13 | 5 |
| notepad | 149 | 78 | 281 | 79 | 13 | 5 |
| stopwatch | 91 | 35 | 157 | 35 | 19 | 10 |
| render-queue | 148 | 89 | 89 | 0 | 18 | 11 |
| launcher | 162 | 50 | 50 | 50 | 18 | 9 |
| **total** | **727** | **330** | **777** | **164** | | |

These were counted from the Application Kit repository's history on 2026-10-24: the first column at the Kit's first round, the next three at the commits that migrated the apps, added coordination, and moved the repeated parts into the Kit. The "now" column matches the apps in this repository.

**What the numbers say.** Migrating to the Kit removed about 400 lines of shims. Then adding coordination added about 450 new ones, taking the total to 777, higher than before the Kit. For a while the Kit had made `main.dart` tiny and the apps' total gap code worse. Moving the repeated parts into the Kit (`ctx.startPeers`, `PeerJson`, `PeersIndicator`, `AppJsonFile`, `SessionSettings`, `VenueSession.withHoldWaiting`) brought the total to 164, 77% below the start and 79% below the peak. Calculator, minesweeper and render-queue have no gap code left. What remains is four helpers that one app each uses: `notifier`, `blob_pull`, `manifest_scan`, `pid_alive`.

**The lesson: build a Kit piece when the second app copies it, not before.** Each piece that moved into the Kit had been written independently by several apps and was identical across them: the exit handling in all six, the JSON file store and settings wrapper in two, and the three peers helpers in three. The four that stayed out have one user each. One exception to be honest about: the wait-for-capacity loop (`withHoldWaiting`) had one app writing it, and moved because the resource-broker session was incomplete without it. These counts measure how much the Kit absorbed, not how long the work took. Lines are a proxy.

## Run two copies and watch them find each other

This uses the stopwatch because it is not sandboxed, so `/tmp` works. The first part is a probe: no window, but the app's real coordination code over real loopback TCP and a real announcement directory. The second part opens windows and was not run for this page.

### Part 1: two probes (run on 2026-10-24)

In one terminal:

```sh
cd apps/stopwatch
flutter pub get
dart run tool/peer_probe.dart --scratch /tmp/ak-demo/laptop --peers /tmp/ak-demo/peers --device laptop --for 12
```

Within a few seconds, in a second terminal:

```sh
cd apps/stopwatch
dart run tool/peer_probe.dart --scratch /tmp/ak-demo/desktop --peers /tmp/ak-demo/peers --device desktop --for 10 --start-after-ready 1
```

What the variables are: `--scratch` is `APPKIT_SCRATCH` (this copy's own data, config and state), `--peers` is `APPKIT_PEERS_DIR` (shared by both copies), `--device` is `APPKIT_DEVICE`. Each probe prints a line per event, starting with the epoch milliseconds. After the second probe is ready it plays the person on the second copy: it resets the countdown to 6 seconds and starts it. This is what the two probes printed, with the once-a-second `TICK` lines and a few `STATE` lines removed:

```text
desktop: 1792850582509 START desktop@efe50421 stamp=0
desktop: 1792850582511 PEER found laptop@a8def94c hello=null
desktop: 1792850582524 PEER ready laptop@a8def94c hello=null
desktop: 1792850583526 COMMAND reset 6s + start (this is the person on the probe copy)
desktop: 1792850583532 STATE duration=6000 running=true remaining=5999 phase=running stamp=2/desktop@efe50421
desktop: 1792850589539 NOTIFY Timer finished: 00:06 countdown is done

laptop:  1792850582523 PEER found desktop@efe50421 hello=null
laptop:  1792850582524 PEER ready desktop@efe50421 hello=null
laptop:  1792850583538 STATE duration=6000 running=true remaining=5998 phase=running stamp=2/desktop@efe50421
laptop:  1792850589540 NOTIFY Timer finished: 00:06 countdown finished on desktop #efe5
```

Read it like this. The desktop probe started and saw the laptop as `found` 2 ms later and `ready` 15 ms after it started. The countdown the desktop started was running on the laptop 12 ms after the desktop's command. When it ended, the desktop, as the writer of the current state, announced; the laptop said where it finished. While both ran, `ls /tmp/ak-demo/peers/local/dev.demo.stopwatch/` showed one announcement file for each copy, named `DEVICE@INSTANCE.json`: the directory is `<peers dir>/<account>/<app id>/`, and the account is `local` because nothing set one.

### See a crash

Start the two probes as above, but give the first `--for 20`, the second `--for 30`, and leave out `--start-after-ready`. Find its process id in its announcement file and kill it hard:

```sh
kill -9 "$(python3 -c "import json,glob; print(json.load(open(glob.glob('/tmp/ak-demo/peers/local/dev.demo.stopwatch/desktop@*.json')[0]))['pid'])")"
```

The surviving probe (the laptop) printed this on 2026-10-24, `TICK` lines removed:

```text
1792851139352 PEER found desktop@9bb7531b hello=null
1792851139361 PEER ready desktop@9bb7531b hello=null
1792851143134 PEER lost desktop@9bb7531b hello=null
1792851143134 PEER found desktop@9bb7531b hello=null
1792851146452 PEER lost desktop@9bb7531b hello=null
```

One death is three events. The operating system closed the dead copy's socket, so `lost` arrives at once. The dead copy's announcement file was still there with a recent beat, so it was `found` again. About 3.3 seconds later the beat was old enough, the provider withdrew the candidate, and the final `lost` came. The dead copy's file stays on disk until a live copy reaps it after 60 seconds. The numbers behind the rule are in the Application Kit's coordination guide, section 6 (providers).

### Part 2: two windows (not run for this page)

Build once, then run the binary twice, rather than running `flutter run` twice from one directory.

```sh
cd apps/stopwatch
flutter build macos --debug
BIN="$PWD/build/macos/Build/Products/Debug/stopwatch.app/Contents/MacOS/stopwatch"
APPKIT_DEVICE=laptop  APPKIT_SCRATCH=/tmp/ak-demo/win-laptop  APPKIT_PEERS_DIR=/tmp/ak-demo/win-peers "$BIN" &
APPKIT_DEVICE=desktop APPKIT_SCRATCH=/tmp/ak-demo/win-desktop APPKIT_PEERS_DIR=/tmp/ak-demo/win-peers "$BIN" &
```

Each window's footer should read "This copy: laptop #xxxx" and "Peers: 1" with one chip for the other copy. Start the countdown in one window and the other follows. Give each copy its own `APPKIT_SCRATCH` as well as its own `APPKIT_DEVICE`: copies that share a config directory share a generated device id. The peers directory is the one thing they share, which is why it is set with `APPKIT_PEERS_DIR`. If `APPKIT_SCRATCH` were the only variable, each copy would announce in `<its scratch>/roster-peers` and never see the other.

For the sandboxed apps (notepad, minesweeper), the same recipe works with every path under `~/Library/Containers/<bundle id>/Data/tmp/`, for example `APPKIT_SCRATCH=~/Library/Containers/dev.demo.notepad/Data/tmp/ak/laptop` and `APPKIT_PEERS_DIR=~/Library/Containers/dev.demo.notepad/Data/tmp/ak/peers`, with the binary at `build/macos/Build/Products/Debug/notepad.app/Contents/MacOS/notepad`. A copy that cannot reach the peers directory keeps working alone and its footer says why. That route was recorded in the apps' development notes (not published) and was not repeated for this page.

See also: the Application Kit's own getting-started, coordination, platforms and design-decisions guides, which ship with the Kit (after `make setup` they are under `.kits/application-kit/docs/`), and [Fitting the Application Kit to other Kits](fitting-the-application-kit-to-other-kits.md) for how it meets its neighbours.

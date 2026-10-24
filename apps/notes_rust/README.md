# notes_rust

A notes app whose core is Rust. The Flutter interface is a facade; the notes live in a Rust crate, `notes_core`, that stores them as content-addressed blocks with the **Storage Kit** and works inside the **Application Kit** context that the Flutter side opened. The two halves are joined by [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/) 2.12.0. It is the first demo app that is not Flutter on a Dart core, and the first to use a Kit written in Rust.

| | |
|---|---|
| Manifest id | `dev.demo.notes-rust` (macOS bundle id the same; Linux application id `dev.demo.notes_rust`) |
| Kits | Application Kit (Dart: `AppKit.run`, peers; Rust: the `adopt` API) and Storage Kit (Rust: `PartitionStore`, fragment trees) |
| Kits in `app.json` | `peers` |
| Runners | macOS (built and run) and Linux (runner generated; **not built or run**) |
| Tests | `cargo test` 29, `flutter test` 19 (no native library), `integration_test` 10 (the real library inside the app) |

> **One temporary thing you will meet.** The Storage Kit is private, so fetching it needs a GitHub login: `make setup KITS=all`. The Application Kit's `adopt` API is in the Kit's pinned release candidate (`kits.lock`); [`kits.override`](../../kits.override) is empty.

## Run and test

From the repository root, once: `make setup KITS=all`. It needs `flutter_rust_bridge_codegen` 2.12.0 (`cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked`; `make doctor` checks the version) and, on macOS, CocoaPods.

```sh
make app APP=notes_rust            # build the app; cargokit builds the Rust core on the way
make run APP=notes_rust            # run it
make test-fast                     # includes: cargo test (the core), flutter test (the app, fake core)
make test-integration              # includes: flutter test integration_test -d macos (the real library, inside the app)
make frb                           # regenerate the bridge after changing rust/src/api/*.rs
sh apps/notes_rust/tool/smoke.sh   # start the built macOS app for 10 s, check what it wrote, SIGTERM it
```

Two copies on one machine need different `APPKIT_DEVICE` values (the app refuses a peer with its own device id: two copies with one device id share one data folder and are one replica) and, because the macOS app is sandboxed, paths inside its container; see the [demo apps guide](../../book/20-guides/demo-apps.md#running-and-testing-any-app). `NOTES_RUST_SEED=3` writes three sample notes into an empty store (the smoke test uses it).

## What it does

* Notes: create, edit (autosave 600 ms after the last keystroke), rename, delete. Each save is a **version**.
* **Version history**: the clock button opens a sheet of every version this copy knows of; tap one to read it, or restore it. A restore writes one new manifest that points at the old version's existing blocks. No body is copied (a test counts the blocks: +1).
* **Sync between copies** over the Application Kit's peer layer, with the blocks and every check in Rust. Notes you make on one copy appear on the other; a second copy of a 10 MiB note receives the body once, and a one-byte edit moves about half a percent of it.
* **Conflicts**: two copies edit one note while apart. The core hands back both versions and never merges; the app's policy (the notepad's) keeps the later edit as the note and the other as "title (conflict from device)", and both copies reach the same result without talking.

## How the two halves share one context

This was the open question: if the Dart side opens an Application Kit context and the Rust side opens its own, the app announces itself twice and two code paths write one `config.json`. The answer here is the Kit's **adopt** API (`spec/APP-CONTEXT.md` section 8 in the Application Kit):

1. `AppKit.run` opens the context once. That side **owns `config.json` and the roster entry**.
2. `main.dart` opens the core with `FrbNotesCore.open(ctx)`, which passes `jsonEncode(ctx.snapshot())`: the directories, the instance id, the mode. No secrets and no handles.
3. Rust calls `ContextSnapshot::parse` (strict: unknown schema, missing field or relative path is a typed error that reaches Dart as `bad_snapshot`) and `AppContext::adopt`. An adopter announces nothing, starts no heartbeat, never writes `config.json`, and may create directories under `data` and `state` only. It reads settings through a reader that refuses writes (the core reads `maxNoteBytes` that way).
4. **One owner per file.** The Rust side owns what it creates under `data`: `blocks/` (the Storage Kit store), `heads-<partition>.json` (which version is current for each note) and `conflicts-<partition>.json`.

What was observed with both halves running (`integration_test/notes_rust_test.dart`, a test that mounts the real app on the real library): exactly one roster file, `dev.demo.notes-rust@<instance>.json`, written by Dart; the core reports the **same instance id** as the Dart context; `config.json` holds what Dart wrote and is byte-for-byte unchanged by core operations; a setting Dart changes (`maxNoteBytes`) is seen by the core on its next call; the roster entry is withdrawn on quit. The same test is what proves it, not this paragraph.

What is awkward: the snapshot has no **account** or **device**, which the Rust side needs (the Storage Kit partition is derived from `(account, app id)`), so Dart passes `ctx.peerAccount` and `ctx.peerDevice` next to it. And an adopter has no way to ask the owner to change a setting.

## How it stores notes

A note **version** is its body cut into blocks by the Storage Kit (FastCDC chunks under a tree of list nodes) plus a small JSON **manifest** block: title, time, device, the tree root, and the versions it follows. A version's address is the hash of its manifest, so history is a graph and two copies can tell "ahead" from "diverged". The only mutable thing is the **head index**, written last and by rename, so a crash leaves unused blocks at worst. The Storage Kit partition is `BLAKE3("slash-builder/application-kit/storage-partition/v1\n<account>\n<app id>")[0..16]`, the derivation from the Application Kit's earlier storage prototype (a test pins the same value).

## How sync works

The **transport is Dart** (`lib/coordination/`: the Kit's `PeerHub`, started by `ctx.startPeers`); **storage and verification are Rust** (`rust/src/sync.rs`). The Rust core offers `heads()`, `missing_blocks(their_heads)`, `export_blocks(hashes)`, `import_blocks(bytes)` and `apply_heads(their_heads)`:

1. The hello carries the core's **heads digest** (one hash of every head). Equal digests: nothing to do.
2. On ready, a copy whose digest differs sends its heads. A copy that lacks something asks (`missing_blocks`), the other exports, the receiver imports, and asks again, because a list node's children are only known once it is here (manifest, list node, chunks: three rounds for an edited note).
3. **`import_blocks` hashes every block before storing any.** One tampered block refuses the whole import, stores nothing and moves no head. (The Storage Kit's own `put` would file tampered bytes under their own hash without an error, so the check is the app's.)
4. Only `apply_heads` moves a head, and only when the whole version is here.

**Parts of 24 KiB.** The Hearth-compatible payload is 64 KiB minus the Kit header. A part's bytes are base64 in JSON (x4/3: 32 KiB) and the Kit's envelope encodes the payload again (x4/3: about 44 KB on the wire), which leaves about 20 KB for the header and reply fields. Blocks are up to 64 KiB, so a block is often more than one part; the receiver reassembles the whole export before verifying. The part protocol is `lib/kit_gaps/blob_pull.dart`, copied from the notepad: a Kit gap, still with one owner per app.

## Measurements

All on 2026-10-24, macOS (Apple silicon, 10 cores), Flutter 3.41.9, Rust 1.98.1, flutter_rust_bridge and its codegen 2.12.0, **debug** builds unless noted. The machine was shared with other builds; where that mattered the table says so.

| What | Result |
|---|---|
| Rust, hand-written (`wc -l`, comments and blanks included) | **1,766** in the core (`src/*.rs`), 172 in the bridge layer (`src/api/`), 847 in `rust/tests/` |
| Dart, hand-written | **2,161** in `lib/` (519 of them the in-memory fake, 81 a copied Kit gap), 777 in `test/` and `integration_test/` |
| Generated glue (committed) | **5,130**: 2,111 Rust (`frb_generated.rs`) and 3,019 Dart (`lib/src/rust/`) |
| Clean build, `make app APP=notes_rust`, debug, macOS | **51 s** with load average about 5.7 (an earlier identical run took 46 s; one run took **8 min 49 s** while other builds had the machine at load average 10 to 15, so quote the quiet figures with that caveat). This includes compiling the Rust core and its 327 packages from nothing |
| The core alone, cold `cargo build` (dev) | 30.5 s wall, 147 s CPU (user), machine quiet. `cargo test`, including compiling every test, 36.8 s |
| Incremental, debug | nothing changed 9 s; a Dart file touched 10 s; a Rust file touched 11 s |
| Clean release build, `flutter build macos --release` | 139 s at load average 11 |
| Regenerating the bridge, `make frb` | seconds after the first run (the first run took about 20 s); on a clean tree it changes nothing |
| App size, debug | 227 MB (`notes_core.framework` 128 MB) |
| App size, release | **126 MB**: `notes_core.framework` 86 MB, Flutter 28 MB, the Dart code 11 MB. Most of the 86 MB is the Storage Kit's S3 and HTTP backends (327 packages; the AWS SDK among them), which this app never calls and which are linked in anyway because the Kit offers no feature to leave them out. Whether link-time optimisation would shrink it was not tried |
| Sync, 10 MiB note, real core in the built app (`integration_test`) | cold sync 10,526,955 bytes (100.4% of the body, 524 blocks); then **one byte changed: 48,395 bytes (0.46%)** in 3 blocks over 3 rounds (a changed manifest, the root list node, one chunk). The Rust test measured 54,866 bytes. The in-memory fake, 2 MiB: 37,763 bytes |
| Two copies, both halves up | exactly one roster file; the core's instance id equals the Dart context's; `config.json` unchanged by the core (asserted in `integration_test`) |
| Launch, `tool/smoke.sh` (10 s, sandbox container) | started; one roster file; `blocks/<partition>/`, `heads-<partition>.json` and a 1,240-byte pack under `data`; SIGTERM exit code 143 after the Dart side closed the context; roster file withdrawn; nothing left running |
| `kill -9` of the app | the roster file stays (the Application Kit's rule: it goes stale after 15 s); the three notes are still in the head index; a relaunch on the same folders starts normally and writes its own roster file |
| `kill -9` of the Rust half | The core is in the app's process, so it cannot be killed apart from the Dart half. Tested on the crate alone: `rust/tests/kill9.rs` starts a writer, kills it with SIGKILL three times at different moments, reopens, and reads every note and every version in full |

Not measured: runtime speed of the core against a Dart one, memory, a Linux build, and anything on a machine that was not shared.


## What the bridge made awkward

* **Everything is a `Future`.** Each Rust call runs on the bridge's worker pool and is asynchronous in Dart. The Application Kit's coordination hook asks for `hello()` synchronously, so the heads digest is cached in Dart and refreshed after every change (extra state that can go stale). A `#[frb(sync)]` call would block the UI thread whenever the core's lock is held by a long write, so it was not used.
* **Error types.** `Result<T, E>` becomes a Dart exception of the type `E`, which has to be a struct the bridge can see (`CoreError { code, message }`). It is mapped to a `NotesCoreException` in one file (`lib/core/frb_notes_core.dart`) so the UI never sees generated types.
* **Enums that carry data need `freezed`.** The conflict answer (`KeepLocal`, `Merged { title, body }`, ...) is a Rust enum with data; the generator refused to continue without `freezed` and a `build_runner` step in the Dart project. It was replaced by a flat struct plus a plain enum (`ResolutionChoice`), and the nicer `sealed class` lives on the Dart side. Two shapes for one idea.
* **A `type R<T> = Result<T, CoreError>` alias breaks the generated Rust** (the generator does not resolve aliases); every signature spells it out.
* **Dart keywords are not avoided.** A Rust parameter named `export` became `export_` in Dart; it was renamed `bytes`.
* **Integers.** `u64` arrives as `BigInt` and `i64` as `int`, so the mapping layer is full of `.toInt()`. Block exports are `Vec<u8>`: `Uint8List` coming back, but `List<int>` going in, which copies.
* **Streams.** Not used: sync is request and reply over the Kit's peer layer, and Dart drives it. A Rust-to-Dart event stream would have been the natural way for the core to say "a note changed"; polling after each sync step does it instead. Not tried.
* **Testing without the library needed a whole second implementation.** The `NotesCore` interface, the 135-line bridge mapping and a 519-line in-memory fake exist so widget tests run without a Rust build. A shared contract test (`test/support/contract.dart`) runs on both the fake and the real core so they cannot drift quietly.
* **Codegen churn.** Adding one field to one struct (checked, then reverted) changed 16 lines in three generated files. The generated glue is 5,130 lines, about three times the hand-written bridge layer and more than the whole Rust core, and is committed.
* **Build plumbing.** The generated glue's library name must equal the CocoaPods plugin name, so the plugin package is called `notes_core` after the crate. macOS needs CocoaPods only because of the plugin. Without a deployment target set for the Rust build, the linker printed 391 "built for newer macOS" warnings (fixed in `rust/.cargo/config.toml`).
* **Hot reload.** Not tested. A change to Rust needs a rebuild; Dart-only changes rebuild in seconds (see the table).
* **A test run replaces the app.** `flutter test integration_test -d macos` builds into the same `build/macos/.../Debug/notes_rust.app` as `make app`, so running it and then launching that app starts the test harness (a black window), not the app. Run `make app` again before `tool/smoke.sh`.

## Generated files: committed, and why

`lib/src/rust/*` and `rust/src/frb_generated.rs` (5,130 lines, more than the hand-written Rust core) are **committed**, like Bozzetto's. A clean checkout then builds with `make setup && make app APP=notes_rust` without running the code generator, which takes a Rust toolchain build of its own to install. The cost is review noise whenever the bridge changes; `make frb` regenerates, and running it on a clean tree produces no diff (checked). `make doctor` still requires the pinned `flutter_rust_bridge_codegen`, because whoever changes the bridge must regenerate with the matching version.

## Layout

```text
app.json, pubspec.yaml            the Application Kit manifest and the Flutter app (flutter_rust_bridge pinned to 2.12.0)
flutter_rust_bridge.yaml          codegen config
lib/main.dart                     RustLib.init, then AppKit.run
lib/core/                         NotesCore (the interface), FrbNotesCore (over the generated binding), FakeNotesCore (in memory)
lib/coordination/                 the peer-layer hook and the sync engine (Dart: transport and policy)
lib/ui/, lib/logic/               the notepad's screen, list and autosaver, plus the history sheet
lib/src/rust/                     generated Dart binding (committed)
rust/                             the crate notes_core: src/{engine,store,sync,namespace,types,error}.rs, src/api/ (the bridge), tests/
rust/src/frb_generated.rs         generated (committed)
rust_builder/                     cargokit glue that builds ../rust for the macOS and Linux runners (vendored; MIT, see its LICENSE)
test/, integration_test/          widget and sync tests on the fake; the same contract and sync scenarios on the real core
tool/smoke.sh                     a 10 s headless-ish launch of the built macOS app
```

`rust_builder/cargokit` is copied unchanged from the Bozzetto UI, which copied it from [cargokit](https://github.com/irondash/cargokit) (MIT, Matej Knopp; its `LICENSE` is kept beside it). `flutter_rust_bridge` is MIT. The rest of the app is Apache-2.0 like the repository.

## Limits

* The Linux runner exists and is wired to the same glue; it was **not built or run**.
* **No fsync in the Storage Kit's `put`.** The core flushes the active pack before it moves a head, so a process kill (tested) and, as far as the operating system honours `fsync`, a power cut leave a readable store. macOS's `fsync` does not flush the drive's own cache; that was not tested.
* No delete, garbage collection or quota in the Storage Kit: versions and unused blocks accumulate. A peer can fill the disk with valid blocks it was not asked for.
* History from a peer arrives as manifests only; an old version's body is "not on this copy" until its blocks arrive another way.
* The part protocol has no acknowledgement and no replay (the Kit has none); a lost reply is repaired by the next digest.
* Hot reload was not tested.

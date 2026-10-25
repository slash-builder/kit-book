# stopwatch

A stopwatch with laps and a countdown. Its state is a point in time plus banked time, saved on every change, so it tests the state directory, settings, and a clean quit and relaunch. With peers it shares **one countdown between copies** and announces "timer finished" from one copy.

| | |
|---|---|
| Manifest id | `dev.demo.stopwatch` |
| Kits in `app.json` | `venue`, `peers` (`venue` is a label; only `peers` is checked today) |
| Tests | 49 |
| `lib/main.dart` | 10 lines |
| Code the app wrote because the Kit lacked it | 35 lines in `lib/kit_gaps/notifier.dart` (a desktop notification, which the Kit should not own); `lib/coordination/` (332 lines) is the shared-countdown rule |

## What it exercises

* The state directory and settings file; `ctx.onClose` to save; the exit path.
* Test isolation: the "start, lap, relaunch" test is two opens on one scratch directory.
* `ctx.startPeers`, `PeerJson`, `PeersIndicator`, `NotesBanner`, `ModeBadge`.

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the App Context Kit is private).

```sh
make run APP=stopwatch

cd apps/stopwatch
flutter test                           # 49 tests
```

This app is **not sandboxed**, so `/tmp` paths work. That makes it the one to use for [running two copies and watching them find each other](../../book/20-guides/demo-apps.md#run-two-copies-and-watch-them-find-each-other): `tool/peer_probe.dart` runs the app's real coordination code over loopback without a window.

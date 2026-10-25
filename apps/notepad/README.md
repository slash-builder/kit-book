# notepad

One JSON file per note in the data directory, autosave 600 ms after the last keystroke, damaged-file handling, and a close hook that saves unsaved typing on quit. With peers it **syncs notes between copies**, including conflicts and notes too large for one message. It is the heaviest user of the Kit's coordination hook.

| | |
|---|---|
| Manifest id | `com.slashbuilder.demo.notepad` |
| Kits in `app.json` | `peers` |
| Tests | 63 |
| `lib/main.dart` | 5 lines |
| Code the app wrote because the Kit lacked it | 79 lines in `lib/kit_gaps/blob_pull.dart` (chunked transfer); `lib/coordination/` (619 lines) is the sync engine |

## What it exercises

* The data directory, `ctx.dataJson('sync.json')` and `AppJsonFile` for atomic JSON files; `SessionSettings`.
* `ctx.onClose` to flush the last keystrokes.
* `ctx.startPeers`, `PeerJson`, `PeersIndicator`, `NotesBanner`, `ModeBadge`.
* Version vectors, conflict copies and a digest exchange on top of the hook (the app's code, not the Kit's).

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the App Context Kit is private).

```sh
make run APP=notepad

cd apps/notepad
flutter test                           # 63 tests
```

Two copies need different `APP_CONTEXT_DEVICE` values: notepad refuses a peer with its own device id, because two copies with one device id share one notes folder and are one replica. `tool/peer_probe.dart` runs two copies without a window; see [the demo apps guide](../../book/20-guides/demo-apps.md#notepad). The app is sandboxed on macOS.

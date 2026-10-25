# minesweeper

Minesweeper with a saved game, high scores and two settings. With the peer layer it can **hand a game to another copy of itself**, or play one board together. It is the case where a state change has to happen on two sides.

| | |
|---|---|
| Manifest id | `dev.demo.minesweeper` |
| Kits in `app.json` | `peers` |
| Tests | 86 |
| `lib/main.dart` | 5 lines |
| Code the app wrote because the Kit lacked it | none in `lib/kit_gaps/`; `lib/coordination/` (329 lines) is the game protocol and stays the app's |

## What it exercises

* The data directory and `AppJsonFile` for the saved game and scores; `SessionSettings` for the settings.
* `ctx.startPeers` to find and connect to other copies; `PeerJson` for message bodies; `PeersIndicator` for "This copy / Peers: N".
* A hand-off protocol built on the Kit's five-method hook: the offer, the person's yes or no, the pull of the board, the confirmation, and checks that refuse anything inconsistent.

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the App Context Kit is private).

```sh
make run APP=minesweeper

cd apps/minesweeper
flutter test                           # 86 tests
```

To exercise the hand-off without a window, `tool/peer_probe.dart` runs the app's own coordination code over the real loopback provider; the commands are in [the demo apps guide](../../book/20-guides/demo-apps.md#minesweeper). The app is sandboxed on macOS, so two copies that should find each other need paths inside the app's container; the same guide explains how.

# launcher

Lists the apps that are running on this machine, which tests whether **a file-based presence list (the roster) is enough**. Each running copy writes a presence file; the launcher reads them.

| | |
|---|---|
| Manifest id | `dev.demo.launcher` |
| Kits in `app.json` | `venue` |
| Tests | 24 |
| `lib/main.dart` | 9 lines |
| Code the app wrote because the Kit lacked it | 50 lines in `lib/kit_gaps/`: `manifest_scan.dart` (finds installed apps) and `pid_alive.dart` (asks the operating system whether a process is alive) |

## What it exercises

* `Roster.scan()` and `RosterRecord` (status `live`, `stale` or `unreadable`); the instance id in the file name, so two copies of one app are two rows.
* `ctx.venue.nodes()` for the node strip, settings, and scratch isolation for the tests.

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the Application Kit is private).

```sh
make run APP=launcher

cd apps/launcher
LAUNCHER_APPS_DIR="$PWD/.." flutter run -d macos   # also lists the manifests in apps/*/app.json (-d linux on Linux)
flutter test                                       # 24 tests
```

The launcher is not sandboxed. It sees an app only if that app writes its presence file to the same roster directory, so to see apps in it, run the unsandboxed ones (stopwatch, render-queue) with the same `APPKIT_ROSTER_DIR`. `tool/rows_probe.dart` prints the rows the launcher would show for a roster directory; the walkthrough is in [the demo apps guide](../../book/20-guides/demo-apps.md#launcher).

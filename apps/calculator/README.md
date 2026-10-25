# calculator

A four-function calculator with no stored state. It exists to find the **least an app can ask of the App Context Kit**: if the Kit is nearly free here, the Kit is not in the way.

| | |
|---|---|
| Manifest id | `com.slashbuilder.demo.calc` |
| Kits in `app.json` | none |
| Tests | 32 |
| `lib/main.dart` | 5 lines |
| Code the app wrote because the Kit lacked it | none (`lib/kit_gaps/` does not exist) |

## What it exercises

* `AppContextKit.run` loading `app.json` and closing the app once on window close, quit, SIGINT or SIGTERM.
* `AppContextScope` supplying the app name for the title.
* `ModeBadge` showing the mock and scratch chip.
* `pumpKitApp` in the tests, which runs the app in mock mode under a scratch directory so no test touches real files.

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the App Context Kit is private).

```sh
make app APP=calculator          # debug build for this computer
make run APP=calculator          # run it

cd apps/calculator
CALC_MODE=mock flutter run -d macos    # shows a "mock" chip in the app bar (use -d linux on Linux)
flutter test                           # 32 tests
```

The calculator is sandboxed on macOS. How environment variables and the sandbox interact is in [the demo apps guide](../../book/20-guides/demo-apps.md#running-and-testing-any-app).

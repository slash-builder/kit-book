# render-queue

A queue of jobs that each take a **hold** on a resource broker (the Venue, a provisional name), run, and release it. It tests what an app does when the broker refuses, makes it wait, or loses the app: a killed app keeps its hold until the lease runs out.

| | |
|---|---|
| Manifest id | `dev.demo.render-queue` |
| Kits in `app.json` | `venue` |
| Tests | 38 passed, 5 skipped |
| `lib/main.dart` | 11 lines |
| Code the app wrote because the Kit lacked it | none; the app keeps the policy (wait or fail fast) and the words the person reads |

## What it exercises

* The session that hides "real", "absent" and "fake" brokers, and `ctx.venue.withHoldWaiting` (retry a refusal for up to `maxWait`, with cancel).
* Typed refusals, the settings file, and `ctx.onClose` cancelling running jobs and waiting for their holds to be released before the session closes.
* The roster scan, used to tell whether another copy of the app is running.

## Run and test

From the repository root, once: `make setup` (add `KITS=all` while the Application Kit is private).

```sh
make run APP=render-queue

cd apps/render-queue
RENDER_QUEUE_MODE=mock flutter run -d macos   # an in-memory broker that grants 2 holds at once (-d linux on Linux)
flutter test                                  # 38 passed, 5 skipped
```

With no broker token configured, real mode uses a local session with no limit and the app says so. The five skipped tests need a running broker daemon and skip themselves unless `VENUE_TOKEN_FILE` is set; the daemon is not part of this repository. Its settings are in `config.json`: `policy` (`wait` or `failFast`), `maxWaitSeconds`, `retrySeconds` and `leaseSeconds`.

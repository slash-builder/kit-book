# Fitting the App Context Kit to other Kits

The App Context Kit (the name is provisional) is the root namespace for one running app: identity, directories, settings, a session with a resource broker (the Venue, also a provisional name), and a way for copies of the same app to find each other. It is not the only Kit an app touches. During its first round of work, six neighbours were probed to find out where the App Context Kit's design meets theirs.

This page records, for each one: the question, what was built, what it showed, what the App Context Kit does about it, and what is still open and with whom.

How to read the evidence:

* **The probes run in a private repository; the public-safe summary is here.** Each probe was a standalone Rust package that exercised a neighbouring Kit directly. You cannot rebuild them from this repository, and this page does not point at them. The numbers below were measured when the page was written.
* **None of this is inside a demo app.** No Flutter app calls the Rust App Context Kit crate or any of these Kits through a bridge, so "works in a probe" is not "works in an app". See [what the demo apps do not cover](demo-apps.md#what-the-demo-apps-do-not-cover).
* The one piece that lives in this repository is [`labs/interface_candidates`](../../labs/interface_candidates/README.md), the proposed shared UI components. Nothing in the Kit's own packages depends on it.
* Numbers come from debug builds on one machine, usually single runs. Latencies are to show magnitude, not to rank anything.
* Where a page below says "tested", it was tested while this page was written. Anything else is from the project's own notes and says so.

## Summary

| Kit | What we tried | Result | Status |
|---|---|---|---|
| Hearth (transport) | Carry traffic between copies of one app, on one account, through a real local Hearth hub. | Works on the stock hub with the app id carried in the message type. App-scoped topics need a change to the hub's topic rules. Usable payload is 64 KiB minus the header. | Adapter prototype (private). No Hearth provider in the Kit. Waiting on a protocol ruling. |
| Message Kit | Map the Kit's coordination envelope onto Message Kit, locally and across a remote-provider seam. | The envelope fits without bending either side. The local transport needs Linux. Same-machine peers on macOS and Windows use the Kit's loopback provider. | Prototype (private). The Kit ships a fake and a loopback provider only. |
| Storage Kit | Keep a note body in a per-account, per-app partition and sync it between two copies. | A 37-byte insert into a 10 MiB note transferred 0.47% of the body. Tamper rejection works. Several Storage Kit gaps. | Prototype (private). Not part of the Kit. |
| Identity Kit | Decide with Identity Kit capabilities whether a peer may join an app's coordination. | The admit / read-only / reject shape maps cleanly. | Prototype with a test double. Waiting on Identity Kit issuance and signing. |
| Interface Kit (candidates) | Derive shared UI components from what six demo apps and a larger app each wrote by hand. | Nine entries built (158 tests). Four are marked thin: one real user in the demo apps, or none. | Candidates only, in [`labs/interface_candidates`](../../labs/interface_candidates/README.md). Nothing promoted to the real Interface Kit. |
| Venue | A Venue session in the app context. | Works against a real daemon in Dart and Rust. Typed refusals, lease-loss reporting and a wait helper (Dart) exist. Registering an app is manual. | Shipped in the Kit. |

## Hearth (transport)

**The question.** Hearth is SlashBuilder's messaging protocol, with a hub that fans messages out to devices on an account. Can the App Context Kit use it to carry traffic between copies of one app, using topics scoped to the app?

**What was built.** A prototype adapter, `HearthTransport`: `join(account, app, device)`, then `broadcast`, `send(device, bytes)`, `recv`, `leave`. It validates ids before anything reaches the wire. It came with 53 tests in eight files (topics, delivery, isolation, presence, request/reply, payload, catch-up, adapter), run against a **real local hub** and Redis on loopback ports, plus a **patched copy of the hub** whose topic module changed by about 60 lines. Nothing touched a production service.

Re-run when this page was written: 53 passed, 0 failed (with the 90-second idle-timeout test skipped).

**What it showed.**

* **The stock hub rejects app-scoped topics.** `account/<id>/app/<app>/...` gets `TOPIC_INVALID` on subscribe and publish. The hub's topic grammar is a closed list of four shapes. The patch adds two. Until the protocol's topic naming is amended, the adapter carries app traffic on the existing broadcast and device topics, marks each message `payload_type = ak.app/<app>`, and filters at the receiver.
* **The usable payload is 64 KiB minus the Kit's header.** Re-run: a 65,536-byte payload was delivered intact; 65,537 bytes was refused with `ENVELOPE_TOO_LARGE` and the connection survived. The 1 MiB figure is the cap on the whole envelope; above it the hub closes the connection without an error.
* **The hub does things the Kit must handle itself.** It echoes a broadcast back to the sender. Its message id is not a safe correlation key: 1 of 40 replies was already buffered before the requester's own publish receipt. Subscribing and then catching up can deliver the same message live and in the catch-up page, so de-duplicate on message id. A copy that goes silent with its socket open is noticed only after the hub's 90-second idle timeout; a killed copy is reported offline in under a millisecond.
* **Rate limits matter for liveness.** On one connection, 10 of 25 rapid publishes were accepted (limit 10 per second). Hourly caps of 600 per connection and 6,000 per account were read in the hub's code, not measured. By that arithmetic a heartbeat every 30 s uses 20% of one connection's hourly cap, and every 5 s exceeds it.
* **Ordering holds per sender only.** 200 messages from one sender arrived 200 of 200, in order. Four concurrent senders kept their own order, but arrival order across senders disagreed with message-id order.
* **Loopback latency is small.** Publish to peer receipt: p50 about 1.4 ms, p95 about 2 ms (60 samples, debug build, one machine).
* **Catch-up paging can skip messages.** Paging by a millisecond timestamp with a strict comparison skips messages that share a millisecond across a page boundary. With five synchronized senders and one message per page, a run recovered 9 of 40 messages; an earlier run recovered 10 of 40. The count depends on timing.
* **A retention field means two things.** The hub reads field 5 of the publish message as a "do not retain" flag. The published schema and the client SDK call it a retention class. An explicit "history" class is silently not stored.

**What the App Context Kit does because of it.**

* The peer layer has a provider interface (discover, connect, send, inbound stream). The Kit ships a fake provider and a loopback provider. **There is no Hearth provider yet.**
* Payload limits differ by provider, so a provider has to declare its own maximum and `send` has to fail before the wire when it is exceeded. The App Context Kit's specification says so (section 6.2). **Not built:** today the app passes the limit to `PeerJson` (for Hearth: 64 KiB minus the header).
* The Kit's own envelope carries a Kit-owned correlation id and `from.device` plus `from.instance`, which is how echo is suppressed. What a Hearth provider must still add: request deadlines, de-duplication across live delivery and catch-up, a `no_retain` heartbeat no more often than every 30 s, and reconnect.

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| Amend the protocol's topic naming for app-scoped topics (or decide to stay on the shared topics). | The protocol owners |
| The retention field mismatch, the catch-up paging cursor, and the missing unsubscribe in the hub. | The protocol owners |
| The Fabric Kit SDK exposes no catch-up, presence or unsubscribe, and does not reconnect. The prototype used a raw wire client for those. | The Fabric Kit's maintainers |
| Not tested: a remote hub, TLS, paired-device connections, and the Dart peer code against a real hub (only the Rust adapter ran). | The App Context Kit's maintainers |

## Message Kit

**The question.** The Kit's coordination envelope is `{account, app, channel, from, seq, kind}` plus an opaque, app-owned payload. Can Message Kit carry it between processes on one machine, and across its remote-provider seam to another machine?

**What was built.** A mapping of the envelope inside a Message Kit frame (19 mapping tests), a small peer process for local exchange tests (6 tests), a TCP provider of under 200 lines through the remote seam (4 tests), and a test of an oversize message (1 test).

**What it showed.**

* **The envelope fits without bending either side.** The whole Kit message goes inside one Message Kit payload. One header works for Message Kit and for Hearth, with two mappings. They differ in who acknowledges a publish, whether a peer can send a directed message, size limits, rates, retention, and echo.

  | | Message Kit, local | Hearth |
  |---|---|---|
  | Largest message | about 200 KiB with default socket buffers (204,800 bytes sent; 212,992 failed) | 64 KiB including the Kit header |
  | Round trip | p50 about 70 microseconds (1,000 requests, two processes, container, debug build) | about 2 ms, hub on loopback |
  | Echo to the sender | none | yes, suppress by `from` |
* **The local transport is Linux-only.** It uses `AF_UNIX` with `SOCK_SEQPACKET`, which the macOS kernel does not implement. Checked here: creating such a socket on macOS fails with "Protocol not supported" (`Errno 43`). Windows is also out: the local bus code is compiled for Linux and Android only (read in Message Kit's source; not run on Windows). So **same-machine peers on macOS and Windows use the Kit's loopback provider**, which is plain TCP on `127.0.0.1`.
* **On macOS the integration tests pass without testing anything.** Re-run on macOS: 19 mapping tests passed, and the 11 integration tests print `SKIP ... local bus unavailable` and report "passed". Read the SKIP lines, not the totals. In a Linux container the same 30 tests ran with none skipped and all passed.
* **What Message Kit cannot express today:** an application answer inside a reply message; local fan-out to several receivers; a caller-chosen socket path; a configurable request timeout; and anything on macOS or iOS.
* **The remote seam has gaps.** Several were found and reported to the Kit's maintainers.

**What the App Context Kit does because of it.**

* It ships the loopback provider for same-machine peers, so macOS and Windows do not wait on Message Kit.
* The envelope header needs additions, tracked in the specification: an `in_reply_to` correlation field, a `to` field for directed messages, a per-message retain hint, and a provider-declared maximum payload checked before the wire. The Dart core already has a request id (`rid`, kind `kit.reply`) for correlation.
* A Message Kit provider is not built.

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| Whether `seq` is per link, restarting at 1 (the Dart core), or one counter per sender (the Rust prototype). | The App Context Kit's maintainers (a specification decision) |
| Whether `kind` is a closed enum (Rust prototype) or `kit.`-prefixed strings (Dart core). | The App Context Kit's maintainers (a specification decision) |
| The remote-provider seam gaps, an error code for an app-level refusal, an unreachable-endpoint code, and a caller-chosen socket path. | The protocol owners |
| Not tested: a real Hearth hub behind the provider, real LAN discovery, release builds. | The App Context Kit's maintainers |

## Storage Kit

**The question.** Storage Kit is content-addressed storage. The App Context Kit names an app by `(account, app id)`. Can that name also name the app's slice of storage, and is syncing a note between two copies cheap when only a little of it changed?

**What was built.** A mapping from `(account, app id)` to a storage partition, so copies of one app on one account share a partition and different accounts never do; a notes model on that partition; and copy-to-copy sync. The "wire" was an in-process call, so this measured bytes and blocks, not network time. Conflict handling used manifest ancestry. The Kit never merges: the app's resolver chooses between keep-local, take-remote, merged, or defer.

**What it showed.** Re-run when this page was written, 10 MiB pseudo-random body, two contexts, debug build:

| Step | Blocks sent | Bytes | Share of the body |
|---|---|---|---|
| Cold sync to the second copy | 544 | 10,507,722 | 100.21% |
| Insert 37 bytes in the middle | 3 | 49,249 | 0.47% |

The 3 blocks are one manifest, the rewritten list node (about 25 KiB), and the one chunk that changed. 541 blocks were already present. The list node is the floor for any edit to a large body.

Also tested: identical bodies under two names store one set of chunks; each of the 10 blocks of one version, corrupted in turn, was rejected and the old body still read back.

**What the App Context Kit does because of it.** Nothing yet in the Kit. The findings point at three changes to the Kit's directory model, none made:

* Reserve names under `data` for the block store (a convention, not a sixth directory kind).
* Add an account dimension. The specification's section 6 uses `(account, app id)` as the scope, but the Kit's directories are per operating-system user, not per account.
* Quotas cannot be enforced until Storage Kit can delete.

**Gaps in Storage Kit** (for its maintainers): no insert that verifies a hash before filing the bytes, so a receiver must hash first; no way to list a list node's children from a half-synced tree; no mutable head; no delete, garbage collection or quota; compression hides the payload from a sync; the async API has no chunking; heavy dependencies are always built (about 327 packages).

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| The gaps above. | The Storage Kit's maintainers |
| Account dimension and reserved directory names in the Kit. | The App Context Kit's maintainers |
| Not tested: a real network, two processes on one partition, crash safety (reasoned only), the S3 and HTTP backends. | The App Context Kit's maintainers |

## Identity Kit

**The question.** Identity Kit has service principals with scopes. Can the App Context Kit's `admit(peer, hello)` hook use them to decide whether a peer may join an app's coordination: accept, accept read-only, or reject?

**What was built.** An `admit` module with scopes `app:<id>:run`, `app:<id>:coordinate` and `app:<id>:storage`. `coordinate` is accept, `run` alone is read-only, `storage` alone is refused. An in-memory fake issuer stood in for issuance, which Identity Kit does not have yet. The fake is a test double, not a design for the real one.

**What it showed.**

* **The shape works.** A program that only types an app id is refused. One app's principal cannot join another app. A principal from another account is refused. A household rule (a child account may not run a given app) can be checked at each join, so changing a role takes effect without reissuing anything. Identity Kit keeps role out of the principal on purpose, so that rule can only live in whoever verifies.
* **Gaps in Identity Kit:** issuance, signing and verification are not built; the principal carries no account; scopes are opaque strings with no constructor or parser; the family graph is not built, so the role rule cannot read real roles.

**What the App Context Kit does because of it.** The Kit's only authenticators are an open one that accepts everyone and a shared-secret one marked as a test fake, and the code says plainly that they are for one machine and tests, never a network. The loopback provider has no encryption or authentication; do not use it across a trust boundary. A real authenticator waits on Identity Kit issuance and signing. Until then the App Context Kit scopes copies by account and app id as a naming convention and does not authenticate them: do not treat peers as trusted.

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| Issuance, signing and verification, and the lifecycle of a capability after it is issued. | The Identity Kit's maintainers |
| Where a principal travels in the coordination envelope. `admit(peer, hello)` has no slot for one today. | The protocol owners and the Identity Kit's maintainers |
| Account in the principal; the family graph. | The Identity Kit's maintainers |

## Interface Kit (candidates)

**The question.** Six demo apps and a larger production app each wrote the same UI pieces by hand. Which pieces are shared enough to belong in the Interface Kit?

**What was built.** [`labs/interface_candidates`](../../labs/interface_candidates/README.md): small, plain-Material components derived from what the apps duplicate. This is **not** the Interface Kit. The real Kit is untouched and nothing here is published. Every colour and text style comes from the ambient `Theme`, so the components can later be mapped onto the real design system. The package's README lists the accessibility contract that the tests enforce.

Re-run when this page was written: `flutter test` in that package, 158 passed (`make test-fast` runs it).

**What it showed.** The catalog's table has nine entries. Use in the demo apps, counted from the apps' source:

| Component | Demo apps using it | Marked THIN? |
|---|---|---|
| `PageScaffold` | 5 of 6 | no |
| `EmptyState` | 3 | no |
| `StatusBanner` | 2 | no |
| `AsyncStateView` (with `LoadingView`, `ErrorView`) | 1 | no (strong support from the larger app) |
| `confirmDialog` and `promptDialog` | 1 | yes |
| `SaveStatusChip` | 1 | yes |
| `StatusDotRow` | 0 (tried in one app and reverted) | yes |
| `showToast` | 0 (four apps wanted one; none built one) | no (strong support from the larger app) |
| `relativeTime` | 0 | yes |

The catalog marks four entries THIN: fewer than three real users, so a candidate rather than a recommendation. The rule for promotion is that at least three real screens duplicate the piece and it needs nothing from the app.

Two attempts were reverted, per the project's notes (not re-run): `EmptyState` in the minesweeper demo (three one-line rows grew from 20 to 72 dp each) and `StatusDotRow` in the launcher (it worked, but turned a scannable table into a list; a design call).

No screen reader was run. The accessibility checks are semantics-tree and guideline tests.

**What the App Context Kit does because of it.** The core package stays free of Flutter. The Flutter companion carries `ModeBadge`, `NotesBanner` and the exit coordinator. The candidates stay in their own package. The Kit's notes carry a severity (info, warning, error) so a banner can pick its style.

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| Which candidates, if any, are promoted, and mapping them onto the design system's tokens. | The Interface Kit's maintainers and the design system's owners |
| The THIN components need a second or third real user before promotion. | The Interface Kit's maintainers |
| Design calls such as dot rows versus tables, and tabs in the page scaffold. | The design owners |

## Venue

**The question.** Can an app hold a reservation on a shared machine the same way whether Venue is real, absent or faked?

**What was built.** A session type in both languages (Dart and Rust) and the render-queue demo app, which uses it harder than the others.

**What it showed.** The session hides the three cases. It also showed what the Kit's first version got wrong: the daemon's refusal for a live-hold limit was mistyped as "unavailable"; a failed lease renewal was swallowed; apps had no way to find holds left by a crash; and every app that could be refused wrote the same wait-and-retry loop. All four are addressed in the Dart Kit (the wait helper is not in the Rust Kit). What remains needs changes in Venue itself.

**What the App Context Kit does because of it.** Typed refusals, `holds()`, lease-loss reporting and `withHoldWaiting` (Dart). Registering an app with a daemon is still four manual steps that need an operator with authority. The [render-queue](../../apps/render-queue/README.md) demo app and the [demo apps guide](demo-apps.md#render-queue) show the session in use; the full story, with code and measurements, is in the App Context Kit's Venue guide.

**What is still open, and who owns it.**

| Open | Owner |
|---|---|
| A machine-readable reason for the live-hold limit, a wait queue or push, and a small typed client library. | The Venue Kit's maintainers |
| A provisioning step for new apps, and a manifest declaration of contract classes. | Undecided; the App Context Kit's maintainers |
| A Rust `with_hold_waiting`. | The App Context Kit's maintainers |

## Cross-cutting

Three themes recur across the probes.

1. **Most of what makes the Kit hard lives in the other Kits.** The Kit's own part (find, connect, route) held on the first try in three very different apps. The gaps were payload limits, topic grammar, identity and signing, and storage lifecycle.
2. **App identity is a naming convention until the Identity Kit issues and verifies capabilities.** Hearth, Storage Kit and Identity Kit each showed a different face of the same fact.
3. **Build a shared piece when the second app copies it, not before.** The same rule decided what moved into the Kit (a wait helper, JSON helpers, a peers handle) and what stayed out (single-user helpers).

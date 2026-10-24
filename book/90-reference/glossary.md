# Glossary

The words these pages use, in alphabetical order. The names *Application Kit* and *Venue* are provisional.

**Admit.** The hook method that decides whether a peer may join an app's coordination: accept, accept read-only, or reject.

**App id.** An app's reverse-DNS name, such as `dev.demo.notepad`, set in its manifest.

**Application Kit.** The Kit that is the root namespace for one running app: identity, directories, settings, modes, a roster entry, a session with a resource broker, and an opt-in way to find other copies of the app. The name is provisional.

**Candidate.** A UI component proposed for the shared interface Kit, built from what several apps duplicate. See [`labs/interface_candidates`](../../labs/interface_candidates/README.md). A candidate marked **THIN** has fewer than three real users.

**Context.** What an app receives from the Application Kit when it starts: its directories, settings, notes for the person, session and peers. In Flutter, `AppContextScope.of(context)`.

**Core (role).** In `kits.lock`, a Kit this book documents and whose own tests run in `make test`. The other roles are **app-dep** (needed by another Kit to build; fetched, not tested here) and **reference** (documented but not needed to build the apps).

**Fetch.** Downloading a Kit at its pinned commit into `.kits/` with `make setup` or `make fetch`. No git is needed.

**Hold.** A reservation on a shared machine's resources, taken from the Venue for the length of a job and released afterwards. A hold lasts for a **lease**; a crashed app keeps its hold until the lease runs out.

**Hook.** The five small methods an app supplies to say what coordination means for that app: `channel`, `hello`, `admit`, `onPeer` and `onMessage`. The Application Kit finds and connects copies and routes messages; it never reads a payload.

**Kit.** A focused piece of SlashBuilder's platform that owns one job. See the [introduction](../00-introduction.md).

**Kit gap.** Code an app wrote itself because a Kit lacked it. By rule it lives in the app's `lib/kit_gaps/` with a `// KIT GAP:` comment, and the line count of those folders measures what the Kits are missing.

**Manifest.** An app's `app.json`: id, name, version, the Kit features it uses and its Venue settings.

**Mock mode.** A mode, switched on with `APPKIT_MODE=mock`, in which the outside world is replaced by in-memory fakes. Together with **scratch mode** (`APPKIT_SCRATCH=<dir>`, which puts every directory under one folder) it lets tests run without touching real files.

**Peer.** Another copy of the same app, on the same account, that the Application Kit found and connected to.

**Pin.** The commit of a Kit that this repository uses, recorded in `kits.lock`. `make lock` shows how to move it.

**Probe.** A small program that exercises one thing and prints what happened. The apps' `tool/` folders hold probes that run an app's own coordination code without a window. Probes of other Kits run in a private repository; the book carries only a summary.

**Refusal.** A typed answer from the Venue saying it will not grant a hold, for example because the app already holds its limit.

**Roster.** The set of presence files, one per running copy of an app, that lets apps (and the launcher demo) see who else is running on the machine.

**Venue.** The resource broker: a daemon that grants and tracks holds on a machine's resources. The name is provisional.

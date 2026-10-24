# Contributing

Thank you for helping. This repository is a book plus demo apps; most changes are to a page, an app, or a script in `tools/`.

## Before you send a change

Run these from the repository root. They are the same checks the CI job runs.

```sh
make docs          # every relative link and heading anchor in the book and README files
make check-public  # nothing that must not be public: names, paths, ids, secrets
make test-fast     # every test (run make setup first; add KITS=all while some Kits are private)
make lint          # analyse the Dart code, then the two checks above
```

## Maintainer notes: the Kit catalog

`book/30-kits/` is **generated** from the Kit registry, which lives in a private repository, and the generated pages are committed so readers never need the registry. Do not edit those pages by hand: the next regeneration overwrites them. To change a card, change the registry entry and regenerate.

```sh
python3 -m pip install pyyaml     # only the generator needs it; make docs and make test-fast do not
make docs-catalog REGISTRY=/path/to/kits.yaml REGISTRY_COMMIT=<registry commit>
make test-tools                   # the generator's own tests
```

* `make docs-catalog` asks GitHub (`gh`) which repositories are public, records the answer in `tools/kit-visibility.tsv`, and links a repository only if it is public. Add `OFFLINE=1` to reuse the file without calling GitHub. Commit the file with the pages.
* The generator drops, rather than rewords, any registry sentence that names people, roles, agents, tickets, hostnames, paths, notes-vault pages, Jira or dates, and it refuses to write a page that still matches. If a card looks thin, the registry entry is thin; fix it there. Do not weaken the sanitiser to make a card longer.
* A new Kit, a renamed Kit or a changed status needs no edit here beyond regenerating. Read the diff: it is the review.

## Maintainer notes: the Kits' reference pages

Each Kit keeps its reference documentation with its code. The book **pulls** it at build time and **commits** the result, so a reader never needs the Kit's repository (some are private) or `make setup` to read it. Pulled pages are generated: do not edit them here. A wrong sentence in a pulled page is fixed in the Kit, then re-pulled.

```sh
make setup KITS=all     # fetch the Kits at the commits kits.lock pins (KITS=all while some Kits are private)
make docs-pull          # copy their reference pages into book/, then run make docs and make check-public
make docs-pull-check    # no writes: fail if the committed pages differ from a fresh pull
make test-tools         # the puller's own tests need nothing but Python 3
```

* What is pulled for each Kit, where it lands, and in what order is `tools/docs-pull.conf`. Adding a Kit's docs is a new section there, then `make docs-pull`; a Kit in the registry lands in `book/30-kits/<slug>/reference/` and `make docs-catalog` then lists the pages on its card.
* The puller refuses to run when `.kits/<name>` is not the commit in `kits.lock`, so the book never mixes versions. After `make lock`, run `make setup KITS=all`, then `make docs-pull`, and commit the pin and the pages together.
* Links in pulled pages are rewritten (to the pulled copy, to plain text for a private Kit, to a GitHub address at the pinned commit for a public one); the rules are in [Make targets](book/90-reference/make-targets.md#docs-pull). The tool prints a warning for a link the Kit itself has wrong. Fix those in the Kit.
* Pulled pages are public text, so they are scanned by `make check-public` like everything else. If they hit, the Kit's text is the problem; fix it there. Do not weaken the scan.
* Pulled pages are not edited for the book's context. If a page says "this repository" and means the Kit's, or points at the demo apps in a way that reads oddly here, raise it with the Kit.

## Rules for what you write

* **This repository is public.** Do not put internal hostnames, ticket ids, local file paths that contain a user name, notes-vault paths, or the names of people (other than the author in the credit line) in any file. `make check-public` finds the common cases; it cannot find them all, so read your own diff.
* **Do not describe security-relevant defects of other systems.** If you found one, report it to the owners of that system privately.
* **Say where a number came from** (what was run, on what, when). Say "not tested" when something was not tested.
* **Names that are provisional stay marked.** The Application Kit and the Venue (a resource broker) are provisional names; say so once where they first appear on a page.
* **Page names are stable.** Link to sections by their headings. `make docs` checks the links.
* **Code samples copied from a file** can be marked with `copied-from=<path>` after the language on the opening fence; `make docs` then checks the sample still matches the file.

## Rules for the apps

An app does not edit a Kit. If an app needs something a Kit lacks, it writes it under `lib/kit_gaps/` with a `// KIT GAP:` comment; the size of those folders is the measurement of what the Kits are missing. The Kits are downloaded into `.kits/` and are never edited there.

## Moving a Kit pin

Run `make lock` (or `make lock KIT=<name>`). It shows what would change and asks before rewriting `kits.lock`. Then run `make setup` and `make test-fast`, and send the new `kits.lock` only if both are green.

## Licensing of contributions

Your contribution is licensed under the licence of the part you change: documentation under CC BY 4.0, code and tooling under the Apache License 2.0 (see [README.md](README.md#licence)).

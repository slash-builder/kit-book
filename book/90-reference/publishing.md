# Publishing the website

The book is also a website, served at **https://kits.slashbuilder.com** from this same repository. This page says how the site is built and published, in what order the steps happen, and what is done by hand. The commands are described in [Make targets](make-targets.md#site).

## How the site is built

`make site` turns `book/` into a static website with [mdBook](https://rust-lang.github.io/mdBook/). The output is in `build/site/`; nothing in it is committed to `main`.

* **Links out of the book.** On GitHub a page can link to `apps/`, `labs/` or `CONTRIBUTING.md` with a relative path. On the website those paths do not exist, so the build rewrites them, in a staged copy, to the file or folder on GitHub. The number of rewritten links is printed. Links inside the book are untouched.
* **Diagrams.** The architecture diagrams are `mermaid` code blocks. GitHub draws them itself; on the website a pinned copy of the mermaid library, committed in [`tools/site/vendor/`](../../tools/site/vendor/README.md), draws them in the browser, in light or dark colours to match the page. The library is never fetched from the internet by the build or by a reader's browser.
* **Search** is mdBook's built-in search: it runs in the browser from an index in the site.
* **Not indexed yet.** Until the site is announced, every page carries `<meta name="robots" content="noindex">`. `SITE_INDEXABLE=1` removes it.
* **Checks.** `make site-check` verifies the built site: every internal link and `#fragment` resolves, the files GitHub Pages needs are there, the robots tag matches `SITE_INDEXABLE`, and the vendored library is the file whose checksum is recorded.

Preview it locally with `python3 -m http.server -d build/site 8000`.

## How it is published

Publishing is **a branch, not a workflow**. The book does not use GitHub Actions (the Kits' own repositories do: each public Kit runs its tests there). `make publish-site` builds and checks the site, then commits the built files as a single new commit with no history to a branch named `gh-pages`, and GitHub Pages serves that branch ("Deploy from a branch"). The commit is made without checking anything out, so `main` and your working tree are never touched.

Two files are added to every published commit:

* **`CNAME`**, holding exactly the domain (`kits.slashbuilder.com`). With branch-based Pages, the custom domain lives in this file in the published branch. Because every publish replaces the whole branch, a publish without it would silently remove the custom domain from the site.
* **`.nojekyll`**, an empty file, so that Pages serves the files as they are and does not run its own site generator over them.

The push is a force push (every publish is a new root commit) guarded by `--force-with-lease`, and it happens only when `PUBLISH=1` is given **and** the repository is public. In every other case `make publish-site` builds the commit on a local `gh-pages` branch, prints what it would have pushed and exits successfully. Pages on the Free plan works only for public repositories, which is why a private repository is previewed locally.

## Before you publish

Run the gate first, as often as you like. It is read-only: it changes no file, no GitHub setting and no DNS record, and builds the website in a temporary copy.

```sh
make go-public-check
```

It prints one row per check (`ok`, `warn`, `FAIL`) and exits 1 while any row is `FAIL`. Every check is described in [Make targets](make-targets.md#go-public-check); what a failing row means and what clears it:

| Row says | What it means | What clears it |
|---|---|---|
| `a` strict scan fails | a file contains a name, path, id or secret that must not be public, or a `core` Kit in `kits.lock` is still private | fix the file (never weaken the scan); make the Kit public |
| `b` `kits.lock` rows | a URL does not end in the Kit's own name, the rename comment is still there, an old Kit spelling is left, or a pin is not 40 hex characters | do the [Kit rename switch](#the-kit-rename-and-the-pin) |
| `c` a core Kit does not answer 200 | the Kit's repository is private, does not exist, was moved (a redirect is not a 200), or its pinned commit is not in it | create or publish the Kit's repository, re-pin with `make lock KIT=<name>` |
| `d` docs or site | a link is broken, a pulled page is stale (`make docs-pull`), or the site does not build or check with `SITE_INDEXABLE=1` | fix the page; `make docs-pull`; install mdBook |
| `e` licences and notices | `LICENSE`, `LICENSE-docs` or `THIRD-PARTY-NOTICES.md` is missing, or the notices do not name the vendored mermaid version and checksum | regenerate the notices after upgrading the vendored script (`tools/gen-third-party-notices.py`) |
| `f` community files | a contact in `tools/contacts.conf` is empty (the files then carry the visible marker `[CONTACT NOT SET]`), or the files are not a fresh render | set `CONDUCT_CONTACT` and `SECURITY_CONTACT` in `tools/contacts.conf`, run `make community`, commit both files |
| `g` old Kit spelling | a tracked file still says `appkit`, `application_kit` or `application-kit` | change it, or, if the old name is the point of the sentence, allow that one line in `tools/go-public-allow.txt` with the reason (never `kits.lock`) |
| `h` visibility is `warn` | this repository is still private | make it public, then run the gate again; the row turns `ok` |
| `i` CNAME | the built site's `CNAME` is not `SITE_DOMAIN` | look at `SITE_DOMAIN` in the Makefile |
| `j` working tree or `kits.need` | uncommitted changes, another branch than `main`, or an app lists a Kit `kits.lock` does not know | commit; switch to `main`; fix the name |

A `warn` never fails the gate, but read it: some warnings are expected until the step they name is done (a private repository, a private `app-dep` Kit whose apps are then skipped for a stranger).

**The order of a launch.** Every step that makes something public is a decision by the owner at the time, not a build step.

1. **Before anything flips:** set the two contacts and commit the community files; make sure the notices match the vendored script; verify the domain for the organisation (step 1 below); run `make go-public-check` and read the table. The only rows allowed to be red are the ones the later steps clear: the Kit rename switch (`b`, `c`), the repository's visibility (`h`).
2. **Make the Kits public**, starting with the ones the book documents: create and publish each repository, then do the [rename switch](#the-kit-rename-and-the-pin) in `kits.lock` and re-pin.
3. **Make this repository public**, then `make go-public-check` again: every row should now be `ok`.
4. **Publish the site and switch Pages on, then add the DNS record last** (the steps below).
5. **Run the stranger test:** `make stranger-test` (preview with `STRANGER_DRY=1`) clones the public repository with no GitHub login and runs `make doctor`, `make setup` and `make test-fast` there. Apps that need a Kit that is still private must skip with a message, not fail. Fix whatever breaks before announcing.
6. Check every link in the announcement, then announce.

Each step has an undo (make the repository private again, remove the `gh-pages` branch, remove the DNS record), but **making something public and then private again does not unpublish copies, forks or caches**. The checks before the flip matter more than the rollback.

## Going public, in order

The order matters. Nothing before step 5 changes what the public sees.

1. **Verify the domain for the organisation** on GitHub (organisation settings, Pages, verified domains: add `slashbuilder.com`). GitHub shows a DNS TXT record to add at the DNS provider. This stops anyone else from claiming a name under the domain.
2. **Decide on indexing.** Leave `SITE_INDEXABLE=0` to publish a site that search engines are asked to ignore, or publish with `SITE_INDEXABLE=1` when the site is ready to be found.
3. **Make the repository public**, after `make go-public-check` shows no `FAIL` (the visibility row stays a warning until you do) and every Kit the book documents is public. This is a deliberate decision by the owner, not a build step.
4. **Publish:** `make publish-site PUBLISH=1`, from a clean `main`. Then in the repository settings, Pages: source **Deploy from a branch**, branch **`gh-pages`**, folder **`/ (root)`**. The custom domain field then shows the value read from the `CNAME` file; do not clear it.
5. **Add the DNS record last:** a `CNAME` record for `kits` pointing at the organisation's `github.io` name, set to DNS only (no proxy) so GitHub can issue the certificate. A name that points at GitHub before anything claims it is how subdomains get taken over, which is why the record comes after steps 1 and 4.
6. **When the certificate is ready** (Pages shows it), tick **Enforce HTTPS**.

## The Kit rename and the pin

The Application Kit was renamed **App Context Kit** before going public. Its repository, `slash-builder/app-context-kit`, was created from the reviewed release candidate: the candidate is one commit with no parents, pushed as it is, so the commit id the repository starts from is the commit id this book already pinned. [`kits.lock`](../../kits.lock) names that repository and that commit. Until the repository is public the line is marked `private`.

At release, before step 3 above:

1. Make `slash-builder/app-context-kit` public, then switch on what a private repository on the free plan cannot have: private vulnerability reporting, branch protection on `main`, and required reviewers on the `release` environment.
2. In `kits.lock`, mark the `app-context-kit` line `public`. If the release candidate had to change, re-pin (`make lock KIT=app-context-kit`) to the commit the repository starts from.
3. Run `make clean-all && make setup`, `make docs-pull`, `make docs` and `make check-public`. `make docs-catalog` then records the new repository's visibility.
4. Run `make go-public-check`. Rows `b1` to `b4` and `c1`, `c2` check this switch: they refuse a `kits.lock` URL that does not end in the Kit's name, a leftover rename comment, an old spelling, and a Kit whose repository or pinned commit does not answer HTTP 200 without a login. `tools/go-public-allow.txt` may never allow `kits.lock`.

## What is manual

Everything on the list above except building and committing: domain verification, making the repository public, switching Pages on and choosing the branch, the DNS record, and the HTTPS setting are all done by a person in the GitHub and DNS settings. The tools in this repository never change a GitHub setting or a DNS record, and neither do `make go-public-check` and `make stranger-test` (the second only clones).

To take the site down, remove the DNS record first, then switch Pages off.

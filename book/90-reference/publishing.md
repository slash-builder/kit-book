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

Publishing is **a branch, not a workflow**. This project does not use GitHub Actions. `make publish-site` builds and checks the site, then commits the built files as a single new commit with no history to a branch named `gh-pages`, and GitHub Pages serves that branch ("Deploy from a branch"). The commit is made without checking anything out, so `main` and your working tree are never touched.

Two files are added to every published commit:

* **`CNAME`**, holding exactly the domain (`kits.slashbuilder.com`). With branch-based Pages, the custom domain lives in this file in the published branch. Because every publish replaces the whole branch, a publish without it would silently remove the custom domain from the site.
* **`.nojekyll`**, an empty file, so that Pages serves the files as they are and does not run its own site generator over them.

The push is a force push (every publish is a new root commit) guarded by `--force-with-lease`, and it happens only when `PUBLISH=1` is given **and** the repository is public. In every other case `make publish-site` builds the commit on a local `gh-pages` branch, prints what it would have pushed and exits successfully. Pages on the Free plan works only for public repositories, which is why a private repository is previewed locally.

## Going public, in order

The order matters. Nothing before step 5 changes what the public sees.

1. **Verify the domain for the organisation** on GitHub (organisation settings, Pages, verified domains: add `slashbuilder.com`). GitHub shows a DNS TXT record to add at the DNS provider. This stops anyone else from claiming a name under the domain.
2. **Decide on indexing.** Leave `SITE_INDEXABLE=0` to publish a site that search engines are asked to ignore, or publish with `SITE_INDEXABLE=1` when the site is ready to be found.
3. **Make the repository public**, after `make check-public` and `make docs` pass and every Kit the book depends on is public. This is a deliberate decision by the owner, not a build step.
4. **Publish:** `make publish-site PUBLISH=1`, from a clean `main`. Then in the repository settings, Pages: source **Deploy from a branch**, branch **`gh-pages`**, folder **`/ (root)`**. The custom domain field then shows the value read from the `CNAME` file; do not clear it.
5. **Add the DNS record last:** a `CNAME` record for `kits` pointing at the organisation's `github.io` name, set to DNS only (no proxy) so GitHub can issue the certificate. A name that points at GitHub before anything claims it is how subdomains get taken over, which is why the record comes after steps 1 and 4.
6. **When the certificate is ready** (Pages shows it), tick **Enforce HTTPS**.

## The Kit rename and the pin

The Application Kit was renamed **App Context Kit** before going public. Its public repository, `slash-builder/app-context-kit`, does not exist yet; it is created at release time from the reviewed release candidate. Until then [`kits.lock`](../../kits.lock) names the Kit `app-context-kit` but keeps the address of the repository that exists today, `slash-builder/application-kit` on GitHub (private; the pinned commit is on its branch `public/release-prep`). That is deliberate: it keeps `make setup KITS=all` working now, and it is the only place that still says the old slug.

At release, before step 3 above:

1. Create `slash-builder/app-context-kit` from the release-candidate commit and make it public.
2. In `kits.lock`, change the address on the `app-context-kit` line to the new repository, `slash-builder/app-context-kit`, and re-pin to the commit the new repository starts from (`make lock KIT=app-context-kit`). The commit id changes because the new repository is a new history.
3. Run `make clean-all && make setup`, `make docs-pull`, `make docs` and `make check-public`. `make docs-catalog` then records the new repository's visibility. A check named `make go-public-check` is meant to refuse a release while a `kits.lock` URL still points at the old slug; it does not exist yet, so do this by hand: `grep application-kit kits.lock` must print nothing.

## What is manual

Everything on the list above except building and committing: domain verification, making the repository public, switching Pages on and choosing the branch, the DNS record, and the HTTPS setting are all done by a person in the GitHub and DNS settings. The tools in this repository never change a GitHub setting or a DNS record.

To take the site down, remove the DNS record first, then switch Pages off.

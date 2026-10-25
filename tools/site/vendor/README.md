# Vendored third-party files for the website

These files are copied, unmodified, into the website by `make site`. They are committed here so the site never loads
code from a CDN and the build never touches the network.

## mermaid

Draws the architecture diagrams (the `mermaid` code blocks in the pulled Kit pages) in the browser.

| | |
|---|---|
| Project | [mermaid](https://github.com/mermaid-js/mermaid) |
| Version | 12.2.0 |
| File | `mermaid.min.js` (the `dist/mermaid.min.js` of the npm package, unmodified; a single script that defines the global `mermaid`) |
| Fetched from | `https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz` over HTTPS, once, on 2026-10-24 |
| Tarball sha1 | `8500d2500a57bd10f0c8ab03ec4deff87df36c39` (equal to the `shasum` the npm registry publishes for this version) |
| Licence | MIT, in [`LICENSE-mermaid`](LICENSE-mermaid) |

The recorded checksums of the files in this folder (the format of `shasum -a 256 -c`):

```text
a8a6a6f805b074a8261a2825c86f99c8054acb3b35f50bb7e24a4f9f2c3c3b9f  mermaid.min.js
ec9fb67dcb25eccc416ed56e1aab819222c805a2a4bfe4cb19e7556bf2ffde80  LICENSE-mermaid
```

`make site-check` compares `mermaid.min.js` here, the copy in `build/site/` and the copy in `build/site-publish/`
with the first line above, and `make check-public` refuses to skip the file in its scan unless it still matches it.

The bundle also inlines mermaid's own dependencies (77 packages in all, with their transitive ones), each with its own licence.
They are listed one by one, with their licences, copyright notices and what was fetched to establish them, in
[`THIRD-PARTY-NOTICES.md`](../../../THIRD-PARTY-NOTICES.md) at the repository root. **Two of them are not plain permissive licences:**
`elkjs` is EPL-2.0 (a file-level copyleft licence that asks for a source-availability statement) and `dompurify` offers
MPL-2.0 or Apache-2.0 (this project takes Apache-2.0). That file says what each asks for. `make site` copies it into the site
root (`build/site/THIRD-PARTY-NOTICES.md`) and `make site-check` verifies the copy, so the notice travels with the script.

### Upgrading

1. Fetch the new tarball from the registry over HTTPS and check its sha1 against `https://registry.npmjs.org/mermaid/<version>` (`dist.shasum`).
2. Extract `package/dist/mermaid.min.js` and `package/LICENSE` from it. Replace the two files here.
3. Update the version, date, tarball sha1 and both checksums above, and the `MERMAID` and `LOCKFILE_URL` values at the top of `tools/gen-third-party-notices.py`.
4. Run `python3 tools/gen-third-party-notices.py` (it needs the network) to regenerate `THIRD-PARTY-NOTICES.md`, and read its "What needs attention" table: a new licence that is not MIT, ISC, BSD, Apache-2.0, 0BSD or CC0 is flagged there and needs a decision before the upgrade is committed. `make go-public-check` fails if the notices do not name the new version and checksum.
5. Run `make site` and `make site-check`, and open a page with a diagram (for example the App Context Kit's architecture page) in a browser, in the light and the dark theme.

Nothing else in `tools/site/` is third party. The code that draws the diagrams on the page is `tools/site/mermaid-init.js`.

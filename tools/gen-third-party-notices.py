#!/usr/bin/env python3
"""Regenerate THIRD-PARTY-NOTICES.md for the vendored tools/site/vendor/mermaid.min.js.  MAINTAINERS ONLY (needs the network).

    python3 tools/gen-third-party-notices.py [--out THIRD-PARTY-NOTICES.md]

What it does, in order, all over HTTPS:
  1. downloads the mermaid npm tarball named in tools/site/vendor/README.md and checks its sha1 against the registry;
  2. checks that dist/mermaid.min.js in it is byte-for-byte the vendored file;
  3. lists every package the bundle contains: the unminified build in the same tarball (dist/mermaid.js) keeps one
     "node_modules/.pnpm/<name>@<version>" comment per bundled file, which gives exact versions; plus the packages inlined
     through @mermaid-js/parser (a prebuilt dist, see PARSER_INLINED below);
  4. for each package fetches its registry metadata and tarball (sha1 checked), reads the licence identifier and the licence
     file, and records sha256 of what it fetched;
  5. writes the notices file: what needs attention, the component table, what was fetched, every distinct licence text once.

Nothing is written unless every download verified. Standard library only. The unit tests cover the pure functions.
"""
import argparse
import collections
import hashlib
import io
import json
import os
import re
import sys
import tarfile
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "tools", "site", "vendor")
REGISTRY = "https://registry.npmjs.org/"
MERMAID = ("mermaid", "12.2.0")
TODAY = "2026-10-24"
# The lockfile of the mermaid repository at the release tag. The npm tarball ships no lockfile; this one is the one the
# published bundle was built from, and it is what gives the versions of the packages below.
LOCKFILE_URL = "https://raw.githubusercontent.com/mermaid-js/mermaid/mermaid@12.2.0/pnpm-lock.yaml"
PARSER_PKG_URL = "https://raw.githubusercontent.com/mermaid-js/mermaid/mermaid@12.2.0/packages/parser/package.json"

# @mermaid-js/parser is bundled from its own prebuilt dist, which has already inlined its dev dependency langium and what that
# needs; esbuild keeps no per-file path comment for them, so they cannot be read from the bundle. They are listed from the
# dependency graph of langium 4.4.0 in the lockfile above (the highest patch version where the lockfile holds two). A listed
# package that tree-shaking removed would only make this list longer than the bundle, never shorter.
PARSER_INLINED = [
    ("@mermaid-js/parser", "2.0.1"), ("@chevrotain/types", "13.2.0"), ("chevrotain-allstar", "0.5.0"), ("langium", "4.4.0"),
    ("vscode-jsonrpc", "9.0.3"), ("vscode-languageserver", "10.1.1"), ("vscode-languageserver-protocol", "3.18.4"),
    ("vscode-languageserver-textdocument", "1.0.15"), ("vscode-languageserver-types", "3.18.4"), ("vscode-uri", "3.1.0"),
]
ALLOWED = {"MIT", "ISC", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "0BSD", "CC0-1.0"}
# Packages whose metadata or tarball lacks something; what was done about it is stated in the notices file.
NO_LICENCE_FILE = {"fastdom"}   # MIT per package.json; the text is the README's licence section (Wilson Page, 2016)

ATTENTION = """\
## What needs attention

Everything below is permissive (MIT, ISC, BSD-3-Clause, Apache-2.0) except one licence that is not on that list and one
that offers a choice. Read these before the repository or the site is announced.

| Package | Licence | Why it is listed here | What it asks of us |
|---|---|---|---|
| `elkjs` 0.9.3 | **EPL-2.0** (Eclipse Public License 2.0, a weak, file-level copyleft licence) | It is inside `mermaid.min.js`: `elkjs/lib/elk.bundled.js`, the ELK graph layout engine compiled to JavaScript. 342 occurrences of `org.eclipse.elk` are in the minified file. | When the code is distributed in object form (this file is), the distributor must say that the source is available and how to get it, and give the licence text (below). The source of the exact version is the npm tarball in the table "What was fetched" (its sha1 is there) and the upstream project <https://github.com/kieler/elkjs>, which builds <https://github.com/eclipse/elk>. Changes to EPL-licensed code must stay under the EPL; this repository does not change it (the bundle is mermaid's own build, vendored unmodified). The EPL does not reach this repository's own code or the Kit Book's text, which are separate works under Apache-2.0 and CC BY 4.0; whether a minified bundle of many licences counts as one combined work is a legal question this file does not settle. |
| `dompurify` 3.4.12 | **(MPL-2.0 OR Apache-2.0)**, a choice | Same bundle. The package metadata and the banner kept in the minified file both say "Apache license 2.0 and Mozilla Public License 2.0". | **This project takes DOMPurify under the Apache License 2.0** (the choice the licence gives the recipient). Apache-2.0 is on the permitted list, so nothing more is needed than the notice and licence text below. The copy of `LICENSE` in the npm tarball is the Apache-2.0 text only. |
| `khroma` 2.1.0 | MIT (by its licence file) | The package metadata has no `license` field. | Nothing; the licence file in the tarball is the MIT licence, listed below. |
| `fastdom` 1.0.12 | MIT (by `package.json` and the README) | The tarball has no licence file. | Nothing; the MIT licence is stated in the README of the package, with the copyright line below. |
"""


# ---------------------------------------------------------------------------------------------------------- pure parts

def parse_bundled_packages(js_text):
    """(name, version) of every package that has a file in an esbuild bundle, read from its path comments.

    esbuild writes "// ../../node_modules/.pnpm/<dir>/node_modules/<name>/<file>" above each bundled file, where <dir> is
    "<name>@<version>" (scoped names use "+" for "/", and patched or peer-suffixed ones continue with "_...")."""
    found = set()
    for m in re.finditer(r"^[ \t]*// (?:\.\./)*node_modules/\.pnpm/([^/\n]+)/node_modules/", js_text, re.M):
        d = m.group(1)
        d = re.sub(r"_.*$", "", d)                       # _patch_hash=..., _peer@version
        if d.startswith("@"):
            d = d.replace("+", "/", 1)
        if "@" not in d[1:]:
            continue
        name, version = d.rsplit("@", 1)
        found.add((name, version))
    return sorted(found)


def normalise_body(text):
    """A licence text with its copyright lines and all spacing removed, lower case: two files with the same body are the same licence."""
    lines = [l for l in text.splitlines() if not re.search(r"copyright|\(c\)", l, re.I)]
    body = " ".join(lines).replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", body).strip().lower()


def copyright_lines(text):
    return [re.sub(r"\s+", " ", l).strip() for l in text.splitlines() if re.match(r"^\s*(?:\(c\)\s*)?copyright\b", l, re.I)]


def group_licence_texts(records):
    """Group records that have a licence text by identical body (whatever identifier they declare).
    Returns [(identifiers joined with " / ", body_hash, [records])], in a stable order."""
    groups = collections.OrderedDict()
    for r in sorted(records, key=lambda r: (r["licence"] or "", r["name"], r["version"])):
        if r.get("text") is None:
            continue
        groups.setdefault(hashlib.sha256(normalise_body(r["text"]).encode()).hexdigest()[:8], []).append(r)
    out = [(" / ".join(sorted({r["licence"] or "(no licence field)" for r in g})), h, g) for h, g in groups.items()]
    return sorted(out, key=lambda t: (t[0], t[1]))


def needs_attention(spdx):
    """True when an SPDX expression is not entirely made of the permitted licences (an OR choice that contains one is still flagged)."""
    ids = [t for t in re.split(r"[\s()]+|\bOR\b|\bAND\b|\bWITH\b", spdx or "") if t]
    ids = [t for t in ids if t not in ("OR", "AND", "WITH")]
    return not ids or any(t not in ALLOWED for t in ids)


def fence_for(text):
    """A code fence longer than any run of backticks in the text."""
    longest = max([len(m.group(0)) for m in re.finditer(r"`+", text)] + [2])
    return "`" * (longest + 1)


# ------------------------------------------------------------------------------------------------------------- network

def http(url):
    req = urllib.request.Request(url, headers={"User-Agent": "kit-book-notices/1"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def fetch_package(name, version):
    url = REGISTRY + "%s/%s" % (urllib.parse.quote(name, safe="@"), version)
    raw = http(url)
    meta = json.loads(raw)
    tb = meta["dist"]["tarball"]
    data = http(tb)
    sha1 = meta["dist"]["shasum"]
    if hashlib.sha1(data).hexdigest() != sha1:
        raise SystemExit("%s@%s: the tarball does not match the sha1 the registry publishes" % (name, version))
    tf = tarfile.open(fileobj=io.BytesIO(data))
    files = sorted((m for m in tf.getmembers() if m.isfile() and re.match(r"^package/(licen[cs]e|copying|unlicense)[^/]*$", m.name, re.I)),
                   key=lambda m: m.name)
    text = None
    lfile = None
    if files:
        lfile = files[0].name.split("/", 1)[1]
        text = tf.extractfile(files[0]).read().decode("utf-8", "replace")
    elif name in NO_LICENCE_FILE:
        readme = tf.extractfile("package/README.md").read().decode("utf-8", "replace")
        m = re.search(r"\(The MIT License\)(.*?)(?:\n#|\Z)", readme, re.S)
        if m:
            text = "(The MIT License)" + m.group(1).rstrip() + "\n"
            lfile = "README.md (licence section)"
    lic = meta.get("license")
    if isinstance(lic, dict):
        lic = lic.get("type")
    declared = bool(lic)
    if not lic and text and "Permission is hereby granted, free of charge" in text:
        lic = "MIT"   # read from the licence file; the package metadata declares none (khroma)
    return {
        "declared": declared,
        "name": name, "version": version, "licence": lic, "url": url, "meta_sha256": hashlib.sha256(raw).hexdigest(),
        "tarball": tb, "sha1": sha1, "licence_file": lfile, "text": text,
        "text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest() if text is not None else None,
        "homepage": meta.get("homepage") or "",
    }


def vendored_sha256():
    with open(os.path.join(VENDOR, "README.md"), encoding="utf-8") as fh:
        m = re.search(r"^([0-9a-f]{64})  mermaid\.min\.js$", fh.read(), re.M)
    if not m:
        raise SystemExit("tools/site/vendor/README.md records no sha256 for mermaid.min.js")
    return m.group(1)


# ---------------------------------------------------------------------------------------------------------------- output

def render(records, facts):
    out = []
    w = out.append
    w("# Third-party notices\n")
    w("This repository ships one file it did not write: `tools/site/vendor/mermaid.min.js`, the browser script that draws the book's diagrams. "
      "`make site` copies it, unmodified, into the published website, together with this file. It is a **bundle**: mermaid and the packages "
      "below are compiled into the one file. This page names each of them, with its licence, and gives the licence texts once.\n")
    w("Not covered here: the Kits that `make setup` downloads (each keeps its own licence), and the Dart, Flutter and Rust packages that "
      "`pub` and `cargo` download on your machine when you build the apps (this repository does not redistribute them). "
      "This repository's own licences are in [README.md](README.md#licence).\n")
    w("## The file\n")
    w("| | |")
    w("|---|---|")
    w("| File | `tools/site/vendor/mermaid.min.js` |")
    w("| sha256 | `%s` |" % facts["file_sha256"])
    w("| Built from | mermaid %s (MIT), the `dist/mermaid.min.js` of the npm package `%s/-/mermaid-%s.tgz` |" % (MERMAID[1], REGISTRY + "mermaid", MERMAID[1]))
    w("| Tarball sha1 | `%s` (equal to the `shasum` the npm registry publishes for this version; the file in the tarball is byte-for-byte the vendored file) |" % facts["tarball_sha1"])
    w("| Which packages are inside | read from the unminified build in the same tarball (`dist/mermaid.js`, sha256 `%s`), which keeps one `node_modules/.pnpm/<package>@<version>` comment per bundled file; versions are exactly those. %d packages (%d from those comments, %d inlined through `@mermaid-js/parser`, see below) |"
      % (facts["unminified_sha256"], len(records), facts["n_from_comments"], facts["n_parser"]))
    w("| Lockfile | The npm tarball ships none. The mermaid repository's `pnpm-lock.yaml` at the tag `mermaid@%s` (sha256 `%s`) was read for the packages inlined through the parser |" % (MERMAID[1], facts["lock_sha256"]))
    w("| Fetched | %s, over HTTPS, by `tools/gen-third-party-notices.py` (run it again after upgrading the file; see [the vendor README](tools/site/vendor/README.md)) |\n" % TODAY)
    w("Copies of `mermaid.min.js` carry the licence banners the build keeps (DOMPurify, lodash, cytoscape); the rest of the notices are below.\n")
    w(ATTENTION)
    flagged = sorted(r["name"] + " " + r["version"] for r in records if needs_attention(r["licence"]))
    expected = {"elkjs 0.9.3", "dompurify 3.4.12"}   # explained in ATTENTION
    unexpected = [f for f in flagged if f not in expected]
    if unexpected:
        w("**New since this section was written: %s have a licence that is not on the permitted list. Read their rows and update this section.**\n" % ", ".join(unexpected))
    w("The permitted list used for the check: %s.\n" % ", ".join(sorted(ALLOWED)))

    w("## Components\n")
    w("| Package | Version | Licence | Copyright notice(s) in its licence file | How it was found |")
    w("|---|---|---|---|---|")
    parser_names = {n for n, _v in PARSER_INLINED}
    for r in sorted(records, key=lambda r: (r["name"], r["version"])):
        cl = "; ".join(copyright_lines(r["text"] or "")) or "(none in the file)"
        lic = (r["licence"] or "none found") + ("" if r.get("declared", True) else " (from its licence file; none declared in the metadata)")
        how = "inlined through `@mermaid-js/parser`" if (r["name"], r["version"]) in set(PARSER_INLINED) else "path comment in the build"
        if r["name"] == "mermaid":
            how = "the project itself"
        flag = " **(attention)**" if needs_attention(r["licence"]) else ""
        w("| `%s` | %s | %s%s | %s | %s |" % (r["name"], r["version"], lic, flag, cl.replace("|", "\\|"), how))
    w("")
    w("Two packages appear twice or more at different versions (`d3-array`, `d3-path`, `d3-shape`, `cose-base`, `layout-base`) because different parts of the bundle depend on different majors. Where the lockfile holds two patch versions of an inlined package, the highest is listed; the licence does not differ.\n")

    w("## What was fetched\n")
    w("For each package: the registry metadata document, the tarball (its sha1 is the one the registry publishes, and was checked), and the licence file taken from the tarball. The sha256 values are of those exact bytes, as fetched on %s.\n" % TODAY)
    w("| Package | Metadata sha256 | Tarball sha1 | Licence file | Licence file sha256 |")
    w("|---|---|---|---|---|")
    for r in sorted(records, key=lambda r: (r["name"], r["version"])):
        w("| `%s@%s` | `%s` | `%s` | %s | %s |" % (r["name"], r["version"], r["meta_sha256"], r["sha1"], "`%s`" % r["licence_file"] if r["licence_file"] else "none", "`%s`" % r["text_sha256"] if r["text_sha256"] else "none"))
    w("\nThe addresses are `%s<name>/<version>` for the metadata and the `dist.tarball` address inside it for the tarball. `fastdom` ships no licence file; its text is the licence section of its README, and `khroma`'s metadata has no `license` field (its licence file is MIT).\n" % REGISTRY)

    w("## Licence texts\n")
    w("Each distinct text appears once, exactly as the first package listed under it ships it; the other packages listed share the same wording apart from the copyright line, which is in the Components table. "
      "Apache-2.0 and the EPL are the standard texts.\n")
    n = 0
    for spdx, _h, group in group_licence_texts(records):
        n += 1
        rep = group[0]
        names = ", ".join("`%s %s`" % (r["name"], r["version"]) for r in group)
        w("### %d. %s\n" % (n, spdx))
        w("Applies to: %s.\n" % names)
        if "MPL-2.0" in spdx:
            w("`dompurify` is taken under the Apache License 2.0 (its package offers MPL-2.0 or Apache-2.0); see the attention table.\n")
        fence = fence_for(rep["text"])
        w("Text as shipped by `%s %s` (`%s`):\n" % (rep["name"], rep["version"], rep["licence_file"]))
        w("%stext\n%s\n%s\n" % (fence, rep["text"].rstrip("\n"), fence))
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "THIRD-PARTY-NOTICES.md"))
    a = ap.parse_args(argv)

    want = vendored_sha256()
    print("downloading mermaid %s ..." % MERMAID[1], file=sys.stderr)
    meta = json.loads(http(REGISTRY + "%s/%s" % MERMAID))
    tgz = http(meta["dist"]["tarball"])
    if hashlib.sha1(tgz).hexdigest() != meta["dist"]["shasum"]:
        raise SystemExit("the mermaid tarball does not match the sha1 the registry publishes")
    tf = tarfile.open(fileobj=io.BytesIO(tgz))
    minified = tf.extractfile("package/dist/mermaid.min.js").read()
    unminified = tf.extractfile("package/dist/mermaid.js").read()
    if hashlib.sha256(minified).hexdigest() != want:
        raise SystemExit("package/dist/mermaid.min.js in the tarball is not the sha256 recorded in tools/site/vendor/README.md")
    with open(os.path.join(VENDOR, "mermaid.min.js"), "rb") as fh:
        if fh.read() != minified:
            raise SystemExit("the vendored mermaid.min.js differs from the one in the tarball")
    lock = http(LOCKFILE_URL)

    from_comments = parse_bundled_packages(unminified.decode("utf-8", "replace"))
    pkgs = sorted(set(from_comments) | set(PARSER_INLINED) | {MERMAID})
    records = []
    for name, version in pkgs:
        print("  %s@%s" % (name, version), file=sys.stderr)
        records.append(fetch_package(name, version))
    facts = {
        "file_sha256": want, "tarball_sha1": meta["dist"]["shasum"], "unminified_sha256": hashlib.sha256(unminified).hexdigest(),
        "lock_sha256": hashlib.sha256(lock).hexdigest(), "n_from_comments": len(set(from_comments) | {MERMAID}), "n_parser": len(PARSER_INLINED),
    }
    text = render(records, facts)
    with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text if text.endswith("\n") else text + "\n")
    print("wrote %s (%d packages)" % (a.out, len(records)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

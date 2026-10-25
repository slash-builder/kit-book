#!/usr/bin/env python3
"""Check the built website (run `make site` first).

    python3 tools/site-check.py [--site build/site] [--publish build/site-publish] [--domain NAME] [--indexable 0|1]

  1. Links: every internal link, script, stylesheet and image address in every generated HTML page resolves to a file in
     the site (a folder means its index.html), and every #fragment names an id that exists in the page it points to.
     Addresses to other sites (http:, https:, mailto: ...) are counted, not fetched.
  2. Publish staging folder: it has a CNAME file that holds exactly the domain, an empty .nojekyll, an index.html and the
     same pages as the site.
  3. Robots: with SITE_INDEXABLE=0 (the default) every page carries <meta name="robots" content="noindex">; with
     SITE_INDEXABLE=1 no page carries it, except print.html and toc.html, which mdBook always marks noindex itself.
  4. Diagrams: the vendored mermaid file in tools/site/vendor/, the copy in the site and the copy in the publish folder
     all match the sha256 recorded in tools/site/vendor/README.md, the licence file is there, and every page with a
     mermaid code block loads the init script.
  5. Notices: THIRD-PARTY-NOTICES.md is in the site root and in the publish folder, byte-for-byte the one at the repository root
     (the vendored script is a bundle of other people's code, and its licences ask for the notice to travel with it).

The domain and SITE_INDEXABLE come from the environment (make exports them) or the Makefile. Standard library only.
Exit status 1 when anything fails.
"""
import argparse
import hashlib
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "tools", "site", "vendor")

NOINDEX_RE = re.compile(r"""<meta\s+name\s*=\s*["']robots["']\s+content\s*=\s*["'][^"']*noindex[^"']*["']\s*/?>""", re.I)
EXTERNAL_RE = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")


def makefile_default(name):
    """The value of a 'NAME ?= value' line in the Makefile (the one place the site settings are written)."""
    with open(os.path.join(ROOT, "Makefile"), encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^%s\s*\?=\s*(.*?)\s*$" % re.escape(name), line)
            if m:
                return m.group(1)
    raise SystemExit("%s is not set and has no default in the Makefile" % name)


def setting(name):
    return os.environ.get(name) or makefile_default(name)


class PageParser(HTMLParser):
    """Collects the addresses a page refers to and the ids it defines."""

    ADDRESS_ATTRS = {"a": "href", "link": "href", "script": "src", "img": "src", "iframe": "src", "source": "src"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs = []     # (tag, address)
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if d.get("id"):
            self.ids.add(d["id"])
        if tag == "a" and d.get("name"):
            self.ids.add(d["name"])
        attr = self.ADDRESS_ATTRS.get(tag)
        if attr and d.get(attr) is not None:
            self.refs.append((tag, d[attr]))


def html_files(site):
    out = []
    for dirpath, _dirs, files in os.walk(site):
        for f in files:
            if f.endswith(".html"):
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def parse_page(path):
    p = PageParser()
    with open(path, encoding="utf-8") as fh:
        p.feed(fh.read())
    return p


def resolve(site, page, address):
    """The file an internal address points to, or None for 'not internal / nothing to check'. Returns (file, fragment)."""
    addr = address.strip()
    if EXTERNAL_RE.match(addr):
        return None
    path, _, frag = addr.partition("#")
    path = unquote(path.split("?", 1)[0])
    if path == "":
        return page, unquote(frag)
    base = site if path.startswith("/") else os.path.dirname(page)
    dest = os.path.normpath(os.path.join(base, path.lstrip("/") if path.startswith("/") else path))
    if os.path.isdir(dest):
        dest = os.path.join(dest, "index.html")
    return dest, unquote(frag)


def check_links(site):
    """Returns (stats dict, problems list)."""
    problems = []
    pages = html_files(site)
    parsed = {}
    stats = {"pages": len(pages), "internal": 0, "external": 0, "fragments": 0}
    site_abs = os.path.abspath(site)
    for page in pages:
        parsed[page] = parse_page(page)
    for page in pages:
        rel = os.path.relpath(page, site)
        for tag, address in parsed[page].refs:
            if address.strip() == "" or address.strip() == "#":
                continue
            r = resolve(site, page, address)
            if r is None:
                stats["external"] += 1
                continue
            dest, frag = r
            stats["internal"] += 1
            if not os.path.abspath(dest).startswith(site_abs + os.sep):
                problems.append("%s: <%s> leaves the site: %s" % (rel, tag, address))
                continue
            if not os.path.isfile(dest):
                problems.append("%s: <%s> %s does not resolve to a file" % (rel, tag, address))
                continue
            if frag and dest.endswith(".html"):
                stats["fragments"] += 1
                if dest not in parsed:
                    parsed[dest] = parse_page(dest)
                if frag not in parsed[dest].ids:
                    problems.append("%s: <%s> %s: no id '%s' in %s" % (rel, tag, address, frag, os.path.relpath(dest, site)))
    return stats, problems


def check_publish(publish, site, domain):
    problems = []
    if not os.path.isdir(publish):
        return ["%s does not exist (run make site)" % publish]
    cname = os.path.join(publish, "CNAME")
    if not os.path.isfile(cname):
        problems.append("publish folder has no CNAME file")
    else:
        with open(cname, encoding="utf-8") as fh:
            got = fh.read()
        if got not in (domain, domain + "\n"):
            problems.append("CNAME holds %r, expected exactly %r" % (got, domain))
    nj = os.path.join(publish, ".nojekyll")
    if not os.path.isfile(nj):
        problems.append("publish folder has no .nojekyll file")
    elif os.path.getsize(nj) != 0:
        problems.append(".nojekyll is not empty")
    if not os.path.isfile(os.path.join(publish, "index.html")):
        problems.append("publish folder has no index.html")
    a = {os.path.relpath(p, site) for p in html_files(site)}
    b = {os.path.relpath(p, publish) for p in html_files(publish)}
    if a != b:
        problems.append("publish folder and site hold different pages (rebuild with make site): %s" % sorted(a ^ b)[:5])
    return problems


# mdBook writes noindex into these two pages itself (the whole book on one page, and the table of contents), whatever
# the setting, and that is right: they duplicate the real pages. They are checked for the tag only in the default mode.
ALWAYS_NOINDEX = ("print.html", "toc.html")


def check_noindex(site, indexable):
    problems = []
    pages = html_files(site)
    with_tag = 0
    for page in pages:
        with open(page, encoding="utf-8") as fh:
            has = bool(NOINDEX_RE.search(fh.read()))
        with_tag += has
        if indexable and has and os.path.relpath(page, site) not in ALWAYS_NOINDEX:
            problems.append("%s has a noindex robots tag but SITE_INDEXABLE=1" % os.path.relpath(page, site))
        if not indexable and not has:
            problems.append("%s has no noindex robots tag (SITE_INDEXABLE=0)" % os.path.relpath(page, site))
    return with_tag, len(pages), problems


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def recorded_sha(vendor, name="mermaid.min.js"):
    with open(os.path.join(vendor, "README.md"), encoding="utf-8") as fh:
        m = re.search(r"^([0-9a-f]{64})  %s$" % re.escape(name), fh.read(), re.M)
    return m.group(1) if m else None


def check_diagrams(site, publish, vendor):
    problems = []
    want = recorded_sha(vendor)
    if not want:
        return 0, 0, ["tools/site/vendor/README.md records no sha256 for mermaid.min.js"]
    if not os.path.isfile(os.path.join(vendor, "LICENSE-mermaid")):
        problems.append("tools/site/vendor/LICENSE-mermaid is missing")
    for label, path in (("vendored file", os.path.join(vendor, "mermaid.min.js")),
                        ("copy in the site", os.path.join(site, "mermaid.min.js")),
                        ("copy in the publish folder", os.path.join(publish, "mermaid.min.js"))):
        if not os.path.isfile(path):
            problems.append("mermaid.min.js: the %s is missing (%s)" % (label, path))
        elif sha256_of(path) != want:
            problems.append("mermaid.min.js: the %s does not match the recorded sha256" % label)
    pages = blocks = 0
    for page in html_files(site):
        with open(page, encoding="utf-8") as fh:
            text = fh.read()
        n = text.count('class="language-mermaid')
        if not n:
            continue
        pages += 1
        blocks += n
        if not re.search(r"""<script[^>]+src="[^"]*mermaid-init[^"]*\.js"[^>]*>""", text):
            problems.append("%s has %d mermaid block(s) but does not load the init script" % (os.path.relpath(page, site), n))
    return pages, blocks, problems


def check_notices(site, publish, notices):
    """THIRD-PARTY-NOTICES.md must be in the site and in the publish folder, identical to the repository's own."""
    name = "THIRD-PARTY-NOTICES.md"
    if not os.path.isfile(notices):
        return ["%s is missing at the repository root" % name]
    with open(notices, "rb") as fh:
        want = fh.read()
    problems = []
    for label, folder in (("the site", site), ("the publish folder", publish)):
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            problems.append("%s is missing from %s (make site copies it)" % (name, label))
            continue
        with open(path, "rb") as fh:
            if fh.read() != want:
                problems.append("%s in %s differs from the one at the repository root (rebuild with make site)" % (name, label))
    return problems


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", default=os.path.join(ROOT, "build", "site"))
    ap.add_argument("--publish", default=os.path.join(ROOT, "build", "site-publish"))
    ap.add_argument("--vendor", default=VENDOR)
    ap.add_argument("--notices", default=os.path.join(ROOT, "THIRD-PARTY-NOTICES.md"))
    ap.add_argument("--domain", default=None)
    ap.add_argument("--indexable", default=None)
    args = ap.parse_args(argv)
    domain = args.domain or setting("SITE_DOMAIN")
    indexable = (args.indexable if args.indexable is not None else setting("SITE_INDEXABLE")) == "1"

    if not os.path.isfile(os.path.join(args.site, "index.html")):
        print("site-check: no built site at %s. Run make site first (it needs mdBook)." % os.path.relpath(args.site, ROOT))
        return 2

    failed = 0

    def report(name, problems, summary):
        nonlocal failed
        if problems:
            failed += len(problems)
            print("FAIL  %s" % name)
            for p in problems[:50]:
                print("      " + p)
            if len(problems) > 50:
                print("      ... and %d more" % (len(problems) - 50))
        else:
            print("ok    %s: %s" % (name, summary))

    stats, problems = check_links(args.site)
    report("links", problems, "%d pages, %d internal addresses resolve to files (%d with a #fragment, all found), %d external not fetched"
           % (stats["pages"], stats["internal"], stats["fragments"], stats["external"]))
    report("publish folder", check_publish(args.publish, args.site, domain),
           "CNAME is exactly %s, .nojekyll is empty, same pages as the site" % domain)
    tagged, total, problems = check_noindex(args.site, indexable)
    report("robots", problems, ("%d of %d pages carry noindex (SITE_INDEXABLE=0)" % (tagged, total)) if not indexable
           else "no page of %d carries noindex (SITE_INDEXABLE=1), except mdBook's own print.html and toc.html" % total)
    pages, blocks, problems = check_diagrams(args.site, args.publish, args.vendor)
    report("diagrams", problems, "vendored mermaid matches the recorded sha256 in all three places; %d mermaid blocks on %d pages load the init script"
           % (blocks, pages))
    report("notices", check_notices(args.site, args.publish, args.notices),
           "THIRD-PARTY-NOTICES.md is in the site root and the publish folder, identical to the repository's")
    if failed:
        print("\nsite-check: %d problem(s)." % failed)
        return 1
    print("site-check: all checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

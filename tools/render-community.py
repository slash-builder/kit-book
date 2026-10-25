#!/usr/bin/env python3
"""Render CODE_OF_CONDUCT.md and SECURITY.md from the templates in tools/community/ and the contacts in tools/contacts.conf.

    python3 tools/render-community.py              write the two files at the repository root
    python3 tools/render-community.py --check      write nothing; fail if the committed files differ from a fresh render
    python3 tools/render-community.py --final      fail (and write nothing) if a contact is empty

A contact that is empty is rendered as the visible marker [CONTACT NOT SET], and the rendered file starts with a draft
banner, so nothing looks finished. `make go-public-check` fails while the marker is in either file. Standard library only.
The template placeholders are written with double braces: CONDUCT_CONTACT, SECURITY_CONTACT, REPO_URL and DRAFT_BANNER.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKER = "[CONTACT NOT SET]"
KEYS = ("CONDUCT_CONTACT", "SECURITY_CONTACT")
BANNER = ("> **Draft: a contact address is not set yet** (%s below). Reports cannot be made by email until it is. "
          "This notice is removed when `tools/contacts.conf` is filled in.\n\n" % MARKER)
# file -> (template, the contact keys it uses)
OUTPUTS = {
    "CODE_OF_CONDUCT.md": ("CODE_OF_CONDUCT.md.tpl", ("CONDUCT_CONTACT",)),
    "SECURITY.md": ("SECURITY.md.tpl", ("SECURITY_CONTACT",)),
}
PLACEHOLDER_RE = re.compile(r"\{\{([A-Z_]+)\}\}")


def parse_contacts(text):
    """NAME=value lines; comments (#) and blank lines ignored. Unknown names are an error, so a typo cannot pass silently."""
    out = {}
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("contacts.conf line %d is not NAME=value: %r" % (n, raw))
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if k not in KEYS:
            raise ValueError("contacts.conf line %d: unknown name %r (expected %s)" % (n, k, ", ".join(KEYS)))
        out[k] = v
    for k in KEYS:
        out.setdefault(k, "")
    return out


def repo_url(root=ROOT):
    """SITE_REPO_URL from the Makefile: the one place the repository address is written."""
    with open(os.path.join(root, "Makefile"), encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^SITE_REPO_URL\s*\?=\s*(\S+)", line)
            if m:
                return m.group(1).rstrip("/")
    raise ValueError("SITE_REPO_URL has no default in the Makefile")


def render(template, contacts, url, keys):
    """Fill one template. A contact among `keys` that is empty becomes MARKER and switches the draft banner on."""
    values = {"REPO_URL": url}
    unset = False
    for k in KEYS:
        v = contacts.get(k, "")
        if not v:
            v = MARKER
            if k in keys:
                unset = True
        values[k] = v
    values["DRAFT_BANNER"] = BANNER if unset else ""

    def sub(m):
        if m.group(1) not in values:
            raise ValueError("template uses an unknown placeholder {{%s}}" % m.group(1))
        return values[m.group(1)]

    return PLACEHOLDER_RE.sub(sub, template)


def render_all(root=ROOT):
    """Return ({output name: text}, [keys that are empty])."""
    with open(os.path.join(root, "tools", "contacts.conf"), encoding="utf-8") as fh:
        contacts = parse_contacts(fh.read())
    url = repo_url(root)
    out = {}
    for name, (tpl, keys) in OUTPUTS.items():
        with open(os.path.join(root, "tools", "community", tpl), encoding="utf-8") as fh:
            out[name] = render(fh.read(), contacts, url, keys)
    return out, [k for k in KEYS if not contacts[k]]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--final", action="store_true", help="fail if a contact is empty")
    ap.add_argument("--check", action="store_true", help="write nothing; fail if the committed files are not a fresh render")
    ap.add_argument("--root", default=ROOT, help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    try:
        out, empty = render_all(a.root)
    except (OSError, ValueError) as e:
        print("render-community: %s" % e, file=sys.stderr)
        return 2
    if a.final and empty:
        print("render-community: --final: %s empty in tools/contacts.conf. Set CONDUCT_CONTACT and SECURITY_CONTACT there." % ", ".join(empty),
              file=sys.stderr)
        return 1
    if a.check:
        bad = 0
        for name, text in out.items():
            p = os.path.join(a.root, name)
            have = open(p, encoding="utf-8").read() if os.path.exists(p) else None
            if have != text:
                print("render-community: %s is %s; run: make community" % (name, "missing" if have is None else "not a fresh render of its template and contacts.conf"), file=sys.stderr)
                bad = 1
        if not bad:
            print("render-community: CODE_OF_CONDUCT.md and SECURITY.md are fresh renders")
        return bad
    for name, text in out.items():
        with open(os.path.join(a.root, name), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print("wrote %s" % name)
    if empty:
        print("WARNING: %s empty in tools/contacts.conf: the files carry the visible marker %s. Not final." % (", ".join(empty), MARKER), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

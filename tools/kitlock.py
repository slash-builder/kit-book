"""Read kits.lock. Shared by tools/go-public-check.py and tools/stranger-env.py; standard library only.

One line per Kit, five fields: name repo-url commit visibility role (see the comments at the top of kits.lock).
"""
import re
from collections import namedtuple

Kit = namedtuple("Kit", "name url commit visibility role line")

HEX40 = re.compile(r"^[0-9a-f]{40}$")
URL_RE = re.compile(r"^https://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+?)(?:\.git)?/?$")


def parse_lock(text):
    """The Kits in kits.lock text, in order. A line with fewer than five fields is returned with empty trailing fields
    (the checks report it) rather than raising, so one bad line does not hide the others."""
    kits = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        f = line.split()
        f += [""] * (5 - len(f))
        kits.append(Kit(f[0], f[1], f[2], f[3], f[4], n))
    return kits


def comment_lines(text):
    """(line number, text) of every comment line."""
    return [(n, l) for n, l in enumerate(text.splitlines(), 1) if l.strip().startswith("#")]


def split_url(url):
    """(org, repo) of a GitHub repository address, or None when it is not one."""
    m = URL_RE.match(url)
    return (m.group(1), m.group(2)) if m else None

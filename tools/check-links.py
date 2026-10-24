#!/usr/bin/env python3
"""Check every relative link and heading anchor in the book and the README files.

    python3 tools/check-links.py            check book/, README.md, CONTRIBUTING.md, apps/*/README.md, labs/*/README.md
    python3 tools/check-links.py FILE...    check only those files

What it checks
  * [text](path) and [text](path#anchor) and ![alt](path): the file or folder must exist, relative to the page.
  * [text](#anchor) and path#anchor into another Markdown file: the anchor must match a heading there, using
    GitHub's heading slugs (lower case, punctuation removed, spaces to hyphens, -1, -2 for repeated headings),
    or an explicit <a id="..."> / <a name="..."> anchor.
  * Reference-style links: [text][label] with a [label]: path definition.
  * A code fence whose opening line says copied-from=<path> (for example ```dart copied-from=apps/x/lib/main.dart)
    must appear, line for line, in that file (path relative to the repository root).
  * Links into .kits/ are errors: that folder is not part of a clone.
External links (http, https, mailto) are not fetched. Standard library only. Exit status 1 on any problem.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$")
INLINE_LINK_RE = re.compile(r"(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*(<[^>]*>|[^)\s]*)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
REF_USE_RE = re.compile(r"\[((?:[^\[\]]|\[[^\]]*\])*)\]\[([^\]]*)\]")
REF_DEF_RE = re.compile(r"^ {0,3}\[([^\]]+)\]:\s*(<[^>]*>|\S+)")
ANCHOR_TAG_RE = re.compile(r"""<a\s+[^>]*?(?:id|name)\s*=\s*["']([^"']+)["']""", re.I)
CODE_SPAN_RE = re.compile(r"(`+)(.+?)\1")


def github_slug(text):
    """GitHub's heading anchor: strip markup, lower case, drop punctuation, spaces to hyphens."""
    t = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)      # images: keep alt text
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)          # links: keep link text
    t = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", t)         # reference links
    t = re.sub(r"<[^>]+>", "", t)                           # inline html
    t = t.replace("`", "")                                  # code span marks (content stays)
    t = re.sub(r"(\*\*|__|\*|~~)", "", t)                   # emphasis marks
    t = re.sub(r"(?<![A-Za-z0-9])_|_(?![A-Za-z0-9])", "", t)  # emphasis underscores at word edges
    t = t.strip().lower()
    out = []
    for ch in t:
        if ch.isalnum() or ch in "-_":
            out.append(ch)
        elif ch.isspace():
            out.append("-")
        # everything else is dropped
    return "".join(out)


_anchor_cache = {}


def anchors_of(path):
    """The set of anchors a Markdown file offers."""
    if path in _anchor_cache:
        return _anchor_cache[path]
    anchors = set()
    seen = {}
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        _anchor_cache[path] = anchors
        return anchors
    in_fence = None
    for line in lines:
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(2)[0]
            if in_fence is None:
                in_fence = marker
            elif in_fence == marker and not m.group(3).strip():
                in_fence = None
            continue
        if in_fence:
            continue
        h = HEADING_RE.match(line)
        if h:
            slug = github_slug(h.group(2))
            n = seen.get(slug, 0)
            seen[slug] = n + 1
            anchors.add(slug if n == 0 else "%s-%d" % (slug, n))
        for a in ANCHOR_TAG_RE.findall(line):
            anchors.add(a)
    _anchor_cache[path] = anchors
    return anchors


def default_files():
    files = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "book")):
        for f in sorted(filenames):
            if f.endswith(".md"):
                files.append(os.path.join(dirpath, f))
    for name in ("README.md", "CONTRIBUTING.md"):
        p = os.path.join(ROOT, name)
        if os.path.exists(p):
            files.append(p)
    for sub in ("apps", "labs"):
        base = os.path.join(ROOT, sub)
        if os.path.isdir(base):
            for d in sorted(os.listdir(base)):
                p = os.path.join(base, d, "README.md")
                if os.path.exists(p):
                    files.append(p)
    return files


def split_target(raw):
    raw = raw.strip()
    if raw.startswith("<") and raw.endswith(">"):
        raw = raw[1:-1]
    if "#" in raw:
        path, frag = raw.split("#", 1)
    else:
        path, frag = raw, None
    return path, frag


def unquote(s):
    return re.sub(r"%([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), s)


def check_file(path, problems):
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    defs = {}
    in_fence = None
    for line in lines:                       # first pass: reference definitions outside fences
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(2)[0]
            if in_fence is None:
                in_fence = marker
            elif in_fence == marker and not m.group(3).strip():
                in_fence = None
            continue
        if in_fence:
            continue
        d = REF_DEF_RE.match(line)
        if d:
            defs[d.group(1).strip().lower()] = d.group(2)

    def check_target(raw, lineno):
        raw = raw.strip()
        if not raw or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", raw):   # external: http:, https:, mailto:, ...
            return
        target, frag = split_target(raw)
        target = unquote(target)
        if target == "":
            dest = path
        else:
            dest = os.path.normpath(os.path.join(os.path.dirname(path), target))
        drel = os.path.relpath(dest, ROOT)
        if drel == ".kits" or drel.startswith(".kits" + os.sep):
            problems.append("%s:%d: link into .kits/ (not part of a clone): %s" % (rel, lineno, raw))
            return
        if not os.path.exists(dest):
            problems.append("%s:%d: no such file or folder: %s" % (rel, lineno, raw))
            return
        if frag:
            frag = unquote(frag)
            if os.path.isfile(dest) and dest.endswith(".md"):
                if frag not in anchors_of(dest) and frag.lower() not in anchors_of(dest):
                    problems.append("%s:%d: no heading anchor '#%s' in %s" % (rel, lineno, frag, os.path.relpath(dest, ROOT)))
            elif os.path.isdir(dest):
                problems.append("%s:%d: anchor '#%s' on a folder link: %s" % (rel, lineno, frag, raw))
            # anchors in non-Markdown files (line numbers on GitHub, e.g. #L10) are not checked

    in_fence = None
    fence_info = ""
    fence_body = []
    fence_start = 0
    for i, line in enumerate(lines, 1):
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(2)[0]
            if in_fence is None:
                in_fence = marker
                fence_info = m.group(3).strip()
                fence_body = []
                fence_start = i
            elif in_fence == marker and not m.group(3).strip():
                in_fence = None
                cm = re.search(r"copied-from=(\S+)", fence_info)
                if cm:
                    check_copied(path, rel, fence_start, cm.group(1), fence_body, problems)
            continue
        if in_fence:
            fence_body.append(line)
            continue
        stripped = CODE_SPAN_RE.sub(lambda mm: " " * len(mm.group(0)), line)   # ignore links inside code spans
        for mm in INLINE_LINK_RE.finditer(stripped):
            check_target(mm.group(3), i)
        for mm in REF_USE_RE.finditer(stripped):
            label = (mm.group(2) or mm.group(1)).strip().lower()
            if label in defs:
                check_target(defs[label], i)
            elif mm.group(2).strip():
                problems.append("%s:%d: reference link [%s] has no definition" % (rel, i, mm.group(2)))
        d = REF_DEF_RE.match(stripped)
        if d:
            check_target(d.group(2), i)


def check_copied(page, rel, lineno, srcpath, body, problems):
    full = os.path.join(ROOT, srcpath)
    if not os.path.isfile(full):
        problems.append("%s:%d: copied-from file does not exist: %s" % (rel, lineno, srcpath))
        return
    with open(full, encoding="utf-8") as fh:
        src = [l.rstrip() for l in fh.read().splitlines()]
    want = [l.rstrip() for l in body]
    while want and not want[0]:
        want.pop(0)
    while want and not want[-1]:
        want.pop()
    if not want:
        problems.append("%s:%d: copied-from block is empty: %s" % (rel, lineno, srcpath))
        return
    n = len(want)
    for start in range(0, len(src) - n + 1):
        if src[start:start + n] == want:
            return
    problems.append("%s:%d: code block no longer matches %s" % (rel, lineno, srcpath))


def main(argv):
    files = [os.path.abspath(a) for a in argv] if argv else default_files()
    problems = []
    for f in files:
        if not os.path.isfile(f):
            problems.append("%s: no such file" % f)
            continue
        check_file(f, problems)
    if problems:
        for p in problems:
            print(p)
        print("\ncheck-links: %d problem(s) in %d file(s)." % (len(problems), len(files)))
        return 1
    print("check-links: %d files, every relative link, heading anchor and copied-from block is fine." % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

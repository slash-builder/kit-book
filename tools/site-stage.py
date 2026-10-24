#!/usr/bin/env python3
"""Stage a copy of book/ for the website and send links that leave the book to GitHub.

    python3 tools/site-stage.py --repo-url https://github.com/ORG/REPO [--branch main] [--rewrite 1|0]
                                [--book book] [--dest build/site-src]

On GitHub a page in book/ can link to apps/..., labs/... or CONTRIBUTING.md with a relative path. On the website those
paths do not exist, so in the staged copy such a link becomes <repo-url>/tree/<branch>/<path> (a folder) or
<repo-url>/blob/<branch>/<path> (a file). Links that stay inside book/ and links to other sites are left alone, and so are
code blocks and code spans, with one exception: mdBook writes a folder's README.md chapter as index.html but still turns a
link to README.md into README.html, which does not exist, so an in-book link to README.md becomes a link to index.md (which
mdBook turns into index.html). book/ itself is never modified. With --rewrite 0 the copy is made and nothing is rewritten.

Prints one summary line, "rewrote N link(s) in M page(s)" (and "renamed K README link(s)") (and a warning for each link it could not place), and with
--list one line per rewrite. Standard library only.
"""
import argparse
import os
import re
import shutil
import sys
from urllib.parse import quote, unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
INLINE_LINK_RE = re.compile(r"(!?)(\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*)(<[^>]*>|[^)\s]*)")
REF_DEF_RE = re.compile(r"^( {0,3}\[[^\]]+\]:\s*)(<[^>]*>|\S+)")
CODE_SPAN_RE = re.compile(r"(`+)(.+?)\1")
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def github_url(repo_url, branch, repo_path, is_dir, fragment):
    """The address of a repository path on GitHub."""
    kind = "tree" if is_dir else "blob"
    url = "%s/%s/%s/%s" % (repo_url.rstrip("/"), kind, branch, quote(repo_path.replace(os.sep, "/")))
    return url + ("#" + fragment if fragment else "")


def readme_to_index(path, fragment, dest, angled):
    """For an in-book link to a README.md, the same link to index.md; None when the link is not that."""
    if os.path.basename(path) != "README.md" or os.path.exists(os.path.join(os.path.dirname(dest), "index.md")):
        return None
    new = path[: -len("README.md")] + "index.md" + ("#" + fragment if fragment else "")
    return "<%s>" % new if angled else new


def rewrite_target(raw, page_dir, book_dir, repo_root, repo_url, branch):
    """The new address for one link target.

    page_dir is the folder of the page in the original book/; book_dir is that book/; repo_root the repository root.
    Returns (new_target, kind, warning). new_target is None for a link to leave as it is; kind is "repo" for a link sent
    to GitHub and "readme" for an in-book README.md link renamed to index.md; warning is None or a sentence.
    """
    target = raw.strip()
    angled = target.startswith("<") and target.endswith(">")
    if angled:
        target = target[1:-1]
    if not target or target.startswith("#") or target.startswith("/") or SCHEME_RE.match(target):
        return None, None, None
    path, _, fragment = target.partition("#")
    path = unquote(path.split("?", 1)[0])
    if not path:
        return None, None, None
    dest = os.path.normpath(os.path.join(page_dir, path))
    rel_book = os.path.relpath(dest, book_dir)
    if rel_book == "." or not (rel_book == ".." or rel_book.startswith(".." + os.sep)):
        new = readme_to_index(target.partition("#")[0], fragment, dest, angled)   # inside book/: mdBook resolves it
        return new, ("readme" if new else None), None
    rel_repo = os.path.relpath(dest, repo_root)
    if rel_repo == ".." or rel_repo.startswith(".." + os.sep):
        return None, None, "points outside the repository: %s" % raw
    if rel_repo == ".kits" or rel_repo.startswith(".kits" + os.sep):
        return None, None, "points into .kits/, which is not in a clone: %s" % raw
    if not os.path.exists(dest):
        return None, None, "does not exist, left as it is: %s" % raw
    new = github_url(repo_url, branch, "" if rel_repo == "." else rel_repo, os.path.isdir(dest), fragment or None)
    return ("<%s>" % new if angled else new), "repo", None


def rewrite_text(text, page_dir, book_dir, repo_root, repo_url, branch, page_label="", warnings=None, listing=None,
                 repo_links=True):
    """Rewrite the links of one page. Returns (new_text, repo_links_rewritten, readme_links_renamed)."""
    counts = {"repo": 0, "readme": 0}
    out = []
    in_fence = None
    for lineno, line in enumerate(text.split("\n"), 1):
        m = FENCE_RE.match(line)
        if m:
            marker = m.group(2)[0]
            if in_fence is None:
                in_fence = marker
            elif in_fence == marker and not m.group(3).strip():
                in_fence = None
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue

        # Hide code spans so a link written as an example is left alone; put them back afterwards.
        spans = []

        def hide(mm):
            spans.append(mm.group(0))
            return "\x00%d\x00" % (len(spans) - 1)

        work = CODE_SPAN_RE.sub(hide, line)

        def one(raw):
            new, kind, warn = rewrite_target(raw, page_dir, book_dir, repo_root, repo_url, branch)
            if kind == "repo" and not repo_links:
                return raw
            if warn and warnings is not None and repo_links:
                warnings.append("%s:%d: link %s" % (page_label, lineno, warn))
            if new is None:
                return raw
            counts[kind] += 1
            if listing is not None:
                listing.append("%s:%d: [%s] %s -> %s" % (page_label, lineno, kind, raw, new))
            return new

        def inline(mm):
            if mm.group(1) == "!":              # an image: GitHub would show an HTML page, not the picture, so leave it
                return mm.group(0)
            return mm.group(1) + mm.group(2) + one(mm.group(3))

        d = REF_DEF_RE.match(work)
        if d:
            work = d.group(1) + one(d.group(2)) + work[d.end():]
        else:
            work = INLINE_LINK_RE.sub(inline, work)
        work = re.sub("\x00(\\d+)\x00", lambda mm: spans[int(mm.group(1))], work)
        out.append(work)
    return "\n".join(out), counts["repo"], counts["readme"]


def stage(book_dir, dest, repo_root, repo_url, branch, rewrite, warnings=None, listing=None):
    """Copy book_dir to dest (replacing it). Returns (repo_links_rewritten, pages_changed, readme_links_renamed)."""
    book_dir = os.path.abspath(book_dir)
    repo_root = os.path.abspath(repo_root)
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(book_dir, dest)
    repo_total = readme_total = 0
    pages = set()
    for dirpath, _dirs, files in os.walk(book_dir):
        for f in sorted(files):
            if not f.endswith(".md") or (f == "SUMMARY.md" and dirpath == book_dir):
                continue                        # SUMMARY.md names the real files, README.md included
            src = os.path.join(dirpath, f)
            with open(src, encoding="utf-8", newline="") as fh:
                text = fh.read()
            label = os.path.relpath(src, repo_root)
            new, n_repo, n_readme = rewrite_text(text, dirpath, book_dir, repo_root, repo_url, branch, label, warnings,
                                                 listing, repo_links=rewrite)
            if n_repo or n_readme:
                with open(os.path.join(dest, os.path.relpath(src, book_dir)), "w", encoding="utf-8", newline="") as fh:
                    fh.write(new)
                repo_total += n_repo
                readme_total += n_readme
                if n_repo:
                    pages.add(src)
    return repo_total, len(pages), readme_total


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo-url", required=True, help="the repository address, e.g. https://github.com/ORG/REPO")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--rewrite", default="1", help="1 (default) rewrites links that leave the book; 0 only copies")
    ap.add_argument("--book", default=os.path.join(ROOT, "book"))
    ap.add_argument("--dest", default=os.path.join(ROOT, "build", "site-src"))
    ap.add_argument("--root", default=ROOT, help="the repository root (links are resolved against it)")
    ap.add_argument("--list", action="store_true", help="print every rewrite")
    args = ap.parse_args(argv)
    warnings, listing = [], []
    n, pages, readmes = stage(args.book, args.dest, args.root, args.repo_url, args.branch, args.rewrite != "0", warnings, listing)
    if args.list:
        for line in listing:
            print(line)
    for w in warnings:
        print("warning: " + w, file=sys.stderr)
    if args.rewrite == "0":
        print("link rewrite is off (SITE_REWRITE_REPO_LINKS=0): links to apps/, labs/ and other repository paths are left as they are")
    else:
        print("rewrote %d link(s) in %d page(s) to %s/{tree,blob}/%s/..." % (n, pages, args.repo_url.rstrip("/"), args.branch))
    print("renamed %d in-book README.md link(s) to index.md (mdBook publishes a folder's README.md as index.html)" % readmes)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

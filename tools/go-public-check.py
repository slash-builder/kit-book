#!/usr/bin/env python3
"""The launch gate: one read-only run that says whether this repository is ready to be made public.  `make go-public-check`

    python3 tools/go-public-check.py            run every check, print the table, exit 1 if anything FAILS
    python3 tools/go-public-check.py --list     print what is checked and exit

Result words: ok, warn (says what to do, does not fail the gate), FAIL (the gate fails). It writes nothing to the working
tree: the website is built in a temporary copy, so build/ is not touched. It changes no GitHub setting and no DNS record.
GO_PUBLIC_OFFLINE=1 skips the checks that need the network and ends with INCOMPLETE (exit 3): never a pass.

The checks (the letters are the column "#"):
  a  the public-safety scan in strict mode, and the private Kits that stay private (warn: which apps then skip)
  b  kits.lock: URL repo name = Kit name, no rename marker, no old Kit spelling, 40-hex pins
  c  every core Kit answers HTTP 200 without credentials, and its pinned commit exists
  d  make docs, make docs-pull-check, then the website built with SITE_INDEXABLE=1 and checked
  e  LICENSE, LICENSE-docs, and THIRD-PARTY-NOTICES.md naming the vendored mermaid version and sha256
  f  CODE_OF_CONDUCT.md and SECURITY.md exist, carry no placeholder, and the contacts are set
  g  no tracked file spells an old Kit name (appkit, application_kit, application-kit) outside tools/go-public-allow.txt
  h  the repository's own visibility (private is a warning: make it public, then run this again)
  i  the built site's CNAME equals SITE_DOMAIN
  j  the working tree is clean and on main (warn), and every kits.need names a Kit in kits.lock

Standard library only. The pure parts are tested in tools/tests/test_go_public_check.py.
"""
import collections
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import kitlock  # noqa: E402

ROOT = os.path.dirname(HERE)
OK, WARN, FAIL = "ok", "warn", "FAIL"
Row = collections.namedtuple("Row", "id title status detail")

OLD_SPELLINGS = re.compile(r"appkit|application_kit|application-kit", re.I)
MARKERS = ("[CONTACT NOT SET]", "[INSERT", "{{", "}}")
CONTACTS_HINT = "set CONDUCT_CONTACT and SECURITY_CONTACT in tools/contacts.conf"
# Files that spell the old names on purpose (they define what is looked for) or that are not our text.
SCAN_SKIP = ("tools/go-public-allow.txt", "tools/go-public-check.py", "tools/tests/test_go_public_check.py",
             "tools/site/vendor/mermaid.min.js")


def row(i, title, status, detail=""):
    return Row(i, title, status, detail)


# ----------------------------------------------------------------------------------------------------- b: kits.lock

def check_lock(lock_text):
    """Rows b1..b4 for the text of kits.lock."""
    kits = kitlock.parse_lock(lock_text)
    rows = []
    bad = []
    for k in kits:
        parts = kitlock.split_url(k.url)
        if not parts:
            bad.append("%s: %r is not https://github.com/<org>/<repo>" % (k.name, k.url))
        elif parts[1] != k.name:
            bad.append("%s: the URL names the repository '%s', not '%s'" % (k.name, parts[1], k.name))
    rows.append(row("b1", "kits.lock: URL repository name = Kit name", FAIL if bad else OK, "\n".join(bad)))
    marked = [str(n) for n, l in kitlock.comment_lines(lock_text) if "RENAMED AT RELEASE" in l]
    rows.append(row("b2", "kits.lock: no RENAMED AT RELEASE comment", FAIL if marked else OK,
                    "line(s) %s: the release switch (URL and re-pin) has not been made" % ", ".join(marked) if marked else ""))
    old = ["%d: %s" % (n, l.strip()[:100]) for n, l in enumerate(lock_text.splitlines(), 1)
           if re.search(r"application[-_]kit|appkit", l, re.I)]
    rows.append(row("b3", "kits.lock: no old Kit spelling", FAIL if old else OK, "\n".join(old[:6])))
    nohex = ["%s (%s)" % (k.name, k.commit[:12] or "empty") for k in kits if not kitlock.HEX40.match(k.commit)]
    rows.append(row("b4", "kits.lock: every pin is 40 hex", FAIL if nohex else OK, ", ".join(nohex)))
    return rows


# ------------------------------------------------------------------------------------------------ a: strict scan, WARN

def apps_needing(kit_name, needs_by_app):
    return sorted(a for a, needs in needs_by_app.items() if kit_name in needs)


def private_warnings(kits, needs_by_app):
    """(core failures, warnings) about Kits that kits.lock marks private. Only a private `core` Kit fails the gate; a private
    app-dep is a warning that names the apps that will be skipped; a private reference Kit is a warning too."""
    fails, warns = [], []
    for k in kits:
        if k.visibility != "private":
            continue
        if k.role == "core":
            fails.append("%s is private and has role core: the book documents it and make test runs it" % k.name)
        elif k.role == "app-dep":
            apps = apps_needing(k.name, needs_by_app)
            warns.append("%s is private (app-dep): %s skipped for a stranger%s" % (
                k.name, ", ".join("apps/" + a for a in apps) if apps else "no app lists it in kits.need, so no app is",
                "" if apps else " (nothing breaks, but why is it fetched?)"))
        else:
            warns.append("%s is private (%s): not fetched without KITS=all" % (k.name, k.role or "no role"))
    return fails, warns


# --------------------------------------------------------------------------------------- e: licences and the notices

def vendor_facts(vendor_readme_text):
    """(mermaid version, sha256 of mermaid.min.js) as tools/site/vendor/README.md records them (None when absent)."""
    v = re.search(r"^\|\s*Version\s*\|\s*([0-9][0-9.]*)\s*\|", vendor_readme_text, re.M)
    s = re.search(r"^([0-9a-f]{64})  mermaid\.min\.js\s*$", vendor_readme_text, re.M)
    return (v.group(1) if v else None, s.group(1) if s else None)


def check_notices(root_files, notices_text, vendor_readme_text):
    """Rows e1, e2 for the licences and THIRD-PARTY-NOTICES.md. root_files: names present at the repository root."""
    rows = []
    missing = [f for f in ("LICENSE", "LICENSE-docs") if f not in root_files]
    rows.append(row("e1", "LICENSE and LICENSE-docs are present", FAIL if missing else OK, "missing: " + ", ".join(missing) if missing else ""))
    if notices_text is None:
        rows.append(row("e2", "THIRD-PARTY-NOTICES.md names mermaid version + sha256", FAIL, "THIRD-PARTY-NOTICES.md is missing"))
        return rows
    version, sha = vendor_facts(vendor_readme_text)
    problems = []
    if not version or not sha:
        problems.append("tools/site/vendor/README.md records no mermaid version or sha256 to compare with")
    else:
        if version not in notices_text:
            problems.append("does not mention mermaid version %s" % version)
        if sha not in notices_text:
            problems.append("does not contain the sha256 %s... of mermaid.min.js" % sha[:12])
    rows.append(row("e2", "THIRD-PARTY-NOTICES.md names mermaid version + sha256", FAIL if problems else OK, "\n".join(problems)))
    return rows


# -------------------------------------------------------------------------------------------------------- f: community

def parse_contacts(text):
    out = {}
    for raw in text.splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def contact_ok(value):
    """An address or a link: an email address, or an https address."""
    return bool(re.fullmatch(r"[^\s@<>]+@[^\s@<>]+\.[A-Za-z]{2,}", value) or re.fullmatch(r"https://\S+", value))


def check_community(root_files, texts, contacts_text, render_problem):
    """Rows f1..f3. texts: {name: text or None}. render_problem: None, or why the committed files are not a fresh render."""
    rows = []
    c = parse_contacts(contacts_text or "")
    unset = [k for k in ("CONDUCT_CONTACT", "SECURITY_CONTACT") if not c.get(k)]
    rows.append(row("f1", "tools/contacts.conf: both contacts set", FAIL if unset else OK, CONTACTS_HINT + " (empty: %s)" % ", ".join(unset) if unset else ""))
    malformed = [k for k in ("CONDUCT_CONTACT", "SECURITY_CONTACT") if c.get(k) and not contact_ok(c[k])]
    if malformed:
        rows.append(row("f1b", "tools/contacts.conf: contacts are email or https", FAIL, ", ".join(malformed)))
    problems = []
    for name in ("CODE_OF_CONDUCT.md", "SECURITY.md"):
        t = texts.get(name)
        if t is None:
            problems.append("%s is missing" % name)
            continue
        found = [m for m in MARKERS if m in t]
        if found:
            problems.append("%s still has an unresolved placeholder (%s)" % (name, ", ".join(found)))
    rows.append(row("f2", "community files exist, no placeholder", FAIL if problems else OK, "\n".join(problems)))
    rows.append(row("f3", "community files are a fresh render", FAIL if render_problem else OK, render_problem or ""))
    return rows


# --------------------------------------------------------------------------------------------- g: old Kit spellings

def parse_allow(text):
    """tools/go-public-allow.txt: 'path :: text that must be on the line', one per line; # comments. Returns ([(path, substring)], [errors])."""
    entries, errors = [], []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "::" not in line:
            errors.append("go-public-allow.txt line %d: expected 'path :: text on the line' (got %r)" % (n, line))
            continue
        path, sub = (p.strip() for p in line.split("::", 1))
        if not path or not sub:
            errors.append("go-public-allow.txt line %d: both the path and the text are needed" % n)
        elif path == "kits.lock":
            errors.append("go-public-allow.txt line %d: kits.lock may not be allowed: its URL must be switched to the new name at release" % n)
        else:
            entries.append((path, sub))
    return entries, errors


def find_old_spellings(files, allow):
    """files: {path: text}. Returns the hits ('path:line: text') that no allow entry covers."""
    hits = []
    for path in sorted(files):
        if path in SCAN_SKIP:
            continue
        if OLD_SPELLINGS.search(path):
            hits.append("%s: the file name itself" % path)
        for n, line in enumerate(files[path].splitlines(), 1):
            if OLD_SPELLINGS.search(line):
                if any(p == path and s in line for p, s in allow):
                    continue
                hits.append("%s:%d: %s" % (path, n, line.strip()[:110]))
    return hits


# ---------------------------------------------------------------------------------------------------- c, h: network

def curl_status(url, runner=None):
    """HTTP status of an unauthenticated GET, as a string ('200', '404' ...), 'unreachable' when curl could not connect.
    Redirects are NOT followed: a moved repository must be noticed, not hidden."""
    run = runner or subprocess.run
    try:
        p = run(["curl", "-s", "-o", os.devnull, "-w", "%{http_code}", "--max-time", "30", "-A", "kit-book-go-public-check", url],
                capture_output=True, text=True, timeout=60, env=_curl_env())
    except (OSError, subprocess.TimeoutExpired):
        return "unreachable"
    code = (p.stdout or "").strip()
    return code if code and code != "000" else "unreachable"


def _curl_env():
    """The environment for curl: no token and no netrc, so the answer is what a stranger gets."""
    env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "NETRC", "CURL_HOME")}
    return env


def check_core_public(kits, status=curl_status):
    """Row c1 (repositories) and c2 (pinned commits) for the core Kits; public non-core Kits only warn."""
    bad_repo, bad_commit, warn_non_core = [], [], []
    core = [k for k in kits if k.role == "core"]
    for k in kits:
        parts = kitlock.split_url(k.url)
        if not parts:
            if k.role == "core":
                bad_repo.append("%s: %r is not a GitHub repository address" % (k.name, k.url))
            continue
        org, repo = parts
        if k.role != "core" and k.visibility != "public":
            continue
        code = status("https://github.com/%s/%s" % (org, repo))
        if code != "200":
            said = "could not be reached (network?)" if code == "unreachable" else "answers %s without a login" % code
            (bad_repo if k.role == "core" else warn_non_core).append("%s: https://github.com/%s/%s %s" % (k.name, org, repo, said))
            continue
        if k.role == "core" and kitlock.HEX40.match(k.commit):
            c2 = status("https://github.com/%s/%s/commit/%s" % (org, repo, k.commit))
            if c2 != "200":
                bad_commit.append("%s: commit %s answers %s" % (k.name, k.commit[:12], c2))
        elif k.role == "core":
            bad_commit.append("%s: the pin is not a 40-hex commit" % k.name)
    rows = [row("c1", "core Kits answer HTTP 200, no login",
                FAIL if bad_repo else (OK if core else WARN), "\n".join(bad_repo) if bad_repo else ("" if core else "kits.lock lists no core Kit"))]
    skipped = {b.split(":")[0] for b in bad_repo}
    rows.append(row("c2", "core Kit pins exist (commit page is 200)",
                    FAIL if (bad_commit or skipped) else OK,
                    "\n".join(bad_commit + ["%s: not checked, its repository did not answer" % s for s in sorted(skipped)])))
    if warn_non_core:
        rows.append(row("c3", "public non-core Kits answer 200", WARN, "\n".join(warn_non_core)))
    return rows


def check_visibility(slug, runner=None):
    """Row h1: the repository's own visibility, from `gh repo view --json visibility`."""
    run = runner or subprocess.run
    title = "repository visibility (%s)" % slug
    if not shutil.which("gh") and runner is None:
        return row("h1", title, WARN, "gh is not installed, so the visibility is not known; make the repo public, then re-run")
    try:
        p = run(["gh", "repo", "view", slug, "--json", "visibility"], capture_output=True, text=True, timeout=60)
        vis = json.loads(p.stdout)["visibility"] if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError):
        vis = None
    if vis is None:
        return row("h1", title, WARN, "could not ask GitHub (gh not logged in, or no network); check it by hand, then re-run")
    if vis.upper() == "PUBLIC":
        return row("h1", title, OK, "PUBLIC")
    return row("h1", title, WARN, "%s: make the repo public, then re-run" % vis.upper())


# ------------------------------------------------------------------------------------------------- j: kits.need names

def check_kits_need(kits, needs_by_app):
    names = {k.name for k in kits}
    bad = ["apps/%s/kits.need names '%s', which is not in kits.lock" % (a, n) for a, ns in sorted(needs_by_app.items()) for n in ns if n not in names]
    return row("j2", "kits.need names only Kits in kits.lock", FAIL if bad else OK, "\n".join(bad))


def read_needs(root):
    """{app: [Kit names]} from apps/*/kits.need."""
    out = {}
    apps = os.path.join(root, "apps")
    if not os.path.isdir(apps):
        return out
    for a in sorted(os.listdir(apps)):
        p = os.path.join(apps, a, "kits.need")
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as fh:
                names = [re.sub(r"\s*#.*$", "", l).strip() for l in fh]
            out[a] = [n for n in names if n]
    return out


# ------------------------------------------------------------------------------------------------------------ table

def format_table(rows):
    """The checklist as text, and the counts (ok, warn, fail)."""
    w_id = max([len(r.id) for r in rows] + [1])
    w_title = max([len(r.title) for r in rows] + [5])
    lines = ["%-*s  %-*s  %-6s  %s" % (w_id, "#", w_title, "Check", "Result", "Detail"),
             "%s  %s  %s  %s" % ("-" * w_id, "-" * w_title, "-" * 6, "-" * 40)]
    for r in rows:
        detail = [d[:130] + ("..." if len(d) > 130 else "") for d in (r.detail.splitlines() or [""])]
        lines.append("%-*s  %-*s  %-6s  %s" % (w_id, r.id, w_title, r.title, r.status, detail[0]))
        for extra in detail[1:]:
            lines.append("%s  %s  %s  %s" % (" " * w_id, " " * w_title, " " * 6, extra))
    counts = collections.Counter(r.status for r in rows)
    return "\n".join(lines), (counts[OK], counts[WARN], counts[FAIL])


def verdict(counts, offline=False):
    ok, warn, fail = counts
    line = "%d ok, %d warn, %d FAIL" % (ok, warn, fail)
    if fail:
        return line + ". NOT READY: fix every FAIL, then run make go-public-check again.", 1
    if offline:
        return line + ". INCOMPLETE: the network checks were skipped (GO_PUBLIC_OFFLINE=1), so this is not a pass.", 3
    if warn:
        return line + ". No FAIL. Read each warn: some are expected until the step they name is done.", 0
    return line + ". READY.", 0


# --------------------------------------------------------------------------------------------------- the real checks

def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):   # missing, or a binary file (an image): nothing to scan
        return None


def run(cmd, cwd=ROOT, env=None, timeout=900):
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def tail(text, n=4):
    lines = [l for l in text.strip().splitlines() if l.strip()]
    return "\n".join(l[:150] for l in lines[-n:])


def makefile_value(name):
    for line in (read(os.path.join(ROOT, "Makefile")) or "").splitlines():
        m = re.match(r"^%s\s*\?=\s*(\S+)" % re.escape(name), line)
        if m:
            return m.group(1)
    return None


def tracked_files():
    """Paths of tracked files (git ls-files); without git, every file under the root except .git, .kits and build."""
    p = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, text=True)
    if p.returncode == 0 and p.stdout:
        return [f for f in p.stdout.split("\0") if f]
    out = []
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in (".git", ".kits", "build")]
        out += [os.path.relpath(os.path.join(d, f), ROOT) for f in files]
    return out


def copy_tree(dest):
    """A copy of the working tree (tracked and untracked, not ignored) in dest: what the site build sees, without touching build/."""
    p = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT, capture_output=True, text=True)
    names = [f for f in p.stdout.split("\0") if f] if p.returncode == 0 else tracked_files()
    for f in names:
        src = os.path.join(ROOT, f)
        if os.path.isfile(src):
            os.makedirs(os.path.join(dest, os.path.dirname(f)), exist_ok=True)
            shutil.copy2(src, os.path.join(dest, f), follow_symlinks=True)


def check_a(kits, needs):
    rc, out = run(["make", "--no-print-directory", "check-public"], env={"CHECK_PUBLIC_STRICT": "1"})
    useful = [l for l in out.splitlines() if l.strip() and not l.startswith(("make", "check-public: no hits", "note: kits.lock", "      They are only"))]
    rows = [row("a1", "strict scan: CHECK_PUBLIC_STRICT=1 make check-public", OK if rc == 0 else FAIL, "" if rc == 0 else "\n".join(useful[-6:]))]
    _fails, warns = private_warnings(kits, needs)
    rows.append(row("a2", "private Kits that may stay private", WARN if warns else OK, "\n".join(warns)))
    return rows


def check_d(offline_site_dir):
    rows = []
    for i, target in (("d1", "make docs"), ("d2", "make docs-pull-check")):
        rc, out = run(["make", "--no-print-directory", target.split()[1]])
        rows.append(row(i, target, OK if rc == 0 else FAIL, "" if rc == 0 else tail(out)))
    copy_tree(offline_site_dir)
    env = {"SITE_INDEXABLE": "1"}
    rc, out = run(["make", "--no-print-directory", "site"], cwd=offline_site_dir, env=env)
    built = os.path.isfile(os.path.join(offline_site_dir, "build", "site", "index.html"))
    if rc != 0 or not built:
        why = tail(out) if rc != 0 else "make site built nothing (mdBook missing? see: make site)\n" + tail(out, 2)
        rows.append(row("d3", "make site (SITE_INDEXABLE=1, temp copy)", FAIL, why))
        rows.append(row("d4", "make site-check (SITE_INDEXABLE=1)", FAIL, "no site to check"))
        return rows
    rows.append(row("d3", "make site (SITE_INDEXABLE=1, temp copy)", OK, ""))
    rc, out = run(["make", "--no-print-directory", "site-check"], cwd=offline_site_dir, env=env)
    rows.append(row("d4", "make site-check (SITE_INDEXABLE=1)", OK if rc == 0 else FAIL, "" if rc == 0 else tail(out, 6)))
    return rows


def check_i(site_dir):
    domain = os.environ.get("SITE_DOMAIN") or makefile_value("SITE_DOMAIN")
    cname = read(os.path.join(site_dir, "build", "site-publish", "CNAME"))
    title = "the site's CNAME equals SITE_DOMAIN"
    if cname is None:
        return row("i1", title, FAIL, "no build/site-publish/CNAME was built (see d3)")
    if cname != domain:
        return row("i1", title, FAIL, "CNAME holds %r, SITE_DOMAIN is %r" % (cname, domain))
    return row("i1", title, OK, domain)


def check_j():
    p = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True)
    b = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    if p.returncode != 0:
        return row("j1", "working tree clean, on main", WARN, "not a git checkout")
    branch = (b.stdout or "").strip()
    dirty = [l for l in p.stdout.splitlines() if l.strip()]
    notes = []
    if dirty:
        notes.append("%d uncommitted change(s): commit them, the published site must match a commit" % len(dirty))
    if branch != (makefile_value("SITE_REPO_BRANCH") or "main"):
        notes.append("on branch %s, not %s" % (branch, makefile_value("SITE_REPO_BRANCH") or "main"))
    return row("j1", "working tree clean, on main", WARN if notes else OK, "\n".join(notes))


def main(argv):
    if "--list" in argv or "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    offline = os.environ.get("GO_PUBLIC_OFFLINE") == "1"
    lock_text = read(os.path.join(ROOT, "kits.lock")) or ""
    kits = kitlock.parse_lock(lock_text)
    needs = read_needs(ROOT)
    rows = []

    print("go-public-check: is the Kit Book ready to be made public? (read-only; writes nothing to this working tree)", file=sys.stderr)
    print("  a. strict public-safety scan ...", file=sys.stderr)
    rows += check_a(kits, needs)
    rows += check_lock(lock_text)
    fails, _ = private_warnings(kits, needs)   # a core Kit marked private is reported by a1 (strict scan) and c1
    if offline:
        rows.append(row("c1", "core Kits answer HTTP 200, no login", WARN, "not run (GO_PUBLIC_OFFLINE=1)"))
    else:
        print("  c. asking github.com about each core Kit (no login) ...", file=sys.stderr)
        rows += check_core_public(kits)
    tmp = tempfile.mkdtemp(prefix="go-public-site.")
    try:
        print("  d. make docs, docs-pull-check, then the site in a temporary copy (about a minute) ...", file=sys.stderr)
        rows += check_d(tmp)
        rows += check_notices(set(os.listdir(ROOT)), read(os.path.join(ROOT, "THIRD-PARTY-NOTICES.md")),
                              read(os.path.join(ROOT, "tools", "site", "vendor", "README.md")) or "")
        rc, out = run([sys.executable, os.path.join(HERE, "render-community.py"), "--check"])
        rows += check_community(set(os.listdir(ROOT)),
                                {n: read(os.path.join(ROOT, n)) for n in ("CODE_OF_CONDUCT.md", "SECURITY.md")},
                                read(os.path.join(ROOT, "tools", "contacts.conf")), None if rc == 0 else tail(out, 3))
        allow_entries, allow_errors = parse_allow(read(os.path.join(HERE, "go-public-allow.txt")) or "")
        files = {}
        for f in tracked_files():
            t = read(os.path.join(ROOT, f))
            if t is not None:
                files[f] = t
        hits = find_old_spellings(files, allow_entries)
        rows.append(row("g1", "no old Kit spelling outside go-public-allow.txt",
                        FAIL if (hits or allow_errors) else OK, "\n".join((allow_errors + hits)[:12] + (["... and %d more" % (len(hits) - 10)] if len(hits) > 10 else []))))
        slug = re.sub(r"^https://github\.com/", "", (os.environ.get("SITE_REPO_URL") or makefile_value("SITE_REPO_URL") or "").rstrip("/"))
        if offline:
            rows.append(row("h1", "this repository's visibility", WARN, "not run (GO_PUBLIC_OFFLINE=1)"))
        else:
            rows.append(check_visibility(slug))
        rows.append(check_i(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    rows.append(check_j())
    rows.append(check_kits_need(kits, needs))
    order = lambda r: (re.match(r"[a-z]", r.id).group(0), r.id)  # noqa: E731
    rows.sort(key=order)
    table, counts = format_table(rows)
    text, code = verdict(counts, offline)
    print(table)
    print()
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

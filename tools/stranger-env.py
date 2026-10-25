#!/usr/bin/env python3
"""The environment a stranger has: no GitHub credentials. Used by tools/stranger-test.sh; standard library only.

    python3 tools/stranger-env.py plan              say, by NAME only (never a value), what would be removed from this environment
    python3 tools/stranger-env.py check             run inside the sanitised environment and fail if a credential is still reachable
    python3 tools/stranger-env.py run -- CMD ...    run CMD in the sanitised environment
    python3 tools/stranger-env.py core-kits DIR     after `make setup` in DIR: fail if a core Kit of kits.lock could not be fetched

Sanitising means: the token variables are removed, git may not ask for a password and has no credential helper, and the PATH
has no `gh` on it (a directory that holds gh is replaced by a folder of links to everything else in it).
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitlock  # noqa: E402

# Variables that carry or point at a credential. Names only: values are never printed.
CREDENTIAL_VARS = (
    "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_HOST", "GH_CONFIG_DIR",
    "GIT_ASKPASS", "SSH_ASKPASS", "SSH_AUTH_SOCK", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_COUNT", "NETRC", "CURL_HOME", "CODESPACES", "GITHUB_ACTIONS",
)
# Not credentials, but state of the outer `make` and of this repository's own settings that a stranger would not have.
OUTER_STATE_VARS = ("MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKEOVERRIDES", "KITS", "PUBLISH", "CHECK_PUBLIC_STRICT", "KITS_LOCK",
                    "SITE_DOMAIN", "SITE_TITLE", "SITE_REPO_URL", "SITE_REPO_BRANCH", "SITE_REWRITE_REPO_LINKS", "SITE_INDEXABLE")
CREDENTIAL_PREFIXES = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_", "GIT_CONFIG_PARAMETERS")


def dirs_with(path, program):
    """The PATH entries that hold an executable called `program`."""
    out = []
    for d in path.split(os.pathsep):
        p = os.path.join(d, program)
        if d and os.path.isfile(p) and os.access(p, os.X_OK):
            out.append(d)
    return out


def strip_program_from_path(path, program, farm_root):
    """A PATH without `program`. A directory that holds it is replaced by a folder under farm_root with a link to every
    other entry, so the tools that share the directory (git, make, flutter ...) still resolve. Returns (new path, [replaced dirs])."""
    replaced = []
    parts = []
    for i, d in enumerate(path.split(os.pathsep)):
        if d in dirs_with(path, program) and os.path.isdir(d):
            farm = os.path.join(farm_root, "path%d" % i)
            os.makedirs(farm, exist_ok=True)
            for name in os.listdir(d):
                if name == program:
                    continue
                link = os.path.join(farm, name)
                if not os.path.lexists(link):
                    os.symlink(os.path.join(d, name), link)
            parts.append(farm)
            replaced.append(d)
        else:
            parts.append(d)
    return os.pathsep.join(parts), replaced


def removed_names(env):
    """Names (not values) of the credential variables set in env."""
    return sorted(k for k in env if k in CREDENTIAL_VARS or k.startswith(CREDENTIAL_PREFIXES))


def sanitised_env(env, farm_root):
    """(a copy of env that has no GitHub credentials, [names removed], [PATH dirs replaced]). Nothing in env is modified."""
    new = {k: v for k, v in env.items()
           if k not in CREDENTIAL_VARS and k not in OUTER_STATE_VARS and not k.startswith(CREDENTIAL_PREFIXES)}
    gone = removed_names(env)
    new["PATH"], replaced = strip_program_from_path(env.get("PATH", ""), "gh", farm_root)
    new["GIT_TERMINAL_PROMPT"] = "0"
    new["GIT_ASKPASS"] = "/usr/bin/false"      # any attempt to ask for a password fails at once instead of waiting
    new["GIT_CONFIG_NOSYSTEM"] = "1"
    new["GIT_CONFIG_GLOBAL"] = os.devnull      # no ~/.gitconfig: no credential helper, no URL rewrites
    new["GH_CONFIG_DIR"] = os.path.join(farm_root, "no-gh-config")
    new["NO_COLOR"] = "1"
    return new, gone, replaced


def self_check(env):
    """Problems that mean a credential would still be reachable in env (an empty list means clean)."""
    problems = []
    for k in removed_names(env):
        if k in ("GIT_ASKPASS", "GIT_CONFIG_GLOBAL", "GH_CONFIG_DIR"):
            continue   # set on purpose by sanitised_env, to harmless values
        problems.append("%s is set" % k)
    if shutil.which("gh", path=env.get("PATH", "")):
        problems.append("gh is on PATH")
    if env.get("GIT_TERMINAL_PROMPT") != "0":
        problems.append("GIT_TERMINAL_PROMPT is not 0")
    if env.get("GIT_ASKPASS") != "/usr/bin/false":
        problems.append("GIT_ASKPASS can still ask for a password")
    return problems


def core_kits_not_fetched(lock_text, kits_dir):
    """Kits of role core that kits.lock marks private or that are not in kits_dir at their pinned commit: what a stranger could not get."""
    bad = []
    for k in kitlock.parse_lock(lock_text):
        if k.role != "core":
            continue
        fetched = os.path.join(kits_dir, k.name, ".fetched")
        got = None
        if os.path.isfile(fetched):
            with open(fetched, encoding="utf-8") as fh:
                got = fh.read().strip()
        if k.visibility != "public":
            bad.append("%s is %s in kits.lock: fetching it needs a GitHub login" % (k.name, k.visibility or "not marked public"))
        elif got != k.commit:
            bad.append("%s was not fetched at its pinned commit %s (got %s)" % (k.name, k.commit[:7], (got or "nothing")[:7]))
    return bad


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "plan":
        env = dict(os.environ)
        gone = removed_names(env)
        print("variables that would be removed (names only): %s" % (", ".join(gone) if gone else "none are set"))
        print("PATH directories that hold gh and would be replaced by a link folder without it: %s"
              % (", ".join(dirs_with(env.get("PATH", ""), "gh")) or "none"))
        print("set: GIT_TERMINAL_PROMPT=0, GIT_ASKPASS=/usr/bin/false, GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=%s, GH_CONFIG_DIR=<empty folder>, NO_COLOR=1" % os.devnull)
        return 0
    if cmd in ("check", "run"):
        farm = os.environ.get("STRANGER_FARM") or tempfile.mkdtemp(prefix="stranger-path.")
        env, _gone, _rep = sanitised_env(dict(os.environ), farm)
        if cmd == "check":
            problems = self_check(env)
            for p in problems:
                print("CREDENTIAL REACHABLE: %s" % p, file=sys.stderr)
            if not problems:
                print("sanitised environment: no token variable, no gh on PATH, git cannot ask for a password and has no credential helper")
            return 1 if problems else 0
        if "--" not in argv:
            print("usage: stranger-env.py run -- COMMAND ...", file=sys.stderr)
            return 2
        command = argv[argv.index("--") + 1:]
        if not command:
            print("usage: stranger-env.py run -- COMMAND ...", file=sys.stderr)
            return 2
        if not shutil.which(command[0], path=env["PATH"]):
            print("stranger-env: %s was not found on the sanitised PATH" % command[0], file=sys.stderr)
            return 127
        os.execvpe(command[0], command, env)
    if cmd == "core-kits":
        d = argv[2] if len(argv) > 2 else "."
        with open(os.path.join(d, "kits.lock"), encoding="utf-8") as fh:
            bad = core_kits_not_fetched(fh.read(), os.path.join(d, ".kits"))
        for b in bad:
            print("A STRANGER COULD NOT GET: %s" % b, file=sys.stderr)
        if not bad:
            print("every core Kit in kits.lock is public and was fetched at its pinned commit")
        return 1 if bad else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

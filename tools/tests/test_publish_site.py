"""Tests for tools/publish-site.sh: the dry run, and the push guard, against a local bare repository standing in for origin.

Standard library only; needs git and sh. A stub `gh` on PATH answers `gh repo view ... --json visibility` so nothing here
touches the network or GitHub. The scripts are copied into a throwaway repository, so the real repository is never used.
"""
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
DOMAIN = "kits.example.org"


@unittest.skipUnless(shutil.which("git") and shutil.which("sh"), "needs git and sh")
class PublishSite(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        base = os.path.realpath(self._tmp.name)
        self.repo = os.path.join(base, "work")
        # the path contains github.com so the script treats origin as a GitHub remote
        self.bare = os.path.join(base, "github.com", "org", "repo.git")
        self.stub = os.path.join(base, "stub")
        os.makedirs(os.path.join(self.repo, "tools"))
        os.makedirs(self.stub)
        for f in ("common.sh", "site-env.sh", "publish-site.sh"):
            shutil.copy(os.path.join(TOOLS, f), os.path.join(self.repo, "tools", f))
        with open(os.path.join(self.repo, "Makefile"), "w") as fh:
            fh.write("SITE_DOMAIN ?= %s\nSITE_TITLE ?= T\nSITE_REPO_URL ?= https://github.com/org/repo\n"
                     "SITE_REPO_BRANCH ?= main\nSITE_REWRITE_REPO_LINKS ?= 1\nSITE_INDEXABLE ?= 0\n" % DOMAIN)
        with open(os.path.join(self.repo, ".gitignore"), "w") as fh:
            fh.write("build/\n")
        self.env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.org", GIT_COMMITTER_NAME="t",
                        GIT_COMMITTER_EMAIL="t@example.org", PATH=self.stub + os.pathsep + os.environ["PATH"], NO_COLOR="1")
        for k in ("PUBLISH", "SITE_DOMAIN", "SITE_INDEXABLE", "SITE_REPO_BRANCH"):
            self.env.pop(k, None)
        self.git("init", "-q", "-b", "main", cwd=self.repo)
        self.git("add", "-A", cwd=self.repo)
        self.git("commit", "-q", "-m", "initial", cwd=self.repo)
        os.makedirs(self.bare)
        self.git("init", "-q", "--bare", self.bare, cwd=base)
        self.git("remote", "add", "origin", self.bare, cwd=self.repo)
        self.make_site("<html>one</html>")
        self.visibility("PRIVATE")

    def git(self, *args, cwd=None, check=True):
        p = subprocess.run(["git"] + list(args), cwd=cwd or self.repo, env=self.env, capture_output=True, text=True)
        if check and p.returncode != 0:
            raise AssertionError("git %s failed: %s" % (" ".join(args), p.stderr))
        return p.stdout.strip()

    def visibility(self, value):
        path = os.path.join(self.stub, "gh")
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\necho %s\n" % value)
        os.chmod(path, 0o755)

    def make_site(self, html, cname=DOMAIN):
        pub = os.path.join(self.repo, "build", "site-publish")
        shutil.rmtree(pub, ignore_errors=True)
        os.makedirs(os.path.join(pub, "sub"))
        for rel, text in (("index.html", html), ("sub/p.html", "p"), ("CNAME", cname), (".nojekyll", "")):
            if rel == "CNAME" and cname is None:
                continue
            with open(os.path.join(pub, rel), "w") as fh:
                fh.write(text)

    def publish(self, **extra):
        env = dict(self.env, **extra)
        return subprocess.run(["sh", "tools/publish-site.sh"], cwd=self.repo, env=env, capture_output=True, text=True)

    def remote_branches(self):
        return self.git("for-each-ref", "--format=%(refname)", cwd=self.bare)

    def test_dry_run_builds_a_local_orphan_commit_and_pushes_nothing(self):
        main_before = self.git("rev-parse", "main")
        p = self.publish()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("DRY RUN: nothing was pushed (PUBLISH=1 was not given)", p.stdout)
        self.assertEqual(self.remote_branches(), "")
        self.assertEqual(self.git("rev-list", "--count", "gh-pages"), "1")
        self.assertEqual(self.git("rev-list", "--parents", "-n1", "gh-pages").split(), [self.git("rev-parse", "gh-pages")])
        self.assertEqual(self.git("show", "gh-pages:CNAME"), DOMAIN)
        self.assertEqual(self.git("cat-file", "-s", "gh-pages:.nojekyll"), "0")
        self.assertEqual(self.git("show", "gh-pages:sub/p.html"), "p")
        self.assertEqual(self.git("ls-tree", "--name-only", "gh-pages").split(), [".nojekyll", "CNAME", "index.html", "sub"])
        # main, the working tree and the real index are untouched
        self.assertEqual(self.git("rev-parse", "main"), main_before)
        self.assertEqual(self.git("rev-parse", "--abbrev-ref", "HEAD"), "main")
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_publish_on_a_private_repository_is_a_dry_run(self):
        p = self.publish(PUBLISH="1")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("DRY RUN", p.stdout)
        self.assertIn("visibility: PRIVATE", p.stdout)
        self.assertEqual(self.remote_branches(), "")

    def test_unknown_visibility_is_treated_as_not_public(self):
        os.remove(os.path.join(self.stub, "gh"))
        # without a stub the real gh may exist; make it fail by hiding the PATH entries that hold it
        p = self.publish(PUBLISH="1", PATH=self.stub + os.pathsep + "/usr/bin:/bin")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("DRY RUN", p.stdout)
        self.assertEqual(self.remote_branches(), "")

    def test_public_clean_main_with_publish_pushes_one_commit_and_a_second_publish_replaces_it(self):
        self.visibility("PUBLIC")
        p = self.publish(PUBLISH="1")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("Pushed.", p.stdout)
        self.assertEqual(self.remote_branches(), "refs/heads/gh-pages")
        first = self.git("rev-parse", "refs/heads/gh-pages", cwd=self.bare)
        self.assertEqual(first, self.git("rev-parse", "gh-pages"))
        self.assertEqual(self.git("show", "gh-pages:CNAME", cwd=self.bare), DOMAIN)
        self.make_site("<html>two</html>")
        p = self.publish(PUBLISH="1")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        second = self.git("rev-parse", "refs/heads/gh-pages", cwd=self.bare)
        self.assertNotEqual(first, second)
        self.assertEqual(self.git("rev-list", "--count", "refs/heads/gh-pages", cwd=self.bare), "1")
        self.assertEqual(self.git("show", "gh-pages:index.html", cwd=self.bare), "<html>two</html>")

    def test_only_gh_pages_is_ever_pushed(self):
        self.visibility("PUBLIC")
        self.publish(PUBLISH="1")
        self.assertEqual(self.remote_branches(), "refs/heads/gh-pages")

    def test_dirty_working_tree_blocks_the_push(self):
        self.visibility("PUBLIC")
        with open(os.path.join(self.repo, "new.txt"), "w") as fh:
            fh.write("x")
        p = self.publish(PUBLISH="1")
        self.assertEqual(p.returncode, 0)
        self.assertIn("uncommitted changes", p.stdout)
        self.assertEqual(self.remote_branches(), "")

    def test_other_branch_blocks_the_push(self):
        self.visibility("PUBLIC")
        self.git("checkout", "-q", "-b", "topic")
        p = self.publish(PUBLISH="1")
        self.assertEqual(p.returncode, 0)
        self.assertIn("current branch is topic", p.stdout)
        self.assertEqual(self.remote_branches(), "")

    def test_publish_other_than_1_does_not_push(self):
        self.visibility("PUBLIC")
        for value in ("0", "yes", "true"):
            p = self.publish(PUBLISH=value)
            self.assertEqual(p.returncode, 0)
            self.assertIn("DRY RUN", p.stdout)
        self.assertEqual(self.remote_branches(), "")

    def test_missing_or_wrong_cname_is_refused(self):
        self.make_site("x", cname=None)
        self.assertNotEqual(self.publish().returncode, 0)
        self.make_site("x", cname="other.example.org")
        p = self.publish()
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("CNAME", p.stderr)

    def test_no_built_site_is_refused(self):
        shutil.rmtree(os.path.join(self.repo, "build"))
        p = self.publish()
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("no built site", p.stderr)


if __name__ == "__main__":
    unittest.main()

"""Tests for the per-app Kit requirements (apps/<app>/kits.need): tools/app-gate.sh, the helpers in tools/common.sh, and the
skipping done by tools/test-run.sh, tools/setup.sh's helpers and tools/frb.sh. Standard library only; needs sh.

Each test copies the scripts into a throwaway repository with fake apps and stand-in `flutter` and `cargo` programs that
print what the real ones print, so nothing is built or downloaded and the real working tree is never touched."""
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)

LOCK = """# test lock
core-kit https://github.com/o/core-kit %s public core
storage-kit https://github.com/o/storage-kit %s private app-dep
open-kit https://github.com/o/open-kit %s public app-dep
""" % ("a" * 40, "b" * 40, "c" * 40)

FLUTTER = """#!/bin/sh
# stand-in: `flutter test` prints a progress line the way the real one does
echo "00:01 +3: All tests passed!"
exit 0
"""
CARGO = """#!/bin/sh
case "$1" in
  metadata) echo '{}' ;;
  test) echo "test result: ok. 4 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out" ;;
  *) : ;;
esac
exit 0
"""


@unittest.skipUnless(shutil.which("sh"), "needs sh")
class AppNeeds(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        os.makedirs(os.path.join(self.root, "tools", "tests"))
        for f in ("common.sh", "app-gate.sh", "test-run.sh", "frb.sh"):
            shutil.copy(os.path.join(TOOLS, f), os.path.join(self.root, "tools", f))
        with open(os.path.join(self.root, "kits.lock"), "w") as fh:
            fh.write(LOCK)
        # the maintainer-tools suite that test-run.sh always runs: a trivial passing test
        for name in ("test_pull_docs.py", "test_gen_catalog.py"):   # the second runs only when PyYAML is installed
            with open(os.path.join(self.root, "tools", "tests", name), "w") as fh:
                fh.write("import unittest\nclass T(unittest.TestCase):\n    def test_ok(self):\n        pass\n")
        os.makedirs(os.path.join(self.root, "labs", "interface_candidates"))
        self.stub = os.path.join(self.root, "stub")
        os.makedirs(self.stub)
        for name, body in (("flutter", FLUTTER), ("cargo", CARGO)):
            p = os.path.join(self.stub, name)
            with open(p, "w") as fh:
                fh.write(body)
            os.chmod(p, 0o755)
        self.app("plain")                                             # needs nothing
        self.app("needs_storage", need="# why\nstorage-kit\n", rust=True)
        self.app("needs_open", need="open-kit\n")
        os.makedirs(os.path.join(self.root, ".kits", "core-kit"))    # the App Context Kit stand-in
        os.makedirs(os.path.join(self.root, ".kits", "app-context-kit"))
        with open(os.path.join(self.root, "kits.lock"), "a") as fh:
            fh.write("app-context-kit https://github.com/o/app-context-kit %s public core\n" % ("d" * 40))
        self.env = dict(os.environ, PATH=self.stub + os.pathsep + os.environ["PATH"], NO_COLOR="1")
        self.env.pop("KITS", None)

    def app(self, name, need=None, rust=False):
        d = os.path.join(self.root, "apps", name)
        os.makedirs(d)
        if need is not None:
            with open(os.path.join(d, "kits.need"), "w") as fh:
                fh.write(need)
        if rust:
            os.makedirs(os.path.join(d, "rust"))
            with open(os.path.join(d, "rust", "Cargo.toml"), "w") as fh:
                fh.write("[package]\nname='x'\n")
            with open(os.path.join(d, "flutter_rust_bridge.yaml"), "w") as fh:
                fh.write("x: y\n")
            with open(os.path.join(d, "pubspec.yaml"), "w") as fh:
                fh.write("dependencies:\n  flutter_rust_bridge: 2.12.0\n")

    def fetch(self, name):
        os.makedirs(os.path.join(self.root, ".kits", name), exist_ok=True)

    def sh(self, script, *args):
        return subprocess.run(["sh", os.path.join(self.root, "tools", script)] + list(args), cwd=self.root, env=self.env, capture_output=True, text=True)

    def helper(self, expr):
        """Run a shell expression with common.sh sourced the way the real scripts do (ROOT comes from the script's own folder)."""
        script = os.path.join(self.root, "tools", "_helper.sh")
        with open(script, "w") as fh:
            fh.write('. "$(dirname "$0")/common.sh"\neval "$1"\n')
        p = subprocess.run(["sh", script, expr], cwd=self.root, env=self.env, capture_output=True, text=True)
        return p.stdout.strip()

    # --- the helpers
    def test_needs_ignore_comments_and_blank_lines(self):
        self.assertEqual(self.helper('app_needs "$ROOT/apps/needs_storage"'), "storage-kit")
        self.assertEqual(self.helper('app_needs "$ROOT/apps/plain"'), "")

    def test_reason_names_the_kit_and_how_to_get_it(self):
        self.assertEqual(self.helper('app_skip_reason "$ROOT/apps/needs_storage"'), "needs storage-kit (private; fetch with KITS=all)")
        self.assertEqual(self.helper('app_skip_reason "$ROOT/apps/needs_open"'), "needs open-kit (public; fetch with make setup)")

    def test_a_kit_that_kits_lock_does_not_list_is_said_so(self):
        self.app("odd", need="mystery-kit\n")
        self.assertEqual(self.helper('app_skip_reason "$ROOT/apps/odd"'), "needs mystery-kit (not listed in kits.lock)")

    def test_no_reason_once_the_kit_is_fetched(self):
        self.fetch("storage-kit")
        self.assertEqual(self.helper('app_skip_reason "$ROOT/apps/needs_storage"'), "")
        self.assertIn("needs_storage", self.helper("included_apps"))

    # --- the gate
    def test_gate_is_quiet_and_zero_for_apps_that_can_be_built(self):
        p = self.sh("app-gate.sh", "plain")
        self.assertEqual((p.returncode, p.stdout, p.stderr), (0, "", ""))

    def test_gate_prints_the_one_line_explanation_and_exits_1(self):
        p = self.sh("app-gate.sh", "needs_storage")
        self.assertEqual(p.returncode, 1)
        self.assertEqual(p.stdout.strip(), "skipped apps/needs_storage: needs storage-kit (private; fetch with KITS=all)")

    def test_direct_gate_says_what_to_do_and_exits_2(self):
        p = self.sh("app-gate.sh", "--direct", "needs_storage")
        self.assertEqual(p.returncode, 2)
        self.assertIn("storage-kit", p.stderr)
        self.assertIn("make setup KITS=all", p.stderr)

    def test_gate_for_an_app_that_does_not_exist(self):
        self.assertEqual(self.sh("app-gate.sh", "nope").returncode, 2)

    # --- test-run.sh
    def test_fast_suites_skip_the_app_and_still_pass(self):
        p = self.sh("test-run.sh", "fast")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        out = p.stdout + p.stderr
        self.assertIn("skipped apps/needs_storage: needs storage-kit (private; fetch with KITS=all)", out)
        self.assertIn("skipped apps/needs_open: needs open-kit (public; fetch with make setup)", out)
        self.assertIn("apps/plain: flutter test", out)
        table = [l for l in p.stdout.splitlines() if l.startswith("apps/")]
        self.assertTrue(any(l.startswith("apps/needs_storage") and "skipped" in l for l in table), table)
        self.assertTrue(any(l.startswith("apps/plain") and " pass" in l for l in table), table)
        self.assertNotIn("needs_storage/rust", p.stdout)    # neither its cargo test nor its flutter test is a row of the table
        self.assertTrue(p.stdout.rstrip().endswith("OK"))

    def test_with_the_kit_fetched_the_app_runs_its_suites_as_before(self):
        self.fetch("storage-kit")
        self.fetch("open-kit")
        p = self.sh("test-run.sh", "fast")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        out = p.stdout + p.stderr
        self.assertNotIn("skipped apps/", out)
        self.assertIn("apps/needs_storage/rust: cargo test", out)
        self.assertIn("apps/needs_storage: flutter test", out)

    def test_a_failing_suite_still_fails_the_run(self):
        self.fetch("storage-kit")
        with open(os.path.join(self.stub, "flutter"), "w") as fh:
            fh.write("#!/bin/sh\necho '00:01 +1 -1: Some tests failed.'\nexit 1\n")
        p = self.sh("test-run.sh", "fast")
        self.assertEqual(p.returncode, 1)

    # --- frb.sh
    def test_frb_skips_the_app_and_does_not_fail(self):
        p = self.sh("frb.sh")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("skipped apps/needs_storage: needs storage-kit (private; fetch with KITS=all)", p.stdout)
        self.assertIn("nothing to generate here", p.stdout)


if __name__ == "__main__":
    unittest.main()

"""Tests for CHECK_PUBLIC_STRICT in tools/check-public.sh: only a private Kit with role core fails; a private app-dep is a warning
that names the apps that will be skipped for a stranger. Standard library only; needs sh. Runs in a throwaway repository."""
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
SHA = "a" * 40


@unittest.skipUnless(shutil.which("sh"), "needs sh")
class Strict(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        os.makedirs(os.path.join(self.root, "tools"))
        os.makedirs(os.path.join(self.root, "apps", "needy"))
        for f in ("common.sh", "check-public.sh"):
            shutil.copy(os.path.join(TOOLS, f), os.path.join(self.root, "tools", f))
        with open(os.path.join(self.root, "README.md"), "w") as fh:
            fh.write("# nothing to see\n")
        with open(os.path.join(self.root, "apps", "needy", "kits.need"), "w") as fh:
            fh.write("dep-kit\n")

    def lock(self, *lines):
        with open(os.path.join(self.root, "kits.lock"), "w") as fh:
            fh.write("".join(l + "\n" for l in lines))

    def run_check(self, strict):
        env = dict(os.environ, NO_COLOR="1")
        env.pop("CHECK_PUBLIC_STRICT", None)
        if strict:
            env["CHECK_PUBLIC_STRICT"] = "1"
        return subprocess.run(["sh", os.path.join(self.root, "tools", "check-public.sh")], cwd=self.root, env=env, capture_output=True, text=True)

    CORE_PRIVATE = "core-kit https://github.com/example-org/core-kit %s private core" % SHA
    CORE_PUBLIC = "core-kit https://github.com/example-org/core-kit %s public core" % SHA
    DEP_PRIVATE = "dep-kit https://github.com/example-org/dep-kit %s private app-dep" % SHA

    def test_a_private_core_kit_fails_in_strict_mode_only(self):
        self.lock(self.CORE_PRIVATE)
        self.assertEqual(self.run_check(strict=False).returncode, 0)
        p = self.run_check(strict=True)
        self.assertEqual(p.returncode, 1)
        self.assertIn("core Kit(s) in kits.lock are private: core-kit", p.stderr)

    def test_a_private_app_dep_only_warns_and_names_the_apps(self):
        self.lock(self.CORE_PUBLIC, self.DEP_PRIVATE)
        p = self.run_check(strict=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("warn: dep-kit is a private app-dep: apps/needy will be skipped for a stranger", p.stderr)

    def test_a_private_app_dep_nobody_needs_is_still_not_a_failure(self):
        os.remove(os.path.join(self.root, "apps", "needy", "kits.need"))
        self.lock(self.CORE_PUBLIC, self.DEP_PRIVATE)
        p = self.run_check(strict=True)
        self.assertEqual(p.returncode, 0)
        self.assertIn("no app lists it in kits.need", p.stderr)

    def test_all_public_is_clean(self):
        self.lock(self.CORE_PUBLIC)
        p = self.run_check(strict=True)
        self.assertEqual(p.returncode, 0)
        self.assertNotIn("warn:", p.stderr)


if __name__ == "__main__":
    unittest.main()

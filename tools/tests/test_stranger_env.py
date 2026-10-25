"""Tests for tools/stranger-env.py (the credential-free environment of `make stranger-test`) and for the dry run of
tools/stranger-test.sh. Standard library only; nothing is cloned and nothing touches the network."""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)


def load():
    spec = importlib.util.spec_from_file_location("stranger_env", os.path.join(TOOLS, "stranger-env.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


se = load()


def make_exe(directory, name):
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, name)
    with open(path, "w") as fh:
        fh.write("#!/bin/sh\necho %s\n" % name)
    os.chmod(path, 0o755)
    return path


class Sanitise(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.base = os.path.realpath(self._tmp.name)
        self.bin_with_gh = os.path.join(self.base, "brew")
        self.bin_plain = os.path.join(self.base, "plain")
        for n in ("gh", "make", "flutter"):
            make_exe(self.bin_with_gh, n)
        make_exe(self.bin_plain, "curl")
        self.farm = os.path.join(self.base, "farm")
        self.env = {
            "PATH": os.pathsep.join([self.bin_with_gh, self.bin_plain]), "HOME": "x-home", "GH_TOKEN": "secret-1",
            "GITHUB_TOKEN": "secret-2", "SSH_AUTH_SOCK": "/tmp/agent", "KEEP_ME": "yes",
        }

    def test_token_variables_are_removed_and_the_rest_is_kept(self):
        env, gone, _ = se.sanitised_env(self.env, self.farm)
        for k in ("GH_TOKEN", "GITHUB_TOKEN", "SSH_AUTH_SOCK"):
            self.assertNotIn(k, env)
        self.assertEqual(env["KEEP_ME"], "yes")
        self.assertEqual(env["HOME"], "x-home")
        self.assertEqual(gone, ["GH_TOKEN", "GITHUB_TOKEN", "SSH_AUTH_SOCK"])

    def test_the_names_reported_never_include_values(self):
        _, gone, _ = se.sanitised_env(self.env, self.farm)
        self.assertNotIn("secret-1", " ".join(gone))

    def test_state_of_the_outer_make_is_not_passed_on(self):
        env, gone, _ = se.sanitised_env(dict(self.env, MAKEFLAGS="KITS=all", MAKELEVEL="1", KITS="all", SITE_INDEXABLE="1"), self.farm)
        for k in ("MAKEFLAGS", "MAKELEVEL", "KITS", "SITE_INDEXABLE"):
            self.assertNotIn(k, env)
        self.assertNotIn("KITS", gone)    # only credentials are reported by name

    def test_git_may_not_prompt_and_has_no_helper_or_global_config(self):
        env, _, _ = se.sanitised_env(self.env, self.farm)
        self.assertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(env["GIT_ASKPASS"], "/usr/bin/false")
        self.assertEqual(env["GIT_CONFIG_GLOBAL"], os.devnull)
        self.assertEqual(env["GIT_CONFIG_NOSYSTEM"], "1")

    def test_gh_is_not_on_the_path_but_its_neighbours_still_are(self):
        env, _, replaced = se.sanitised_env(self.env, self.farm)
        self.assertEqual(replaced, [self.bin_with_gh])
        self.assertIsNone(shutil.which("gh", path=env["PATH"]))
        for tool in ("make", "flutter", "curl"):
            self.assertIsNotNone(shutil.which(tool, path=env["PATH"]), tool)
        # the original directory is untouched
        self.assertTrue(os.path.exists(os.path.join(self.bin_with_gh, "gh")))
        self.assertNotIn(self.bin_with_gh, env["PATH"].split(os.pathsep))

    def test_the_input_environment_is_not_modified(self):
        before = dict(self.env)
        se.sanitised_env(self.env, self.farm)
        self.assertEqual(self.env, before)

    def test_self_check_passes_for_a_sanitised_environment_and_fails_for_a_raw_one(self):
        env, _, _ = se.sanitised_env(self.env, self.farm)
        self.assertEqual(se.self_check(env), [])
        problems = se.self_check(self.env)
        self.assertTrue(any("GH_TOKEN" in p for p in problems))
        self.assertTrue(any("gh is on PATH" in p for p in problems))

    def test_a_token_variable_that_slips_back_in_is_caught(self):
        env, _, _ = se.sanitised_env(self.env, self.farm)
        env["GITHUB_TOKEN"] = "x"
        self.assertEqual(se.self_check(env), ["GITHUB_TOKEN is set"])
        env2, _, _ = se.sanitised_env(self.env, self.farm)
        env2["PATH"] = self.bin_with_gh + os.pathsep + env2["PATH"]
        self.assertEqual(se.self_check(env2), ["gh is on PATH"])

    def test_git_config_injection_variables_are_removed(self):
        env, gone, _ = se.sanitised_env(dict(self.env, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="credential.helper", GIT_CONFIG_VALUE_0="store"), self.farm)
        for k in ("GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"):
            self.assertNotIn(k, env)
            self.assertIn(k, gone)

    def test_run_executes_in_the_sanitised_environment(self):
        script = "echo token=${GH_TOKEN:-none}; command -v gh || echo no-gh"
        p = subprocess.run([sys.executable, os.path.join(TOOLS, "stranger-env.py"), "run", "--", "sh", "-c", script],
                           env=dict(os.environ, GH_TOKEN="secret-1", STRANGER_FARM=self.farm), capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("token=none", p.stdout)
        self.assertNotIn("secret-1", p.stdout + p.stderr)
        self.assertIn("no-gh", p.stdout)


class CoreKits(unittest.TestCase):
    SHA = "a" * 40

    def lock(self, vis="public", role="core"):
        return "app-context-kit https://github.com/o/app-context-kit %s %s %s\n" % (self.SHA, vis, role)

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.kits = self._tmp.name

    def fetched(self, commit):
        os.makedirs(os.path.join(self.kits, "app-context-kit"))
        with open(os.path.join(self.kits, "app-context-kit", ".fetched"), "w") as fh:
            fh.write(commit + "\n")

    def test_public_core_fetched_at_its_pin_is_fine(self):
        self.fetched(self.SHA)
        self.assertEqual(se.core_kits_not_fetched(self.lock(), self.kits), [])

    def test_private_core_means_a_stranger_cannot_get_it_even_if_it_is_there(self):
        self.fetched(self.SHA)
        bad = se.core_kits_not_fetched(self.lock("private"), self.kits)
        self.assertEqual(len(bad), 1)
        self.assertIn("GitHub login", bad[0])

    def test_public_core_that_was_skipped_or_is_at_another_commit_is_reported(self):
        self.assertEqual(len(se.core_kits_not_fetched(self.lock(), self.kits)), 1)
        self.fetched("b" * 40)
        self.assertEqual(len(se.core_kits_not_fetched(self.lock(), self.kits)), 1)

    def test_non_core_kits_are_not_required(self):
        self.assertEqual(se.core_kits_not_fetched(self.lock("private", "app-dep"), self.kits), [])


@unittest.skipUnless(shutil.which("sh") and shutil.which("python3"), "needs sh and python3")
class DryRun(unittest.TestCase):
    def run_script(self, **env):
        e = dict(os.environ, STRANGER_DRY="1", GH_TOKEN="secret-1", **env)
        return subprocess.run(["sh", os.path.join(TOOLS, "stranger-test.sh")], env=e, capture_output=True, text=True)

    def test_dry_run_prints_the_plan_clones_nothing_and_never_prints_a_token(self):
        p = self.run_script()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("STRANGER_DRY=1: nothing was cloned or run", p.stdout)
        self.assertIn("https://github.com/slash-builder/kit-book", p.stdout)
        self.assertIn("make doctor", p.stdout)
        self.assertIn("make setup", p.stdout)
        self.assertIn("make test-fast", p.stdout)
        self.assertIn("GH_TOKEN", p.stdout)            # the name, as something that would be removed
        self.assertNotIn("secret-1", p.stdout + p.stderr)

    def test_the_repository_comes_from_a_variable(self):
        p = self.run_script(STRANGER_REPO_URL="https://github.com/example/other")
        self.assertIn("https://github.com/example/other", p.stdout)

    def test_unknown_step_is_refused(self):
        p = self.run_script(STRANGER_STEPS="doctor frobnicate")
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()

"""Tests for the pure parts of tools/go-public-check.py (the launch gate). Standard library only; nothing here touches the network,
GitHub or the real working tree: curl and gh are replaced by stand-ins."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g = load("go_public_check", "go-public-check.py")
kitlock = load("kitlock_t", "kitlock.py")
SHA40 = "a" * 40
GOOD_LOCK = """# comment
app-context-kit https://github.com/example-org/app-context-kit %s public core
storage-kit https://github.com/example-org/storage-kit %s public app-dep
""" % (SHA40, "b" * 40)


def by_id(rows):
    return {r.id: r for r in rows}


class Lock(unittest.TestCase):
    def test_clean_lock_passes_every_row(self):
        rows = g.check_lock(GOOD_LOCK)
        self.assertEqual([r.status for r in rows], ["ok"] * 4)

    def test_url_repo_must_match_the_kit_name(self):
        r = by_id(g.check_lock(GOOD_LOCK.replace("example-org/app-context-kit", "example-org/application-kit")))
        self.assertEqual(r["b1"].status, "FAIL")
        self.assertIn("application-kit", r["b1"].detail)
        self.assertEqual(r["b3"].status, "FAIL")   # the old spelling is caught separately

    def test_dot_git_suffix_is_accepted_and_a_non_github_url_is_not(self):
        r = by_id(g.check_lock(GOOD_LOCK.replace("app-context-kit https://github.com/example-org/app-context-kit",
                                                 "app-context-kit https://github.com/example-org/app-context-kit.git")))
        self.assertEqual(r["b1"].status, "ok")
        r = by_id(g.check_lock(GOOD_LOCK.replace("https://github.com/example-org/storage-kit", "https://example.org/storage-kit")))
        self.assertEqual(r["b1"].status, "FAIL")

    def test_rename_marker_in_a_comment_fails(self):
        r = by_id(g.check_lock("# RENAMED AT RELEASE: do the switch\n" + GOOD_LOCK))
        self.assertEqual(r["b2"].status, "FAIL")
        self.assertIn("line(s) 1", r["b2"].detail)

    def test_old_spellings_are_found_in_comments_and_lines_case_insensitively(self):
        for text in ("# was AppKit\n", "# application_kit\n", "# the Application-Kit repo\n"):
            self.assertEqual(by_id(g.check_lock(text + GOOD_LOCK))["b3"].status, "FAIL", text)

    def test_pin_must_be_40_lowercase_hex(self):
        for bad in ("abc1234", "A" * 40, "a" * 39, "g" * 40):
            r = by_id(g.check_lock(GOOD_LOCK.replace(SHA40, bad)))
            self.assertEqual(r["b4"].status, "FAIL", bad)

    def test_short_line_is_reported_not_raised(self):
        rows = g.check_lock("only-a-name\n")
        self.assertTrue(any(r.status == "FAIL" for r in rows))


class PrivateKits(unittest.TestCase):
    def kits(self, text):
        return kitlock.parse_lock(text)

    def test_private_core_fails(self):
        fails, warns = g.private_warnings(self.kits("a https://github.com/o/a %s private core\n" % SHA40), {})
        self.assertEqual(len(fails), 1)
        self.assertEqual(warns, [])

    def test_private_app_dep_warns_and_names_the_apps(self):
        kits = self.kits("storage-kit https://github.com/o/storage-kit %s private app-dep\n" % SHA40)
        fails, warns = g.private_warnings(kits, {"notes_rust": ["storage-kit"], "calc": []})
        self.assertEqual(fails, [])
        self.assertEqual(len(warns), 1)
        self.assertIn("apps/notes_rust", warns[0])
        self.assertNotIn("calc", warns[0])

    def test_private_app_dep_that_no_app_needs_is_still_only_a_warning(self):
        kits = self.kits("x https://github.com/o/x %s private app-dep\n" % SHA40)
        fails, warns = g.private_warnings(kits, {})
        self.assertEqual((len(fails), len(warns)), (0, 1))

    def test_private_reference_warns_and_public_is_silent(self):
        kits = self.kits("r https://github.com/o/r %s private reference\np https://github.com/o/p %s public core\n" % (SHA40, SHA40))
        fails, warns = g.private_warnings(kits, {})
        self.assertEqual((len(fails), len(warns)), (0, 1))


class Network(unittest.TestCase):
    def kits(self):
        return kitlock.parse_lock(GOOD_LOCK)

    def test_core_answering_200_for_repo_and_commit_passes(self):
        asked = []

        def status(url):
            asked.append(url)
            return "200"

        r = by_id(g.check_core_public(self.kits(), status))
        self.assertEqual((r["c1"].status, r["c2"].status), ("ok", "ok"))
        self.assertIn("https://github.com/example-org/app-context-kit/commit/" + SHA40, asked)

    def test_a_core_repo_that_404s_fails_and_its_commit_is_not_claimed_ok(self):
        r = by_id(g.check_core_public(self.kits(), lambda url: "404"))
        self.assertEqual(r["c1"].status, "FAIL")
        self.assertIn("404", r["c1"].detail)
        self.assertEqual(r["c2"].status, "FAIL")

    def test_missing_commit_fails_c2_only(self):
        def status(url):
            return "404" if "/commit/" in url else "200"

        r = by_id(g.check_core_public(self.kits(), status))
        self.assertEqual((r["c1"].status, r["c2"].status), ("ok", "FAIL"))

    def test_a_redirect_is_not_a_200(self):
        r = by_id(g.check_core_public(self.kits(), lambda url: "301"))
        self.assertEqual(r["c1"].status, "FAIL")

    def test_private_non_core_is_not_asked_and_public_non_core_only_warns(self):
        kits = kitlock.parse_lock("s https://github.com/o/s %s private app-dep\nt https://github.com/o/t %s public app-dep\n" % (SHA40, SHA40))
        asked = []

        def status(url):
            asked.append(url)
            return "404"

        r = by_id(g.check_core_public(kits, status))
        self.assertEqual(asked, ["https://github.com/o/t"])
        self.assertEqual(r["c3"].status, "warn")
        self.assertEqual(r["c1"].status, "warn")   # no core Kit at all is not a pass

    def test_curl_status_runs_without_tokens_and_does_not_follow_redirects(self):
        seen = {}

        def runner(cmd, **kw):
            seen["cmd"], seen["env"] = cmd, kw["env"]
            return subprocess.CompletedProcess(cmd, 0, stdout="200", stderr="")

        old = os.environ.get("GITHUB_TOKEN")
        os.environ["GITHUB_TOKEN"] = "x"
        try:
            self.assertEqual(g.curl_status("https://github.com/o/r", runner), "200")
        finally:
            if old is None:
                del os.environ["GITHUB_TOKEN"]
            else:
                os.environ["GITHUB_TOKEN"] = old
        self.assertNotIn("-L", seen["cmd"])
        self.assertNotIn("GITHUB_TOKEN", seen["env"])
        self.assertNotIn("Authorization", " ".join(seen["cmd"]))

    def test_curl_000_means_unreachable(self):
        self.assertEqual(g.curl_status("u", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 7, stdout="000", stderr="")), "unreachable")

    def test_visibility_private_warns_public_passes_unknown_warns(self):
        def run_with(out, rc=0):
            return lambda cmd, **kw: subprocess.CompletedProcess(cmd, rc, stdout=out, stderr="")

        self.assertEqual(g.check_visibility("o/r", run_with('{"visibility":"PRIVATE"}')).status, "warn")
        self.assertIn("make the repo public, then re-run", g.check_visibility("o/r", run_with('{"visibility":"PRIVATE"}')).detail)
        self.assertEqual(g.check_visibility("o/r", run_with('{"visibility":"PUBLIC"}')).status, "ok")
        self.assertEqual(g.check_visibility("o/r", run_with("", 1)).status, "warn")
        self.assertEqual(g.check_visibility("o/r", run_with("not json")).status, "warn")


class Notices(unittest.TestCase):
    README = "| Version | 12.2.0 |\n```text\n%s  mermaid.min.js\n```\n" % ("c" * 64)

    def test_vendor_facts(self):
        self.assertEqual(g.vendor_facts(self.README), ("12.2.0", "c" * 64))
        self.assertEqual(g.vendor_facts("nothing"), (None, None))

    def test_licences_and_notices_present_and_naming_version_and_sha(self):
        rows = by_id(g.check_notices({"LICENSE", "LICENSE-docs"}, "mermaid 12.2.0 sha " + "c" * 64, self.README))
        self.assertEqual((rows["e1"].status, rows["e2"].status), ("ok", "ok"))

    def test_missing_licence_file_and_missing_notices(self):
        rows = by_id(g.check_notices({"LICENSE"}, None, self.README))
        self.assertEqual(rows["e1"].status, "FAIL")
        self.assertIn("LICENSE-docs", rows["e1"].detail)
        self.assertEqual(rows["e2"].status, "FAIL")

    def test_notices_without_the_version_or_the_sha_fail(self):
        for text in ("mermaid 12.1.0 " + "c" * 64, "mermaid 12.2.0 " + "d" * 64):
            self.assertEqual(by_id(g.check_notices({"LICENSE", "LICENSE-docs"}, text, self.README))["e2"].status, "FAIL")


class Community(unittest.TestCase):
    CONTACTS = "CONDUCT_CONTACT=conduct@example.org\nSECURITY_CONTACT=https://example.org/security\n"
    FILES = {"CODE_OF_CONDUCT.md": "ok text", "SECURITY.md": "ok text"}

    def test_everything_set_passes(self):
        rows = g.check_community(set(), self.FILES, self.CONTACTS, None)
        self.assertEqual({r.status for r in rows}, {"ok"})

    def test_empty_contacts_fail_with_the_instruction(self):
        rows = by_id(g.check_community(set(), self.FILES, "CONDUCT_CONTACT=\nSECURITY_CONTACT=\n", None))
        self.assertEqual(rows["f1"].status, "FAIL")
        self.assertIn("set CONDUCT_CONTACT and SECURITY_CONTACT in tools/contacts.conf", rows["f1"].detail)

    def test_the_visible_marker_and_other_placeholders_fail(self):
        for bad in ("at [CONTACT NOT SET].", "[INSERT CONTACT METHOD]", "at {{CONDUCT_CONTACT}}"):
            rows = by_id(g.check_community(set(), {"CODE_OF_CONDUCT.md": bad, "SECURITY.md": "x"}, self.CONTACTS, None))
            self.assertEqual(rows["f2"].status, "FAIL", bad)

    def test_missing_file_fails(self):
        rows = by_id(g.check_community(set(), {"SECURITY.md": "x"}, self.CONTACTS, None))
        self.assertEqual(rows["f2"].status, "FAIL")

    def test_malformed_contact_fails(self):
        rows = by_id(g.check_community(set(), self.FILES, "CONDUCT_CONTACT=call me\nSECURITY_CONTACT=a@b.org\n", None))
        self.assertEqual(rows["f1b"].status, "FAIL")

    def test_stale_render_fails(self):
        rows = by_id(g.check_community(set(), self.FILES, self.CONTACTS, "SECURITY.md is not a fresh render"))
        self.assertEqual(rows["f3"].status, "FAIL")


class OldSpellings(unittest.TestCase):
    def test_parse_allow(self):
        entries, errors = g.parse_allow("# c\n\nbook/x.md :: example-org/application-kit\n")
        self.assertEqual((entries, errors), ([("book/x.md", "example-org/application-kit")], []))

    def test_kits_lock_may_not_be_allowed(self):
        entries, errors = g.parse_allow("kits.lock :: application-kit\n")
        self.assertEqual(entries, [])
        self.assertIn("kits.lock may not be allowed", errors[0])

    def test_malformed_allow_lines_are_errors(self):
        _, errors = g.parse_allow("just a path\n:: x\n")
        self.assertEqual(len(errors), 2)

    def test_hits_are_found_and_the_allowlist_covers_only_its_own_line(self):
        files = {"a.md": "fine\nthe application-kit repo\nAppKit again\n", "b.md": "nothing", "kits.lock": "x application-kit y\n"}
        hits = g.find_old_spellings(files, [("a.md", "the application-kit repo")])
        self.assertEqual(len(hits), 2)
        self.assertTrue(any(h.startswith("a.md:3:") for h in hits))
        self.assertTrue(any(h.startswith("kits.lock:1:") for h in hits))

    def test_allow_entry_for_another_file_does_not_cover(self):
        hits = g.find_old_spellings({"a.md": "application-kit"}, [("b.md", "application-kit")])
        self.assertEqual(len(hits), 1)

    def test_file_names_count_and_the_new_name_is_fine(self):
        hits = g.find_old_spellings({"docs/application_kit.md": "x", "docs/app-context-kit.md": "App Context Kit app-context-kit"}, [])
        self.assertEqual(hits, ["docs/application_kit.md: the file name itself"])

    def test_the_tools_that_spell_the_patterns_are_not_scanned(self):
        self.assertEqual(g.find_old_spellings({"tools/go-public-allow.txt": "application-kit", "tools/go-public-check.py": "appkit"}, []), [])


class KitsNeed(unittest.TestCase):
    def test_read_needs_and_unknown_names(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "apps", "a"))
            os.makedirs(os.path.join(d, "apps", "b"))
            with open(os.path.join(d, "apps", "a", "kits.need"), "w") as fh:
                fh.write("# why\nstorage-kit  # trailing\n\nmystery-kit\n")
            needs = g.read_needs(d)
            self.assertEqual(needs, {"a": ["storage-kit", "mystery-kit"]})
            row = g.check_kits_need(kitlock.parse_lock(GOOD_LOCK), needs)
            self.assertEqual(row.status, "FAIL")
            self.assertIn("mystery-kit", row.detail)
            self.assertEqual(g.check_kits_need(kitlock.parse_lock(GOOD_LOCK), {"a": ["storage-kit"]}).status, "ok")


class Table(unittest.TestCase):
    def test_table_counts_and_verdicts(self):
        rows = [g.Row("a1", "first", "ok", ""), g.Row("b1", "second", "warn", "say what\nmore"), g.Row("c1", "third", "FAIL", "why")]
        table, counts = g.format_table(rows)
        self.assertEqual(counts, (1, 1, 1))
        self.assertIn("FAIL", table)
        self.assertIn("more", table)
        text, code = g.verdict(counts)
        self.assertEqual(code, 1)
        self.assertIn("NOT READY", text)

    def test_warn_only_exits_zero_ready_only_when_clean_and_offline_is_never_a_pass(self):
        self.assertEqual(g.verdict((3, 1, 0))[1], 0)
        self.assertIn("READY", g.verdict((3, 0, 0))[0])
        self.assertEqual(g.verdict((3, 0, 0), offline=True)[1], 3)
        self.assertEqual(g.verdict((3, 0, 1), offline=True)[1], 1)


if __name__ == "__main__":
    unittest.main()

"""Tests for tools/render-community.py (CODE_OF_CONDUCT.md and SECURITY.md from templates and tools/contacts.conf).
Standard library only; each test builds a tiny repository layout in a temporary folder."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)


def load():
    spec = importlib.util.spec_from_file_location("render_community", os.path.join(TOOLS, "render-community.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rc = load()


class Pure(unittest.TestCase):
    def test_parse_contacts(self):
        c = rc.parse_contacts("# c\n\nCONDUCT_CONTACT = a@b.org \nSECURITY_CONTACT=\n")
        self.assertEqual(c, {"CONDUCT_CONTACT": "a@b.org", "SECURITY_CONTACT": ""})

    def test_missing_keys_default_to_empty_and_unknown_keys_are_errors(self):
        self.assertEqual(rc.parse_contacts(""), {"CONDUCT_CONTACT": "", "SECURITY_CONTACT": ""})
        with self.assertRaises(ValueError):
            rc.parse_contacts("CONDUCT_CONTAKT=x\n")
        with self.assertRaises(ValueError):
            rc.parse_contacts("not a setting\n")

    def test_empty_contact_becomes_the_visible_marker_and_a_banner(self):
        out = rc.render("{{DRAFT_BANNER}}at {{CONDUCT_CONTACT}} ({{REPO_URL}})", {"CONDUCT_CONTACT": "", "SECURITY_CONTACT": "s@x.org"}, "https://h/r", ("CONDUCT_CONTACT",))
        self.assertIn("at [CONTACT NOT SET] (https://h/r)", out)
        self.assertIn("Draft", out)

    def test_set_contact_has_no_marker_and_no_banner(self):
        out = rc.render("{{DRAFT_BANNER}}at {{CONDUCT_CONTACT}}", {"CONDUCT_CONTACT": "c@x.org", "SECURITY_CONTACT": ""}, "u", ("CONDUCT_CONTACT",))
        self.assertEqual(out, "at c@x.org")

    def test_unknown_placeholder_is_an_error(self):
        with self.assertRaises(ValueError):
            rc.render("{{NOPE}}", {}, "u", ())


class Layout(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        os.makedirs(os.path.join(self.root, "tools", "community"))
        with open(os.path.join(self.root, "Makefile"), "w") as fh:
            fh.write("SITE_REPO_URL ?= https://github.com/o/r\n")
        for name, body in (("CODE_OF_CONDUCT.md.tpl", "{{DRAFT_BANNER}}report to {{CONDUCT_CONTACT}}\n"), ("SECURITY.md.tpl", "{{DRAFT_BANNER}}write {{SECURITY_CONTACT}} or {{REPO_URL}}/x\n")):
            with open(os.path.join(self.root, "tools", "community", name), "w") as fh:
                fh.write(body)
        self.set_contacts("", "")

    def set_contacts(self, conduct, security):
        with open(os.path.join(self.root, "tools", "contacts.conf"), "w") as fh:
            fh.write("CONDUCT_CONTACT=%s\nSECURITY_CONTACT=%s\n" % (conduct, security))

    def run_tool(self, *args):
        return subprocess.run([sys.executable, os.path.join(TOOLS, "render-community.py"), "--root", self.root] + list(args), capture_output=True, text=True)

    def read(self, name):
        with open(os.path.join(self.root, name)) as fh:
            return fh.read()

    def test_empty_contacts_render_with_the_marker_and_a_loud_warning(self):
        p = self.run_tool()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("[CONTACT NOT SET]", self.read("CODE_OF_CONDUCT.md"))
        self.assertIn("[CONTACT NOT SET]", self.read("SECURITY.md"))
        self.assertIn("WARNING", p.stderr)

    def test_final_fails_when_a_contact_is_empty_and_writes_nothing(self):
        self.set_contacts("c@x.org", "")
        p = self.run_tool("--final")
        self.assertEqual(p.returncode, 1)
        self.assertIn("SECURITY_CONTACT", p.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.root, "SECURITY.md")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "CODE_OF_CONDUCT.md")))

    def test_final_with_both_contacts_writes_clean_files(self):
        self.set_contacts("conduct@x.org", "security@x.org")
        p = self.run_tool("--final")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.read("CODE_OF_CONDUCT.md"), "report to conduct@x.org\n")
        self.assertEqual(self.read("SECURITY.md"), "write security@x.org or https://github.com/o/r/x\n")
        self.assertNotIn("WARNING", p.stderr)

    def test_check_detects_a_stale_or_missing_file(self):
        self.run_tool()
        self.assertEqual(self.run_tool("--check").returncode, 0)
        self.set_contacts("conduct@x.org", "")
        p = self.run_tool("--check")
        self.assertEqual(p.returncode, 1)
        self.assertIn("make community", p.stderr)
        os.remove(os.path.join(self.root, "SECURITY.md"))
        self.assertIn("missing", self.run_tool("--check").stderr)


class RealRepository(unittest.TestCase):
    """The committed templates, as they are in this repository."""

    def test_covenant_template_differs_from_the_official_text_only_in_the_contact(self):
        with open(os.path.join(TOOLS, "community", "CODE_OF_CONDUCT.md.tpl"), encoding="utf-8") as fh:
            t = fh.read()
        self.assertEqual(t.count("{{CONDUCT_CONTACT}}"), 1)
        self.assertIn("sha256 of that file as fetched:", t)
        self.assertIn("## Attribution", t)
        self.assertIn("Contributor Covenant", t)
        self.assertIn("version 2.1", t)

    def test_committed_files_are_a_fresh_render(self):
        out, _empty = rc.render_all(ROOT)
        for name, text in out.items():
            with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
                self.assertEqual(fh.read(), text, name)


if __name__ == "__main__":
    unittest.main()

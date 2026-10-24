"""Tests for tools/site-stage.py (stages book/ for the website and sends links that leave the book to GitHub).

Standard library only. Every test builds a small fake repository in a temporary folder.
"""
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
URL = "https://github.com/org/repo"


def load():
    spec = importlib.util.spec_from_file_location("site_stage", os.path.join(TOOLS, "site-stage.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


stage_mod = load()


class Repo(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        self.book = os.path.join(self.root, "book")
        self.dest = os.path.join(self.root, "build", "site-src")
        for d in ("book/guides", "book/kits", "apps/calc", "labs/x"):
            os.makedirs(os.path.join(self.root, d))
        for f, text in (("apps/calc/README.md", "calc"), ("labs/x/README.md", "x"), ("CONTRIBUTING.md", "c"),
                        ("book/kits/README.md", "# Kits"), ("book/kits/a.md", "# A")):
            self.write(f, text)

    def write(self, rel, text):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)

    def read_staged(self, rel):
        with open(os.path.join(self.dest, rel), encoding="utf-8") as fh:
            return fh.read()

    def run_stage(self, rewrite=True):
        warnings, listing = [], []
        result = stage_mod.stage(self.book, self.dest, self.root, URL, "main", rewrite, warnings, listing)
        return result, warnings, listing


class RewriteTests(Repo):
    def test_file_link_becomes_blob_and_folder_link_becomes_tree(self):
        self.write("book/guides/g.md", "See [calc](../../apps/calc/README.md) and [labs](../../labs/x/) and [c](../../CONTRIBUTING.md).\n")
        (n, pages, _), warnings, _ = self.run_stage()
        self.assertEqual((n, pages), (3, 1))
        self.assertEqual(warnings, [])
        self.assertEqual(
            self.read_staged("guides/g.md"),
            "See [calc](%s/blob/main/apps/calc/README.md) and [labs](%s/tree/main/labs/x) and [c](%s/blob/main/CONTRIBUTING.md).\n"
            % (URL, URL, URL))

    def test_in_book_links_external_links_and_anchors_are_left_alone(self):
        text = "[a](../kits/a.md#x) [b](b.md) [w](https://example.com/apps/) [m](mailto:a@b.c) [h](#top) [r](/abs)\n"
        self.write("book/guides/g.md", text)
        (n, _, _), _, _ = self.run_stage()
        self.assertEqual(n, 0)
        self.assertEqual(self.read_staged("guides/g.md"), text)

    def test_code_fences_and_code_spans_are_left_alone(self):
        text = "`[x](../../apps/calc/README.md)`\n\n```md\n[x](../../apps/calc/README.md)\n```\n\n[real](../../apps/calc/README.md)\n"
        self.write("book/guides/g.md", text)
        (n, _, _), _, _ = self.run_stage()
        self.assertEqual(n, 1)
        staged = self.read_staged("guides/g.md")
        self.assertEqual(staged.count("../../apps/calc/README.md"), 2)
        self.assertIn("[real](%s/blob/main/apps/calc/README.md)" % URL, staged)

    def test_fragment_is_kept_and_reference_definitions_are_rewritten(self):
        self.write("book/guides/g.md", "[c][1]\n\n[1]: ../../CONTRIBUTING.md#rules\n[t](../../apps/calc/README.md#L10)\n")
        (n, _, _), _, _ = self.run_stage()
        self.assertEqual(n, 2)
        staged = self.read_staged("guides/g.md")
        self.assertIn("[1]: %s/blob/main/CONTRIBUTING.md#rules" % URL, staged)
        self.assertIn("(%s/blob/main/apps/calc/README.md#L10)" % URL, staged)

    def test_images_and_missing_targets_are_not_rewritten_and_missing_ones_warn(self):
        self.write("book/guides/g.md", "![i](../../apps/calc/README.md) [gone](../../apps/none/README.md)\n")
        (n, _, _), warnings, _ = self.run_stage()
        self.assertEqual(n, 0)
        self.assertEqual(len(warnings), 1)
        self.assertIn("does not exist", warnings[0])

    def test_kits_folder_and_outside_the_repository_are_not_rewritten(self):
        self.write("book/guides/g.md", "[k](../../.kits/x/README.md) [o](../../../elsewhere)\n")
        (n, _, _), warnings, _ = self.run_stage()
        self.assertEqual(n, 0)
        self.assertEqual(len(warnings), 2)

    def test_switch_off_copies_without_rewriting_repo_links(self):
        text = "[calc](../../apps/calc/README.md)\n"
        self.write("book/guides/g.md", text)
        (n, pages, _), _, _ = self.run_stage(rewrite=False)
        self.assertEqual((n, pages), (0, 0))
        self.assertEqual(self.read_staged("guides/g.md"), text)

    def test_book_itself_is_never_modified(self):
        text = "[calc](../../apps/calc/README.md)\n"
        self.write("book/guides/g.md", text)
        self.run_stage()
        with open(os.path.join(self.book, "guides", "g.md"), encoding="utf-8") as fh:
            self.assertEqual(fh.read(), text)

    def test_stage_replaces_an_old_staged_copy(self):
        os.makedirs(self.dest)
        self.write("build/site-src/stale.md", "old")
        self.run_stage()
        self.assertFalse(os.path.exists(os.path.join(self.dest, "stale.md")))

    def test_special_characters_are_percent_encoded(self):
        self.write("apps/my app/README.md", "x")
        self.write("book/guides/g.md", "[a](<../../apps/my app/README.md>)\n")
        self.run_stage()
        self.assertIn("<%s/blob/main/apps/my%%20app/README.md>" % URL, self.read_staged("guides/g.md"))


class ReadmeTests(Repo):
    def test_in_book_readme_link_becomes_index_even_with_the_switch_off(self):
        self.write("book/guides/g.md", "[k](../kits/README.md#top) [k2](../kits/README.md)\n")
        (n, _, readmes), _, _ = self.run_stage(rewrite=False)
        self.assertEqual((n, readmes), (0, 2))
        self.assertEqual(self.read_staged("guides/g.md"), "[k](../kits/index.md#top) [k2](../kits/index.md)\n")

    def test_summary_is_left_alone_because_it_names_the_real_files(self):
        self.write("book/SUMMARY.md", "- [Kits](kits/README.md)\n")
        self.run_stage()
        self.assertEqual(self.read_staged("SUMMARY.md"), "- [Kits](kits/README.md)\n")

    def test_a_folder_that_already_has_an_index_keeps_its_readme_link(self):
        self.write("book/kits/index.md", "# i")
        self.write("book/guides/g.md", "[k](../kits/README.md)\n")
        (_, _, readmes), _, _ = self.run_stage()
        self.assertEqual(readmes, 0)


if __name__ == "__main__":
    unittest.main()

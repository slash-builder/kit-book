"""Tests for the pure parts of tools/gen-third-party-notices.py (no network): reading a bundle's package list, grouping licence
texts, flagging licences, and the committed THIRD-PARTY-NOTICES.md itself. Standard library only."""
import importlib.util
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)


def load():
    spec = importlib.util.spec_from_file_location("gen_notices", os.path.join(TOOLS, "gen-third-party-notices.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gn = load()

BUNDLE = """
  // ../../node_modules/.pnpm/d3-array@3.2.4/node_modules/d3-array/src/index.js
  var x = 1;
  // ../../node_modules/.pnpm/d3-array@2.12.1/node_modules/d3-array/src/index.js
  // ../../node_modules/.pnpm/@iconify+utils@3.0.2/node_modules/@iconify/utils/lib/icon/defaults.js
  // ../../node_modules/.pnpm/cytoscape-fcose@2.2.0_cytoscape@3.34.0/node_modules/cytoscape-fcose/src/index.js
  // ../../node_modules/.pnpm/roughjs@4.6.6_patch_hash=3543d47108cb41b68ec6a671c0e1f9d0cfe2ce524fea5b0992511ae84c3c6b64/node_modules/roughjs/bundled/rough.esm.js
  // src/diagrams/c4/parser/c4Diagram.jison
  // ../parser/dist/chunks/mermaid-parser.core/chunk-NGNAAXSQ.mjs
"""


class Pure(unittest.TestCase):
    def test_package_list_from_path_comments(self):
        self.assertEqual(gn.parse_bundled_packages(BUNDLE), [
            ("@iconify/utils", "3.0.2"), ("cytoscape-fcose", "2.2.0"), ("d3-array", "2.12.1"), ("d3-array", "3.2.4"), ("roughjs", "4.6.6")])

    def test_licence_body_ignores_copyright_lines_and_spacing(self):
        a = "MIT License\n\nCopyright (c) 2020 A B\n\nPermission  is granted."
        b = "MIT License\nCopyright (c) 2019 C D\nPermission is   granted."
        self.assertEqual(gn.normalise_body(a), gn.normalise_body(b))
        self.assertNotEqual(gn.normalise_body(a), gn.normalise_body(a + " Plus more."))

    def test_copyright_lines(self):
        self.assertEqual(gn.copyright_lines("x\n  Copyright (c) 2020 A B\nCopyright 2021 C\nnot copyright here"), ["Copyright (c) 2020 A B", "Copyright 2021 C"])

    def test_grouping_puts_identical_texts_together_whatever_identifier_they_declare(self):
        recs = [
            {"name": "a", "version": "1", "licence": "Apache-2.0", "text": "Apache text"},
            {"name": "b", "version": "1", "licence": "(MPL-2.0 OR Apache-2.0)", "text": "Apache  text"},
            {"name": "c", "version": "1", "licence": "MIT", "text": "MIT text"},
            {"name": "d", "version": "1", "licence": "MIT", "text": None},
        ]
        groups = gn.group_licence_texts(recs)
        self.assertEqual(len(groups), 2)
        self.assertEqual(sorted(len(g[2]) for g in groups), [1, 2])

    def test_which_licences_need_attention(self):
        for ok in ("MIT", "ISC", "BSD-3-Clause", "Apache-2.0", "(MIT OR Apache-2.0)", "0BSD", "CC0-1.0"):
            self.assertFalse(gn.needs_attention(ok), ok)
        for bad in ("EPL-2.0", "(MPL-2.0 OR Apache-2.0)", "LGPL-3.0", "GPL-2.0-only", "CC-BY-4.0", "MPL-2.0", None, ""):
            self.assertTrue(gn.needs_attention(bad), bad)

    def test_fence_is_longer_than_any_backtick_run_in_the_text(self):
        self.assertEqual(gn.fence_for("no ticks"), "```")
        self.assertEqual(gn.fence_for("a ``` b"), "````")


class CommittedFile(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(ROOT, "THIRD-PARTY-NOTICES.md"), encoding="utf-8") as fh:
            self.text = fh.read()

    def test_it_records_the_vendored_file_and_names_the_licences_that_need_attention(self):
        with open(os.path.join(ROOT, "tools", "site", "vendor", "README.md"), encoding="utf-8") as fh:
            readme = fh.read()
        sha = re.search(r"^([0-9a-f]{64})  mermaid\.min\.js$", readme, re.M).group(1)
        self.assertIn(sha, self.text)
        self.assertIn("12.2.0", self.text)
        self.assertIn("## What needs attention", self.text)
        self.assertIn("EPL-2.0", self.text)
        self.assertIn("elkjs", self.text)
        self.assertIn("Apache License 2.0", self.text)

    def test_no_new_unflagged_problem_licence(self):
        self.assertNotIn("New since this section was written", self.text)


if __name__ == "__main__":
    unittest.main()

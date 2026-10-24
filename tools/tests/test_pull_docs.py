"""Tests for tools/pull-docs.py (pulls each Kit's own reference documentation into the book).

    python3 -m unittest                              from the repository root
    python3 -m unittest discover -s tools/tests -v   the same, verbose (this is `make test-tools`)

Standard library only: these run for readers too, with or without PyYAML. Every test builds a small fake Kit in a
temporary folder, so nothing here needs .kits/ or a network.
"""
import contextlib
import importlib.util
import io
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)

COMMIT = "0123456789abcdef0123456789abcdef01234567"
OTHER = "fedcba9876543210fedcba9876543210fedcba98"
SHORT = COMMIT[:7]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CONF = """\
[demo-kit]
dest = book/30-kits/demo-kit/reference
index = docs/README.md
nav_title = Demo Kit reference
include =
    docs/*.md
    spec/SPEC.md
    docs/examples/*/README.md
exclude =
    docs/README.md
order =
    docs/GUIDE.md
    spec/SPEC.md | The spec
"""

SUMMARY = """\
# Summary

# Kits

- [Kits](30-kits/README.md)
  <!-- catalog:start -->
  - [Demo Kit](30-kits/demo-kit.md)
  <!-- catalog:end -->

# Reference

- [Make targets](90-reference/make-targets.md)
"""

README = """\
# Demo documentation

[Guide](GUIDE.md) · [Spec](../spec/SPEC.md) · [Home](../README.md)

---

The demo Kit does one small thing well, and these pages say how.

## Pages

See the [guide](GUIDE.md#second-part) and [`examples/cli`](examples/cli/).
"""

GUIDE = """\
# Guide: using the demo

Start with the [index](README.md). Then read this guide, which explains the first thing. It goes on.

## First part

Text.

## Second part

Text with `[not a link](nowhere.md)` inside a code span.
"""

SPEC = """\
# The spec

This is the contract. Both sides must satisfy it.

## 1. Rules

Rule text.
"""

EXAMPLE = """\
# cli

A command-line example. Run it with `dart run`.

See [the code](bin/main.dart) and [the guide](../../GUIDE.md).
"""


class KitCase(unittest.TestCase):
    """A temporary repository with a lock file, a configuration, a SUMMARY and a fetched fake Kit."""

    visibility = "private"

    def setUp(self):
        self.mod = load("pull_docs", "pull-docs.py")
        self.tmp = tempfile.mkdtemp(prefix="pull-docs-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = os.path.join(self.tmp, "repo")
        os.makedirs(os.path.join(self.root, "book", "30-kits"))
        os.makedirs(os.path.join(self.root, "tools"))
        self.write("kits.lock", "demo-kit https://github.com/example-org/demo-kit %s %s core\n" % (COMMIT, self.visibility))
        self.write("tools/docs-pull.conf", CONF)
        self.write("book/SUMMARY.md", SUMMARY)
        self.kit = os.path.join(self.root, ".kits", "demo-kit")
        self.kit_write("docs/README.md", README)
        self.kit_write("docs/GUIDE.md", GUIDE)
        self.kit_write("spec/SPEC.md", SPEC)
        self.kit_write("docs/examples/cli/README.md", EXAMPLE)
        self.kit_write("docs/examples/cli/bin/main.dart", "void main() {}\n")
        self.kit_write("README.md", "# Home\n")
        self.kit_write(".fetched", COMMIT + "\n")

    # -- helpers ---------------------------------------------------------------------------------------------------

    def write(self, rel, text):
        path = os.path.join(self.root, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def kit_write(self, rel, text, binary=False):
        path = os.path.join(self.kit, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb" if binary else "w", **({} if binary else {"encoding": "utf-8", "newline": "\n"})) as fh:
            fh.write(text)

    def read(self, rel):
        with open(os.path.join(self.root, *rel.split("/")), encoding="utf-8") as fh:
            return fh.read()

    def exists(self, rel):
        return os.path.exists(os.path.join(self.root, *rel.split("/")))

    def pull(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = self.mod.main(["--root", self.root] + list(extra))
        return rc, out.getvalue(), err.getvalue()

    def snapshot(self):
        files = {}
        for base, _, names in os.walk(os.path.join(self.root, "book")):
            for n in names:
                path = os.path.join(base, n)
                with open(path, "rb") as fh:
                    files[os.path.relpath(path, self.root)] = fh.read()
        return files

    DEST = "book/30-kits/demo-kit/reference"


class LinkRewriteTests(KitCase):
    """One test per class of link. The page under test is docs/GUIDE.md unless it says otherwise."""

    def rewrite(self, text, page="docs/GUIDE.md", public=None, dest=None):
        entry = self.mod.read_lock(os.path.join(self.root, "kits.lock"))["demo-kit"]
        pulled = {"docs/GUIDE.md": "guide.md", "docs/README.md": "index.md", "spec/SPEC.md": "spec/spec.md",
                  "docs/examples/cli/README.md": "examples/cli.md"}
        rw = self.mod.Rewriter(self.kit, entry, (self.visibility == "public") if public is None else public, pulled)
        return rw.rewrite(page, dest or pulled[page], text), rw

    def test_external_links_and_same_page_anchors_are_left_alone(self):
        text = "[a](https://example.org/x#y) [b](mailto:a@example.org) [c](#first-part) <https://example.org>\n"
        out, rw = self.rewrite(text)
        self.assertEqual(out, text)
        self.assertEqual(rw.warnings, [])

    def test_link_to_a_pulled_page_becomes_a_link_to_the_copy_and_keeps_its_anchor(self):
        out, rw = self.rewrite("[g](GUIDE.md#second-part) and [s](../spec/SPEC.md#1-rules)\n")
        self.assertEqual(out, "[g](guide.md#second-part) and [s](spec/spec.md#1-rules)\n")
        self.assertEqual(rw.stats["to pulled page"], 2)

    def test_links_are_relative_to_where_the_page_lands(self):
        out, _ = self.rewrite("[g](../../GUIDE.md) [s](../../../spec/SPEC.md)\n", page="docs/examples/cli/README.md")
        self.assertEqual(out, "[g](../guide.md) [s](../spec/spec.md)\n")

    def test_docs_readme_becomes_the_index_and_a_folder_with_a_pulled_readme_becomes_that_page(self):
        out, _ = self.rewrite("[i](README.md) [f](examples/cli/) [f2](examples/cli)\n")
        self.assertEqual(out, "[i](index.md) [f](examples/cli.md) [f2](examples/cli.md)\n")

    def test_not_pulled_target_in_a_private_kit_becomes_plain_text(self):
        out, rw = self.rewrite("see [the code](examples/cli/bin/main.dart), [`../README.md`](../README.md) and [`x`](..)\n")
        self.assertEqual(out, "see the code, `../README.md` and `x`\n")
        self.assertEqual(rw.warnings, [])
        self.assertNotIn("github.com", out)

    def test_not_pulled_target_in_a_public_kit_becomes_a_github_url_at_the_pinned_commit(self):
        out, _ = self.rewrite("[code](examples/cli/bin/main.dart#L1) [dir](examples/cli/bin) [home](../README.md)\n", public=True)
        base = "https://github.com/example-org/demo-kit/"
        self.assertIn("[code](%sblob/%s/docs/examples/cli/bin/main.dart#L1)" % (base, COMMIT), out)
        self.assertIn("[dir](%stree/%s/docs/examples/cli/bin)" % (base, COMMIT), out)
        self.assertIn("[home](%sblob/%s/README.md)" % (base, COMMIT), out)

    def test_a_link_that_leaves_the_kit_or_points_at_nothing_is_plain_text_and_warned_about(self):
        out, rw = self.rewrite("[up](../../../elsewhere.md) and [gone](missing.md)\n", public=True)
        self.assertEqual(out, "up and gone\n")
        self.assertEqual(len(rw.warnings), 2)
        self.assertIn("leaves the Kit", rw.warnings[0])
        self.assertIn("does not have", rw.warnings[1])

    def test_a_dead_anchor_keeps_the_page_link_without_the_anchor_and_warns(self):
        out, rw = self.rewrite("[g](GUIDE.md#no-such-heading)\n")
        self.assertEqual(out, "[g](guide.md)\n")
        self.assertIn("dead anchor", rw.warnings[0])

    def test_percent_encoded_paths_and_link_titles_survive(self):
        self.kit_write("docs/GUIDE.md", GUIDE)
        out, _ = self.rewrite('[g](GUIDE.md "the guide") [h](%47UIDE.md#first-part)\n')
        self.assertEqual(out, '[g](guide.md "the guide") [h](guide.md#first-part)\n')

    def test_images_that_exist_are_copied_and_missing_ones_are_dropped_with_a_note(self):
        self.kit_write("docs/img/pic.png", b"\x89PNG fake", binary=True)
        out, rw = self.rewrite("![the picture](img/pic.png) ![gone](img/none.png) ![web](https://example.org/a.png)\n")
        self.assertIn("![the picture](assets/img/pic.png)", out)
        self.assertIn("*(image not included: gone)*", out)
        self.assertIn("![web](https://example.org/a.png)", out)
        self.assertEqual(rw.assets, {"assets/img/pic.png": b"\x89PNG fake"})
        self.assertEqual(rw.stats["image copied"], 1)
        self.assertEqual(rw.stats["image dropped"], 1)

    def test_code_fences_and_code_spans_are_never_touched(self):
        text = "`[a](README.md)`\n\n```md\n[b](README.md)\n```\n\n~~~\n[c](README.md)\n~~~\n\n[d](README.md)\n"
        out, _ = self.rewrite(text)
        self.assertEqual(out, text.replace("[d](README.md)", "[d](index.md)"))

    def test_a_longer_fence_is_not_closed_by_a_shorter_one(self):
        text = "````md\n```\n[a](README.md)\n```\n````\n[b](README.md)\n"
        out, _ = self.rewrite(text)
        self.assertEqual(out, text.replace("[b](README.md)", "[b](index.md)"))

    def test_reference_style_links_follow_the_same_rules(self):
        text = "[a][one] [b][two] [c][one]\n\n[one]: GUIDE.md#first-part\n[two]: ../README.md\n"
        out, _ = self.rewrite(text)
        self.assertEqual(out, "[a][one] b [c][one]\n\n[one]: guide.md#first-part\n")


class PageTests(KitCase):
    def test_every_page_starts_with_the_banner_comment_and_has_the_visible_line_under_its_title(self):
        self.assertEqual(self.pull()[0], 0)
        for rel in ("index.md", "guide.md", "spec/spec.md", "examples/cli.md"):
            lines = self.read(self.DEST + "/" + rel).splitlines()
            self.assertTrue(lines[0].startswith("<!-- Generated by tools/pull-docs.py from demo-kit at %s (" % SHORT), rel)
            self.assertEqual(lines[1], "")
            self.assertTrue(lines[2].startswith("# "), rel)
            self.assertEqual(lines[3], "")
            self.assertEqual(lines[4], "> Reference page pulled from demo-kit at commit %s. Edit it in the Kit, not here." % SHORT)
            self.assertEqual(lines[5], "")

    def test_a_page_without_a_title_gets_the_visible_line_first(self):
        text = self.mod.add_banner("Just text.\n", self.mod.read_lock(os.path.join(self.root, "kits.lock"))["demo-kit"], "x.md")
        lines = text.splitlines()
        self.assertTrue(lines[0].startswith("<!-- Generated by"))
        self.assertIn("Reference page pulled from demo-kit at commit " + SHORT, lines[2])
        self.assertEqual(lines[-1], "Just text.")

    def test_a_title_followed_directly_by_text_gets_a_blank_line_after_the_quote(self):
        text = self.mod.add_banner("# T\nText.\n", self.mod.read_lock(os.path.join(self.root, "kits.lock"))["demo-kit"], "x.md")
        self.assertEqual(text.splitlines()[2:7], ["# T", "", "> Reference page pulled from demo-kit at commit %s. Edit it in the Kit, not here." % SHORT, "", "Text."])

    def test_the_kits_text_is_otherwise_unchanged(self):
        self.pull()
        body = self.read(self.DEST + "/spec/spec.md").split("\n", 6)[6]          # after comment, title, quote
        self.assertEqual(body, SPEC.split("\n", 2)[2].lstrip("\n"))

    def test_heading_anchors_survive_in_every_pulled_page(self):
        self.pull()
        links = load("check_links_probe", "check-links.py")
        for src, dest in (("docs/GUIDE.md", "guide.md"), ("spec/SPEC.md", "spec/spec.md"),
                          ("docs/examples/cli/README.md", "examples/cli.md"), ("docs/README.md", "index.md")):
            before = links.anchors_of(os.path.join(self.kit, *src.split("/")))
            after = links.anchors_of(os.path.join(self.root, *(self.DEST + "/" + dest).split("/")))
            self.assertTrue(before <= after, (src, before - after))
        self.assertIn("second-part", links.anchors_of(os.path.join(self.root, *(self.DEST + "/guide.md").split("/"))))

    def test_names_follow_the_rules(self):
        d = self.mod.dest_name
        self.assertEqual(d("docs/GUIDE.md", "docs/README.md"), "guide.md")
        self.assertEqual(d("docs/README.md", "docs/README.md"), "index.md")
        self.assertEqual(d("spec/SPEC.md", "docs/README.md"), "spec/spec.md")
        self.assertEqual(d("docs/examples/cli/README.md", "docs/README.md"), "examples/cli.md")

    def test_the_index_is_the_kits_readme_plus_a_table_of_every_page(self):
        self.pull()
        index = self.read(self.DEST + "/index.md")
        self.assertIn("# Demo documentation", index)
        self.assertIn("[Guide](guide.md) · [Spec](spec/spec.md) · Home", index)
        table = index.split("## Pages in this book")[1]
        self.assertIn("| [Guide: using the demo](guide.md) | Start with the index.", table)       # description: first sentence
        self.assertIn("| [The spec](spec/spec.md) | This is the contract. |", table)             # label from the configuration
        self.assertIn("| [cli](examples/cli.md) | A command-line example. |", table)
        self.assertLess(table.index("guide.md"), table.index("spec/spec.md"))                    # the configured order

    def test_without_a_kit_readme_the_index_is_still_made(self):
        os.remove(os.path.join(self.kit, "docs", "README.md"))
        self.assertEqual(self.pull()[0], 0)
        index = self.read(self.DEST + "/index.md")
        self.assertIn("# demo-kit", index)
        self.assertIn("(guide.md)", index)

    def test_a_navigation_line_is_not_taken_as_the_description(self):
        self.assertEqual(self.mod.description(README), "The demo Kit does one small thing well, and these pages say how.")

    def test_summary_nests_the_pages_under_the_kit_in_a_part_of_their_own_before_reference(self):
        self.pull()
        s = self.read("book/SUMMARY.md")
        self.assertIn("  <!-- catalog:end -->\n\n# Kit reference\n\n<!-- docs-pull:start -->\n- [Demo Kit reference](30-kits/demo-kit/reference/index.md)\n"
                      "  - [Guide: using the demo](30-kits/demo-kit/reference/guide.md)\n"
                      "  - [The spec](30-kits/demo-kit/reference/spec/spec.md)\n"
                      "  - [cli](30-kits/demo-kit/reference/examples/cli.md)\n<!-- docs-pull:end -->\n\n# Reference\n", s)
        self.assertIn("  - [Demo Kit](30-kits/demo-kit.md)", s)            # the catalog block is untouched
        self.assertTrue(s.endswith("- [Make targets](90-reference/make-targets.md)\n"))

    def test_a_second_pull_replaces_only_the_block_and_leaves_the_rest_of_summary_alone(self):
        self.pull()
        first = self.read("book/SUMMARY.md")
        self.write("book/SUMMARY.md", first.replace("# Reference", "# Reference\n\n- [Hand written](x.md)"))
        self.kit_write("docs/GUIDE.md", GUIDE.replace("# Guide: using the demo", "# Guide renamed"))
        self.pull()
        s = self.read("book/SUMMARY.md")
        self.assertIn("- [Hand written](x.md)", s)
        self.assertIn("[Guide renamed]", s)
        self.assertEqual(s.count(self.mod.SUMMARY_START), 1)

    def test_summary_without_a_reference_part_gets_the_new_part_at_the_end(self):
        self.write("book/SUMMARY.md", "# Summary\n\n- [Intro](a.md)\n")
        self.pull()
        s = self.read("book/SUMMARY.md")
        self.assertTrue(s.startswith("# Summary\n\n- [Intro](a.md)\n\n# Kit reference\n\n<!-- docs-pull:start -->\n- [Demo Kit reference]"))
        self.assertTrue(s.endswith("<!-- docs-pull:end -->\n"))

    def test_a_marker_without_its_partner_is_refused(self):
        self.write("book/SUMMARY.md", SUMMARY.replace("  <!-- catalog:end -->", "  <!-- catalog:end -->\n<!-- docs-pull:start -->"))
        rc, _, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("marker", err)
        self.assertFalse(self.exists(self.DEST + "/guide.md"))


class RunTests(KitCase):
    def test_second_run_is_byte_identical(self):
        self.assertEqual(self.pull()[0], 0)
        first = self.snapshot()
        self.assertEqual(self.pull()[0], 0)
        self.assertEqual(self.snapshot(), first)

    def test_a_page_the_kit_no_longer_has_is_removed_but_a_hand_written_page_stays(self):
        self.pull()
        self.write(self.DEST + "/notes.md", "# Mine\n")
        os.remove(os.path.join(self.kit, "docs", "examples", "cli", "README.md"))
        self.kit_write("docs/README.md", "# Demo documentation\n\nText.\n")
        rc, out, _ = self.pull()
        self.assertEqual(rc, 0)
        self.assertFalse(self.exists(self.DEST + "/examples/cli.md"))
        self.assertFalse(self.exists(self.DEST + "/examples"))                      # and the empty folder with it
        self.assertTrue(self.exists(self.DEST + "/guide.md"))
        self.assertIn("removed 1 stale", out)
        self.assertTrue(self.exists(self.DEST + "/notes.md"))

    def test_a_section_needs_a_lock_entry_and_a_fetched_kit(self):
        self.write("kits.lock", "unrelated-kit https://github.com/example-org/unrelated %s public core\n" % COMMIT)
        rc, out, _ = self.pull()                     # demo-kit has a section but is not in kits.lock
        self.assertEqual(rc, 2)
        self.write("tools/docs-pull.conf", CONF.replace("[demo-kit]", "[unrelated-kit]"))
        rc, out, err = self.pull()                   # now the section and the lock agree, but that Kit is not fetched
        self.assertEqual(rc, 2)
        self.assertIn("not fetched", err)
        self.write("tools/docs-pull.conf", "[x]\ndest = book/x\ninclude =\n    a.md\n")
        rc, out, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("[x]", err)

    def test_a_kit_in_the_lock_without_a_section_is_left_alone(self):
        self.write("kits.lock", self.read("kits.lock") + "other-kit https://github.com/example-org/other %s public core\n" % COMMIT)
        rc, out, _ = self.pull()
        self.assertEqual(rc, 0)
        self.assertNotIn("other-kit", out)
        self.assertFalse(self.exists("book/30-kits/other-kit"))

    def test_an_order_line_that_selects_nothing_is_refused(self):
        self.write("tools/docs-pull.conf", CONF + "    docs/GONE.md\n")
        rc, _, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("docs/GONE.md", err)

    def test_the_configuration_is_validated(self):
        self.write("tools/docs-pull.conf", CONF.replace("dest = book/30-kits/demo-kit/reference", "dest = elsewhere"))
        self.assertEqual(self.pull()[0], 2)
        self.write("tools/docs-pull.conf", CONF + "colour = blue\n")
        rc, _, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("unknown key", err)

    def test_visibility_comes_from_kits_lock_unless_the_configuration_says_otherwise(self):
        self.kit_write("docs/GUIDE.md", GUIDE + "\n[code](../README.md)\n")
        self.pull()
        self.assertNotIn("github.com", self.read(self.DEST + "/guide.md"))
        self.write("kits.lock", "demo-kit https://github.com/example-org/demo-kit %s public core\n" % COMMIT)
        self.pull()
        self.assertIn("https://github.com/example-org/demo-kit/blob/%s/README.md" % COMMIT, self.read(self.DEST + "/guide.md"))
        self.write("tools/docs-pull.conf", CONF.replace("index = ", "public = no\nindex = "))
        self.pull()
        self.assertNotIn("github.com", self.read(self.DEST + "/guide.md"))


class PinTests(KitCase):
    def test_a_fetched_kit_at_a_different_commit_is_refused_and_nothing_is_written(self):
        self.kit_write(".fetched", OTHER + "\n")
        before = self.snapshot()
        rc, out, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn(OTHER[:7], err)
        self.assertIn(SHORT, err)
        self.assertIn("make fetch KITS=all", err)                    # private Kit: the fix says KITS=all
        self.assertIn("never mixes", err)
        self.assertEqual(self.snapshot(), before)

    def test_a_public_kit_needs_no_kits_all_in_the_fix(self):
        self.write("kits.lock", "demo-kit https://github.com/example-org/demo-kit %s public core\n" % COMMIT)
        self.kit_write(".fetched", OTHER + "\n")
        self.assertNotIn("KITS=all", self.pull()[2])

    def test_a_kit_with_no_fetched_marker_or_no_folder_is_refused(self):
        os.remove(os.path.join(self.kit, ".fetched"))
        rc, _, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("no .fetched", err)
        shutil.rmtree(self.kit)
        rc, _, err = self.pull()
        self.assertEqual(rc, 2)
        self.assertIn("not fetched", err)
        self.assertFalse(self.exists(self.DEST + "/index.md"))

    def test_the_check_refuses_a_mismatched_pin_too(self):
        self.pull()
        self.kit_write(".fetched", OTHER + "\n")
        rc, _, err = self.pull("--check")
        self.assertEqual(rc, 2)
        self.assertIn("kits.lock pins", err)


class CheckTests(KitCase):
    def test_check_passes_right_after_a_pull(self):
        self.pull()
        rc, out, _ = self.pull("--check")
        self.assertEqual(rc, 0)
        self.assertIn("match a fresh pull", out)

    def test_check_writes_nothing(self):
        before = self.snapshot()
        self.pull("--check")
        self.assertEqual(self.snapshot(), before)

    def test_check_names_the_page_that_was_edited_by_hand(self):
        self.pull()
        path = os.path.join(self.root, *(self.DEST + "/guide.md").split("/"))
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("A hand edit.\n")
        rc, out, _ = self.pull("--check")
        self.assertEqual(rc, 1)
        self.assertIn("%s/guide.md: differs" % self.DEST, out)
        self.assertIn("-A hand edit.", out)
        self.assertIn("make docs-pull", out)
        self.assertNotIn("index.md: differs", out)

    def test_check_reports_a_missing_page_a_stale_page_and_a_changed_summary(self):
        self.pull()
        os.remove(os.path.join(self.root, *(self.DEST + "/spec/spec.md").split("/")))
        self.write("book/SUMMARY.md", self.read("book/SUMMARY.md").replace("[The spec]", "[Spec]"))
        os.remove(os.path.join(self.kit, "docs", "examples", "cli", "README.md"))
        self.kit_write("docs/README.md", README.replace("[`examples/cli`](examples/cli/)", "nothing"))
        rc, out, _ = self.pull("--check")
        self.assertEqual(rc, 1)
        self.assertIn("spec/spec.md: missing", out)
        self.assertIn("examples/cli.md: stale", out)
        self.assertIn("book/SUMMARY.md: differs", out)

    def test_check_notices_that_the_kit_moved_on(self):
        self.pull()
        self.kit_write("docs/GUIDE.md", GUIDE.replace("Text.", "Changed text."))
        rc, out, _ = self.pull("--check")
        self.assertEqual(rc, 1)
        self.assertIn("guide.md: differs", out)

    def test_check_skips_with_a_message_when_the_kit_is_not_fetched(self):
        self.pull()
        shutil.rmtree(self.kit)
        rc, out, err = self.pull("--check")
        self.assertEqual((rc, err), (0, ""))
        self.assertIn("skipped demo-kit", out)
        self.assertIn("make setup KITS=all", out)

    def test_check_does_not_judge_the_summary_when_a_kit_was_skipped(self):
        self.write("kits.lock", "demo-kit https://github.com/example-org/demo-kit %s private core\n"
                   "late-kit https://github.com/example-org/late-kit %s public core\n" % (COMMIT, COMMIT))
        self.write("tools/docs-pull.conf", CONF + "\n[late-kit]\ndest = book/30-kits/late-kit/reference\ninclude =\n    docs/*.md\n")
        rc, out, _ = self.pull("--check")                              # nothing pulled yet, and late-kit is not fetched
        self.assertIn("skipped late-kit", out)
        self.assertEqual(rc, 1)                                        # demo-kit is fetched and its pages are missing
        self.assertNotIn("SUMMARY.md", out)


if __name__ == "__main__":
    unittest.main()

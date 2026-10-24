"""Tests for tools/gen-catalog.py (the maintainer tool that generates book/30-kits/ from the Kit registry).

    python3 -m unittest                              from the repository root
    python3 -m unittest discover -s tools/tests -v   the same, verbose (this is `make test-tools`)

PyYAML is required to run them (the generator needs it); without it every test is skipped with a message.
This file feeds the sanitiser sample leaks on purpose, so tools/check-public.sh does not scan it.
"""
import contextlib
import importlib.util
import io
import os
import shutil
import tempfile
import unittest

try:
    import yaml  # noqa: F401
    HAVE_YAML = True
except ImportError:
    HAVE_YAML = False

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR = os.path.join(os.path.dirname(HERE), "gen-catalog.py")


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_catalog", GENERATOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


NEEDS_YAML = unittest.skipUnless(HAVE_YAML, "PyYAML is not installed (python3 -m pip install pyyaml); skipping")

HEADER = """\
# Test Kit Registry
# STATUS VOCABULARY (evidence is the test, not intent):
#   design      a document; no code to speak of
#   scaffold    a skeleton of code that nothing depends on
#   alpha       real code and tests, no stable API
#   pre-release published, depended on by products, API settling
#   stable      API frozen with a versioning promise
#   legacy      archived or retired
#   banked      deliberately paused with its program (off-focus)
# Format version: 1.0

"""

DIRTY_DESCRIPTION = (
    "Alpha Kit owns the widgets. It was ruled by DJ on 2026-10-19 under CLUS-22.\n"
    "See jenkins.softsurve.com for the build and ~/src/github.com/dlockamy/vault/wiki/notes.md for why. "
    "Lockamy Studios ships it (data-architect agreed, see QR-66). "
    "It also keeps widgets sorted."
)

REGISTRY = HEADER + """\
kits:
  - display_name: "Alpha Kit"
    org: "slash-builder"
    language: "Rust"
    repo: "https://github.com/slash-builder/alpha-kit"
    status: "alpha"
    tagline: |
      Keeps widgets
      in order.
    description: |
      STUB ENTRY -- backfill pending. @@DIRTY@@

      Second paragraph, still public.

      Third paragraph is not shown.
    tier: "hybrid"
    scope_out:
      - "Painting widgets (the renderer owns that; see CLUS-9)"
      - "Cooking, per the ruling by DJ"
    related_kits:
      - "beta-kit (reads widgets)"
      - "digital-zen"
      - "alpha-kit"
  - display_name: "Beta Kit"
    org: "slash-builder"
    language: "Dart"
    repo: "https://github.com/slash-builder/beta-kit"
    status: "design"
    tagline: "A plan for beta."
    description: "Beta Kit is only a document so far."
    tier: "cross-platform"
  - display_name: "Gamma Kit"
    org: "slash-builder"
    language: "Rust"
    repo: "https://github.com/slash-builder/gamma-kit"
    status: "pre-release"
    tagline: "Gamma things."
    description: "Gamma Kit does gamma things."
    tier: "substrate"
    related_kits: ["alpha-kit", "beta-kit"]
  - display_name: "Delta Kit"
    org: "slash-builder"
    language: "Rust"
    repo: "https://github.com/slash-builder/delta-kit"
    status: "alpha"
    tagline: "Delta things."
    description: "Delta Kit does delta things."
    tier: "infrastructure"
  - display_name: "Banked Kit"
    org: "slash-builder"
    language: "Rust"
    repo: "https://github.com/slash-builder/banked-kit"
    status: "banked"
    tagline: "Paused."
    description: "Banked Kit is on hold."
    tier: "core"
pending_kits:
  - display_name: "Pending Kit"
    org: "slash-builder"
    language: "Rust"
    repo: "https://github.com/slash-builder/pending-kit"
    status: "alpha"
    tagline: "Not created yet."
    description: "Pending Kit has no repository."
    tier: "core"
"""

REGISTRY = REGISTRY.replace("@@DIRTY@@", DIRTY_DESCRIPTION.replace("\n", "\n      "))

SUMMARY = """\
# Summary

[Introduction](00-introduction.md)

# Kits

- [Kits](30-kits/README.md)

# Reference

- [Make targets](90-reference/make-targets.md)
"""

# repository -> (visibility, docs)
VISIBILITY = {
    "slash-builder/alpha-kit": ("public", "yes"),
    "slash-builder/beta-kit": ("private", "-"),
    "slash-builder/gamma-kit": ("public", "no"),
    "slash-builder/delta-kit": ("private", "-"),
    "slash-builder/banked-kit": ("private", "-"),
    "slash-builder/pending-kit": ("missing", "-"),
    "slash-builder/application-kit": ("private", "-"),
}


def quiet(fn, *args, **kwargs):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        result = fn(*args, **kwargs)
    return result, out.getvalue(), err.getvalue()


@NEEDS_YAML
class GeneratorTestCase(unittest.TestCase):
    def setUp(self):
        self.gen = load_generator()
        self.tmp = tempfile.mkdtemp(prefix="gen-catalog-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = os.path.join(self.tmp, "repo")
        os.makedirs(os.path.join(self.root, "book", "30-kits"))
        os.makedirs(os.path.join(self.root, "tools"))
        self.registry = os.path.join(self.tmp, "kits.yaml")
        self.write(self.registry, REGISTRY)
        self.write(os.path.join(self.root, "book", "SUMMARY.md"), SUMMARY)
        self.write_tsv(VISIBILITY)

    def write(self, path, text):
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)

    def read(self, *parts):
        with open(os.path.join(self.root, *parts), encoding="utf-8") as fh:
            return fh.read()

    def write_tsv(self, visibility):
        names = {"slash-builder/application-kit": "Application Kit"}
        rows = [{"name": names.get(repo) or repo.split("/")[1].replace("-", " ").title(), "visibility": v,
                 "date": "2026-01-01", "docs": "unknown" if d == "-" else d}
                for repo, (v, d) in visibility.items()]
        self.gen.write_visibility(os.path.join(self.root, "tools", "kit-visibility.tsv"), rows)

    def run_gen(self, *extra):
        args = ["--registry", self.registry, "--root", self.root, "--offline"] + list(extra)
        return quiet(self.gen.main, args)

    def snapshot(self):
        files = {}
        for base, _, names in os.walk(self.root):
            for n in names:
                path = os.path.join(base, n)
                with open(path, "rb") as fh:
                    files[os.path.relpath(path, self.root)] = fh.read()
        return files


class SanitiseTests(GeneratorTestCase):
    def test_every_kind_of_internal_context_comes_out_clean(self):
        clean = self.gen.sanitise_text(DIRTY_DESCRIPTION)
        self.assertEqual(self.gen.find_leaks(clean), [], clean)
        for needle in ("CLUS-22", "QR-66", "jenkins", "softsurve", "dlockamy", "vault", "DJ", "Lockamy", "data-architect"):
            self.assertNotIn(needle, clean)
        self.assertIn("It also keeps widgets sorted.", clean)

    def test_owner_name_is_slashbuilder(self):
        self.assertEqual(self.gen.sanitise_text("Lockamy Studios builds it."), "SlashBuilder builds it.")
        self.assertEqual(self.gen.sanitise_text("Used across the studio's services."), "Used across SlashBuilder's services.")

    def test_parenthetical_with_a_ticket_is_removed_but_a_plain_one_stays(self):
        out = self.gen.sanitise_text("It stores bytes (see CLUS-22) and hashes them (BLAKE3).")
        self.assertEqual(out, "It stores bytes and hashes them (BLAKE3).")

    def test_dated_claims_and_stub_markers_are_dropped(self):
        out = self.gen.sanitise_text("STUB ENTRY -- backfill pending. It does X. Maturity as of 2026-08-25: stub.")
        self.assertEqual(out, "It does X.")

    def test_first_sentence_dropped_means_the_paragraph_is_dropped(self):
        text = "Settled by DJ on 2026-01-01 in CLUS-1. It is a plain subject with no tier."
        self.assertEqual(self.gen.sanitise_text(text, lead_required=True), "")
        self.assertEqual(self.gen.sanitise_text(text), "It is a plain subject with no tier.")

    def test_a_later_paragraph_is_not_shown_without_the_one_before_it(self):
        text = "Opens with DJ's ruling in CLUS-5.\n\nContinues the thought."
        self.assertEqual(self.gen.paragraphs(text, 2), [])

    def test_renamed_kit_gets_its_current_name(self):
        self.assertEqual(self.gen.sanitise_text("Used by AI Kit."), "Used by Inference Kit.")

    def test_a_leak_in_a_rendered_page_fails_loudly(self):
        with self.assertRaises(self.gen.LeakError):
            self.gen.assert_page_clean("x.md", "# X\n\nSee jenkins.softsurve.com\n")
        with self.assertRaises(self.gen.LeakError):
            self.gen.assert_page_clean("x.md", "# X\n\nOwned by CLUS-31 work\n")
        self.gen.assert_page_clean("x.md", "# X\n\n[slash-builder/alpha-kit](https://github.com/slash-builder/alpha-kit)\n")

    def test_generated_pages_contain_no_leak(self):
        self.run_gen()
        for name in os.listdir(os.path.join(self.root, "book", "30-kits")):
            text = self.read("book", "30-kits", name)
            self.gen.assert_page_clean(name, text)
        card = self.read("book", "30-kits", "alpha-kit.md")
        self.assertIn("SlashBuilder ships it", card)
        self.assertIn("Keeps widgets in order.", card)
        self.assertNotIn("CLUS", card)


class CardTests(GeneratorTestCase):
    def test_public_repo_is_linked_and_private_is_not(self):
        self.run_gen()
        public = self.read("book", "30-kits", "alpha-kit.md")
        private = self.read("book", "30-kits", "beta-kit.md")
        self.assertIn("[slash-builder/alpha-kit](https://github.com/slash-builder/alpha-kit)", public)
        self.assertIn("* **Source:** not public yet", private)
        self.assertNotIn("github.com", private)
        self.assertNotIn("beta-kit", private.replace("beta-kit.md", ""))     # no repository name either
        index = self.read("book", "30-kits", "README.md")
        self.assertEqual(index.count("https://github.com/"), 2)             # alpha and gamma only

    def test_missing_repository_gets_the_note_and_no_link(self):
        self.run_gen()
        card = self.read("book", "30-kits", "pending-kit.md")
        self.assertIn("* **Source:** Repository not created yet", card)
        self.assertNotIn("github.com", card)
        self.assertIn("Yes (not published)", card)

    def test_unknown_visibility_is_treated_as_private(self):
        vis = dict(VISIBILITY)
        del vis["slash-builder/alpha-kit"]
        self.write_tsv(vis)
        _, _, err = self.run_gen()
        self.assertIn("not in kit-visibility.tsv", err)
        self.assertIn("not public yet", self.read("book", "30-kits", "alpha-kit.md"))
        self.assertNotIn("github.com", self.read("book", "30-kits", "alpha-kit.md"))

    def test_reference_docs_sentence_depends_on_public_docs(self):
        self.run_gen()
        self.assertIn("`make docs-pull`", self.read("book", "30-kits", "alpha-kit.md"))        # public, has docs
        self.assertIn("No reference docs yet.", self.read("book", "30-kits", "gamma-kit.md"))  # public, no docs
        self.assertIn("No reference docs yet.", self.read("book", "30-kits", "beta-kit.md"))   # private

    def test_will_not_do_comes_only_from_the_registry_and_is_cleaned(self):
        self.run_gen()
        card = self.read("book", "30-kits", "alpha-kit.md")
        self.assertIn("## What it will not do", card)
        self.assertIn("* Painting widgets\n", card)                             # the parenthetical named a ticket
        self.assertNotIn("Cooking", card)                                       # the whole item named DJ: dropped
        self.assertNotIn("## What it will not do", self.read("book", "30-kits", "delta-kit.md"))

    def test_related_kits_are_names_linked_to_cards_and_non_kits_are_skipped(self):
        self.run_gen()
        card = self.read("book", "30-kits", "alpha-kit.md")
        self.assertIn("## Related Kits\n\n[Beta Kit](beta-kit.md)\n", card)
        self.assertNotIn("digital-zen", card)
        self.assertNotIn("reads widgets", card)

    def test_paragraphs_are_trimmed_to_two(self):
        self.run_gen()
        card = self.read("book", "30-kits", "alpha-kit.md")
        self.assertIn("Second paragraph, still public.", card)
        self.assertNotIn("Third paragraph", card)


class IndexTests(GeneratorTestCase):
    def test_status_groups_run_most_mature_first_and_keep_registry_order_inside(self):
        self.run_gen()
        index = self.read("book", "30-kits", "README.md")
        headings = [l[3:] for l in index.splitlines() if l.startswith("## ") and l[3:] in self.gen.STATUS_ORDER]
        self.assertEqual(headings, ["pre-release", "alpha", "design", "banked"])
        alpha_rows = [l for l in index.split("## alpha")[1].split("## design")[0].splitlines() if l.startswith("| [")]
        self.assertEqual([r.split("]")[0] for r in alpha_rows], ["| [Alpha Kit", "| [Delta Kit", "| [Pending Kit"])

    def test_real_code_marker_follows_the_status(self):
        self.run_gen()
        rows = dict((l.split("]")[0][3:], l) for l in self.read("book", "30-kits", "README.md").splitlines() if l.startswith("| ["))
        self.assertIn("| Yes |", rows["Alpha Kit"])
        self.assertIn("| Yes |", rows["Gamma Kit"])
        self.assertIn("| No |", rows["Beta Kit"])
        self.assertIn("| No |", rows["Banked Kit"])

    def test_registry_commit_is_printed_only_when_given(self):
        self.run_gen()
        self.assertNotIn("Generated from registry commit", self.read("book", "30-kits", "README.md"))
        self.run_gen("--registry-commit", "ABCDEF1234567")
        self.assertIn("Generated from registry commit abcdef1.", self.read("book", "30-kits", "README.md"))

    def test_a_bad_registry_commit_is_refused(self):
        with self.assertRaises(SystemExit):
            self.run_gen("--registry-commit", "not-a-sha")

    def test_every_kit_has_a_card_and_the_counts_add_up(self):
        _, out, _ = self.run_gen()
        self.assertIn("6 Kit cards", out)
        for slug in ("alpha-kit", "beta-kit", "gamma-kit", "delta-kit", "banked-kit", "pending-kit"):
            self.assertTrue(os.path.isfile(os.path.join(self.root, "book", "30-kits", slug + ".md")), slug)
        self.assertIn("6 Kits: 1 pre-release, 3 alpha, 1 design, 1 banked.", self.read("book", "30-kits", "README.md"))

    def test_status_that_is_not_in_the_vocabulary_is_refused(self):
        self.write(self.registry, REGISTRY.replace('status: "banked"', 'status: "shiny"'))
        with self.assertRaises(SystemExit):
            self.run_gen()

    def test_vocabulary_page_defines_every_status(self):
        self.run_gen()
        page = self.read("book", "30-kits", "status-vocabulary.md")
        for status in self.gen.STATUS_ORDER:
            self.assertIn("## " + status + "\n", page)

    def test_not_in_the_registry_page_says_kit_book_is_not_a_kit(self):
        self.run_gen()
        page = self.read("book", "30-kits", "not-in-the-registry.md")
        self.assertIn("Application Kit", page)
        self.assertIn("not a Kit", page)
        self.assertNotIn("github.com", page)                                  # the repository is private


class RewriteTests(GeneratorTestCase):
    def test_second_run_is_byte_identical(self):
        self.run_gen("--registry-commit", "abcdef1")
        first = self.snapshot()
        self.run_gen("--registry-commit", "abcdef1")
        self.assertEqual(first, self.snapshot())

    def test_summary_block_is_added_after_the_kits_entry_and_the_rest_is_kept(self):
        self.run_gen()
        summary = self.read("book", "SUMMARY.md")
        self.assertIn(self.gen.SUMMARY_START, summary)
        self.assertIn(self.gen.SUMMARY_END, summary)
        self.assertTrue(summary.startswith("# Summary\n\n[Introduction](00-introduction.md)\n\n# Kits\n\n- [Kits](30-kits/README.md)\n  <!-- catalog:start -->"))
        self.assertTrue(summary.endswith("# Reference\n\n- [Make targets](90-reference/make-targets.md)\n"))
        self.assertIn("  - [Alpha Kit](30-kits/alpha-kit.md)", summary)

    def test_only_the_marked_block_is_rewritten(self):
        self.run_gen()
        summary = self.read("book", "SUMMARY.md")
        stale = summary.replace("  - [Alpha Kit](30-kits/alpha-kit.md)", "  - [Gone Kit](30-kits/gone.md)")
        stale = stale.replace("# Reference", "# Reference\n\n(hand-written, keep me)")
        self.write(os.path.join(self.root, "book", "SUMMARY.md"), stale)
        self.run_gen()
        fixed = self.read("book", "SUMMARY.md")
        self.assertNotIn("Gone Kit", fixed)
        self.assertIn("  - [Alpha Kit](30-kits/alpha-kit.md)", fixed)
        self.assertIn("(hand-written, keep me)", fixed)
        self.assertEqual(fixed.count(self.gen.SUMMARY_START), 1)

    def test_one_marker_without_the_other_is_refused(self):
        self.write(os.path.join(self.root, "book", "SUMMARY.md"), SUMMARY + "\n<!-- catalog:start -->\n")
        with self.assertRaises(SystemExit):
            self.run_gen()

    def test_summary_without_a_kits_entry_is_refused(self):
        self.write(os.path.join(self.root, "book", "SUMMARY.md"), "# Summary\n\n[Introduction](00-introduction.md)\n")
        with self.assertRaises(SystemExit):
            self.run_gen()

    def test_a_card_for_a_kit_that_left_the_registry_is_removed_but_hand_written_pages_stay(self):
        self.run_gen()
        self.write(os.path.join(self.root, "book", "30-kits", "handwritten.md"), "# Mine\n")
        self.write(self.registry, REGISTRY.replace('display_name: "Banked Kit"', 'display_name: "Renamed Kit"'))
        self.write_tsv(dict(VISIBILITY, **{"slash-builder/banked-kit": ("private", "-")}))
        self.run_gen()
        self.assertFalse(os.path.exists(os.path.join(self.root, "book", "30-kits", "banked-kit.md")))
        self.assertTrue(os.path.exists(os.path.join(self.root, "book", "30-kits", "renamed-kit.md")))
        self.assertTrue(os.path.exists(os.path.join(self.root, "book", "30-kits", "handwritten.md")))


class VisibilityTests(GeneratorTestCase):
    def fake(self, answers):
        calls = []

        def runner(gh, args):
            calls.append(args)
            key = args[1]
            if key in answers:
                return answers[key]
            return 1, "", "gh: Not Found (HTTP 404)"
        return runner, calls

    def test_gh_answers_map_to_public_private_missing_unknown(self):
        runner, _ = self.fake({
            "repos/o/pub": (0, "false\n", ""),
            "repos/o/pub/contents": (0, "README.md\nsrc\n", ""),
            "repos/o/priv": (0, "true\n", ""),
            "repos/o/odd": (1, "", "gh: HTTP 502 Bad Gateway"),
        })
        self.assertEqual(self.gen.query_visibility("o/pub", runner=runner), ("public", "yes"))
        self.assertEqual(self.gen.query_visibility("o/priv", runner=runner), ("private", "unknown"))
        self.assertEqual(self.gen.query_visibility("o/gone", runner=runner), ("missing", "unknown"))
        self.assertEqual(self.gen.query_visibility("o/odd", runner=runner), ("unknown", "unknown"))

    def test_public_repo_without_readme_or_docs_has_no_docs(self):
        runner, _ = self.fake({"repos/o/pub": (0, "false", ""), "repos/o/pub/contents": (0, "src\nLICENSE\n", "")})
        self.assertEqual(self.gen.query_visibility("o/pub", runner=runner), ("public", "no"))

    def test_online_run_records_the_answers_and_keeps_the_date_when_nothing_changed(self):
        kits = self.gen.load_kits(self.registry)
        tsv = os.path.join(self.root, "tools", "kit-visibility.tsv")
        answers = {}
        for repo, (v, _) in VISIBILITY.items():
            answers["repos/" + repo] = (0, "false" if v == "public" else "true", "") if v != "missing" else (1, "", "HTTP 404")
        for repo in ("slash-builder/alpha-kit", "slash-builder/gamma-kit"):
            answers["repos/%s/contents" % repo] = (0, "README.md" if "alpha" in repo else "src", "")
        runner, _ = self.fake(answers)
        vis, rows, _ = self.gen.resolve_visibility(kits, tsv, False, "gh", "2026-12-31", runner=runner)
        self.assertEqual(vis["slash-builder/alpha-kit"], ("public", "yes"))
        self.assertEqual(vis["slash-builder/pending-kit"], ("missing", "unknown"))
        self.assertEqual(set(r["date"] for r in rows), {"2026-01-01"})        # unchanged answers keep their date
        answers["repos/slash-builder/delta-kit"] = (0, "false", "")
        answers["repos/slash-builder/delta-kit/contents"] = (0, "README.md", "")
        _, rows, _ = self.gen.resolve_visibility(kits, tsv, False, "gh", "2026-12-31", runner=self.fake(answers)[0])
        changed = [r for r in rows if r["date"] == "2026-12-31"]
        self.assertEqual([r["name"] for r in changed], ["Delta Kit"])

    def test_offline_never_calls_gh_and_never_rewrites_the_file(self):
        before = self.read("tools", "kit-visibility.tsv")
        self.run_gen()
        self.assertEqual(before, self.read("tools", "kit-visibility.tsv"))

    def test_the_visibility_file_never_records_where_a_kit_lives(self):
        """The file will be public. It holds Kit names, never a repository slug or an org name."""
        kits = self.gen.load_kits(self.registry)
        answers = {}
        for repo, (v, _) in VISIBILITY.items():
            answers["repos/" + repo] = (0, "false" if v == "public" else "true", "") if v != "missing" else (1, "", "HTTP 404")
        answers["repos/slash-builder/alpha-kit/contents"] = (0, "README.md", "")
        answers["repos/slash-builder/gamma-kit/contents"] = (0, "src", "")
        tsv = os.path.join(self.root, "tools", "kit-visibility.tsv")
        _, rows, _ = self.gen.resolve_visibility(kits, tsv, False, "gh", "2026-12-31", runner=self.fake(answers)[0])
        self.gen.write_visibility(tsv, rows)
        text = self.read("tools", "kit-visibility.tsv")
        for repo in list(VISIBILITY) + ["lockamy-studios", "slash-builder", "github.com", "http"]:
            for part in repo.split("/"):
                if part.endswith("-kit") or "-" in part and part != "slash-builder":
                    self.assertNotIn(part, text, "the file names " + part)
        self.assertNotIn("/", text.split("name\tvisibility", 1)[1])
        self.assertNotIn("slash-builder", text)
        self.assertNotIn("lockamy-studios", text)
        self.assertEqual(text.splitlines()[-len(rows) - 1], "name\tvisibility\tdocs\tchecked")
        # and a registry that uses the old org name does not put it in the file either
        self.write(self.registry, REGISTRY.replace("slash-builder/gamma-kit", "lockamy-studios/gamma-kit"))
        kits = self.gen.load_kits(self.registry)
        answers["repos/lockamy-studios/gamma-kit"] = (0, "true", "")
        _, rows, _ = self.gen.resolve_visibility(kits, tsv, False, "gh", "2026-12-31", runner=self.fake(answers)[0])
        self.gen.write_visibility(tsv, rows)
        self.assertNotIn("lockamy-studios", self.read("tools", "kit-visibility.tsv"))

    def test_registry_option_is_required(self):
        saved = os.environ.pop("KITS_REGISTRY", None)
        try:
            with self.assertRaises(SystemExit) as cm:
                quiet(self.gen.main, ["--root", self.root, "--offline"])
            self.assertIn("KITS_REGISTRY", str(cm.exception))
        finally:
            if saved is not None:
                os.environ["KITS_REGISTRY"] = saved


class WithoutYamlTests(unittest.TestCase):
    def test_missing_pyyaml_gives_an_install_hint(self):
        gen = load_generator()
        saved = gen.yaml
        gen.yaml = None
        try:
            with self.assertRaises(SystemExit) as cm:
                gen.require_yaml()
            self.assertIn("python3 -m pip install pyyaml", str(cm.exception))
        finally:
            gen.yaml = saved


if __name__ == "__main__":
    unittest.main()

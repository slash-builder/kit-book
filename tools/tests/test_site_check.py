"""Tests for tools/site-check.py (checks the built website). Standard library only; each test builds a tiny fake site."""
import hashlib
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
NOINDEX = '<meta name="robots" content="noindex">'


def load():
    spec = importlib.util.spec_from_file_location("site_check", os.path.join(TOOLS, "site-check.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sc = load()
JS = b"/* pretend mermaid */"
SHA = hashlib.sha256(JS).hexdigest()


class Site(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        r = os.path.realpath(self._tmp.name)
        self.site, self.publish, self.vendor = (os.path.join(r, n) for n in ("site", "publish", "vendor"))
        for d in (self.site, self.vendor):
            os.makedirs(d)
        self.page("index.html", '<a href="a/b.html#sec">b</a> <a href="https://x.example/">x</a> <script src="m.js"></script>')
        self.page("a/b.html", '<h2 id="sec">S</h2><a href="../index.html">home</a> <a href="#sec">self</a> <a href="/index.html">abs</a>')
        with open(os.path.join(self.site, "m.js"), "w") as fh:
            fh.write("x")
        self.write(os.path.join(self.vendor, "mermaid.min.js"), JS, "wb")
        self.write(os.path.join(self.vendor, "LICENSE-mermaid"), "MIT")
        self.write(os.path.join(self.vendor, "README.md"), "```text\n%s  mermaid.min.js\n```\n" % SHA)

    def write(self, path, content, mode="w"):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, mode) as fh:
            fh.write(content)

    def page(self, rel, body, head="", root=None):
        self.write(os.path.join(root or self.site, rel), "<html><head>%s</head><body>%s</body></html>" % (head, body))


class LinkTests(Site):
    def test_good_site_passes_and_counts(self):
        stats, problems = sc.check_links(self.site)
        self.assertEqual(problems, [])
        self.assertEqual(stats["pages"], 2)
        self.assertEqual(stats["external"], 1)
        self.assertEqual(stats["internal"], 5)
        self.assertEqual(stats["fragments"], 2)

    def test_missing_file_is_reported(self):
        self.page("c.html", '<a href="nope.html">n</a> <img src="img/x.png">')
        _, problems = sc.check_links(self.site)
        self.assertEqual(len(problems), 2)
        self.assertTrue(all("does not resolve" in p for p in problems))

    def test_missing_fragment_is_reported(self):
        self.page("c.html", '<a href="a/b.html#missing">n</a> <a href="#nothing">m</a>')
        _, problems = sc.check_links(self.site)
        self.assertEqual(len(problems), 2)
        self.assertTrue(all("no id" in p for p in problems))

    def test_folder_link_resolves_to_its_index(self):
        self.page("a/index.html", "x")
        self.page("c.html", '<a href="a/">a</a> <a href="a">a</a>')
        _, problems = sc.check_links(self.site)
        self.assertEqual(problems, [])

    def test_readme_html_link_is_the_bug_this_catches(self):
        self.page("c.html", '<a href="README.html">k</a>')
        _, problems = sc.check_links(self.site)
        self.assertEqual(len(problems), 1)

    def test_link_that_climbs_out_of_the_site_is_reported(self):
        self.page("c.html", '<a href="../../../etc/hosts">x</a>')
        _, problems = sc.check_links(self.site)
        self.assertEqual(len(problems), 1)

    def test_query_strings_and_percent_encoding(self):
        self.page("with space.html", "x")
        self.page("c.html", '<a href="with%20space.html?x=1">x</a>')
        _, problems = sc.check_links(self.site)
        self.assertEqual(problems, [])


class PublishTests(Site):
    def make_publish(self, cname="kits.example.org", nojekyll=True):
        self.page("index.html", "x", root=self.publish)
        self.page("a/b.html", "x", root=self.publish)
        if cname is not None:
            self.write(os.path.join(self.publish, "CNAME"), cname)
        if nojekyll:
            self.write(os.path.join(self.publish, ".nojekyll"), "")

    def test_good(self):
        self.make_publish()
        self.assertEqual(sc.check_publish(self.publish, self.site, "kits.example.org"), [])

    def test_cname_must_be_exactly_the_domain(self):
        self.make_publish(cname="kits.example.org.evil")
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 1)

    def test_trailing_newline_is_tolerated_but_other_text_is_not(self):
        self.make_publish(cname="kits.example.org\n")
        self.assertEqual(sc.check_publish(self.publish, self.site, "kits.example.org"), [])
        self.write(os.path.join(self.publish, "CNAME"), "www.kits.example.org\n")
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 1)

    def test_missing_cname_and_nojekyll(self):
        self.make_publish(cname=None, nojekyll=False)
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 2)

    def test_nojekyll_must_be_empty(self):
        self.make_publish()
        self.write(os.path.join(self.publish, ".nojekyll"), "x")
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 1)

    def test_missing_folder(self):
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 1)

    def test_different_pages_are_reported(self):
        self.make_publish()
        self.page("extra.html", "x")
        self.assertEqual(len(sc.check_publish(self.publish, self.site, "kits.example.org")), 1)


class NoindexTests(Site):
    def test_default_requires_the_tag_on_every_page(self):
        tagged, total, problems = sc.check_noindex(self.site, indexable=False)
        self.assertEqual((tagged, total, len(problems)), (0, 2, 2))
        self.page("index.html", "x", head=NOINDEX)
        self.page("a/b.html", "x", head=NOINDEX)
        tagged, total, problems = sc.check_noindex(self.site, indexable=False)
        self.assertEqual((tagged, total, problems), (2, 2, []))

    def test_indexable_requires_no_tag_anywhere(self):
        self.assertEqual(sc.check_noindex(self.site, indexable=True)[2], [])
        self.page("a/b.html", "x", head=NOINDEX)
        self.assertEqual(len(sc.check_noindex(self.site, indexable=True)[2]), 1)

    def test_a_different_robots_value_is_not_noindex(self):
        self.page("index.html", "x", head='<meta name="robots" content="all">')
        self.assertEqual(len(sc.check_noindex(self.site, indexable=False)[2]), 2)


class DiagramTests(Site):
    def copies(self):
        self.write(os.path.join(self.site, "mermaid.min.js"), JS, "wb")
        self.write(os.path.join(self.publish, "mermaid.min.js"), JS, "wb")

    def test_good(self):
        self.copies()
        self.page("d.html", '<pre><code class="language-mermaid">graph</code></pre><script src="mermaid-init-abc123.js"></script>')
        pages, blocks, problems = sc.check_diagrams(self.site, self.publish, self.vendor)
        self.assertEqual((pages, blocks, problems), (1, 1, []))

    def test_hash_mismatch_in_each_place(self):
        self.copies()
        for target in (self.site, self.publish, self.vendor):
            path = os.path.join(target, "mermaid.min.js")
            self.write(path, b"tampered", "wb")
            self.assertEqual(len(sc.check_diagrams(self.site, self.publish, self.vendor)[2]), 1, target)
            self.write(path, JS, "wb")

    def test_missing_copy_and_missing_licence(self):
        self.write(os.path.join(self.site, "mermaid.min.js"), JS, "wb")
        os.remove(os.path.join(self.vendor, "LICENSE-mermaid"))
        self.assertEqual(len(sc.check_diagrams(self.site, self.publish, self.vendor)[2]), 2)

    def test_page_with_a_diagram_must_load_the_init_script(self):
        self.copies()
        self.page("d.html", '<pre><code class="language-mermaid hljs">graph</code></pre>')
        self.assertEqual(len(sc.check_diagrams(self.site, self.publish, self.vendor)[2]), 1)

    def test_no_recorded_hash(self):
        self.write(os.path.join(self.vendor, "README.md"), "nothing here")
        self.assertEqual(len(sc.check_diagrams(self.site, self.publish, self.vendor)[2]), 1)

    def test_the_recorded_hash_of_the_real_vendored_file_is_right(self):
        real = os.path.join(TOOLS, "site", "vendor")
        self.assertEqual(sc.recorded_sha(real), sc.sha256_of(os.path.join(real, "mermaid.min.js")))


if __name__ == "__main__":
    unittest.main()

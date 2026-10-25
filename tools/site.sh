#!/bin/sh
# Build the book as an HTML website with mdBook (https://rust-lang.github.io/mdBook/).
#
#   build/site-src/      a staged copy of book/ in which links that leave the book point to GitHub (tools/site-stage.py)
#   build/mdbook/        the generated book.toml, the robots head file and the diagram script, so there is no book.toml to keep
#   build/site/          the website: what you preview locally (python3 -m http.server -d build/site); its root also holds THIRD-PARTY-NOTICES.md
#   build/site-publish/  build/site plus CNAME and .nojekyll: exactly what make publish-site commits to gh-pages
#
# The settings (SITE_DOMAIN, SITE_TITLE, SITE_REPO_URL, SITE_REPO_BRANCH, SITE_REWRITE_REPO_LINKS, SITE_INDEXABLE) are
# set in the Makefile. If mdBook is not installed this prints how to install it and exits 0.
set -eu
. "$(dirname "$0")/common.sh"
. "$TOOLS_DIR/site-env.sh"
cd "$ROOT"

# mdBook: $MDBOOK, then PATH, then the copy some builders keep in ~/.cache/mdbook/.
MDBOOK_BIN=${MDBOOK:-}
if [ -z "$MDBOOK_BIN" ]; then
  if have mdbook; then MDBOOK_BIN=$(command -v mdbook)
  elif [ -x "${HOME:-/nonexistent}/.cache/mdbook/mdbook" ]; then MDBOOK_BIN="$HOME/.cache/mdbook/mdbook"; fi
fi
if [ -z "$MDBOOK_BIN" ] || ! [ -x "$MDBOOK_BIN" ]; then
  say "mdBook is not installed, so the website was not built (nothing is wrong with the book itself)."
  case "$(os_family)" in
    macos) say "Install it with:  brew install mdbook" ;;
    *) say "Install it with:  cargo install mdbook   (or your package manager)" ;;
  esac
  say "Then run make site again. The book reads fine on GitHub without it."
  exit 0
fi

VENDOR="$ROOT/tools/site/vendor"
[ -f "$VENDOR/mermaid.min.js" ] || die "tools/site/vendor/mermaid.min.js is missing (it is committed; see tools/site/vendor/README.md)"

# 1. The staged copy of the book, with links that leave book/ rewritten to GitHub.
python3 tools/site-stage.py --repo-url "$SITE_REPO_URL" --branch "$SITE_REPO_BRANCH" --rewrite "$SITE_REWRITE_REPO_LINKS" \
  --dest "$ROOT/build/site-src"

# 2. The mdBook configuration, generated so no book.toml has to be kept in step.
CFG="$ROOT/build/mdbook"
rm -rf "$CFG"; mkdir -p "$CFG"
toml_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
cat > "$CFG/book.toml" <<TOML
[book]
title = "$(toml_str "$SITE_TITLE")"
language = "en"
src = "book"

[build]
build-dir = "../site"
create-missing = false

[output.html]
# Served at the root of the domain, so every absolute address (the 404 page) starts at /.
site-url = "/"
git-repository-url = "$(toml_str "$SITE_REPO_URL")"
edit-url-template = "$(toml_str "$SITE_REPO_URL")/edit/$(toml_str "$SITE_REPO_BRANCH")/{path}"
additional-js = ["mermaid-init.js"]

[output.html.search]
enable = true
TOML
cp "$ROOT/tools/site/mermaid-init.js" "$CFG/mermaid-init.js"
# mdBook builds the edit address as <src>/<page>. Naming the source "book" (a link to the staged copy) makes that
# <repo>/edit/<branch>/book/<page>, which is the page's real place in the repository.
ln -s ../site-src "$CFG/book"
if [ "$SITE_INDEXABLE" = 1 ]; then
  say "SITE_INDEXABLE=1: pages carry no robots meta tag, so search engines may index them."
else
  # mdBook adds theme/head.hbs to the <head> of every page, including the 404 page.
  mkdir -p "$CFG/theme"
  printf '<meta name="robots" content="noindex">\n' > "$CFG/theme/head.hbs"
  say "noindex: every page carries <meta name=\"robots\" content=\"noindex\"> (the default; SITE_INDEXABLE=1 removes it at publish time)."
fi

# 3. Build, then add the vendored diagram library (mdBook only copies what the book refers to) and its third-party notices.
rm -rf "$ROOT/build/site" "$ROOT/build/site-publish"
"$MDBOOK_BIN" build "$CFG" 2>&1 | sed 's/^/  mdbook: /'
cp "$VENDOR/mermaid.min.js" "$ROOT/build/site/mermaid.min.js"
# The licences of that bundle ask for their notice to travel with it: the notices file goes into the site root too.
[ -f "$ROOT/THIRD-PARTY-NOTICES.md" ] || die "THIRD-PARTY-NOTICES.md is missing at the repository root (it is committed; see tools/site/vendor/README.md)"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$ROOT/build/site/THIRD-PARTY-NOTICES.md"

# 4. The publish staging folder: the site, a CNAME file with the domain only, and an empty .nojekyll.
cp -R "$ROOT/build/site" "$ROOT/build/site-publish"
printf '%s' "$SITE_DOMAIN" > "$ROOT/build/site-publish/CNAME"
: > "$ROOT/build/site-publish/.nojekyll"

pages=$(find "$ROOT/build/site" -name '*.html' ! -name 404.html ! -name print.html ! -name toc.html | wc -l | tr -d ' ')
say "mdBook: $("$MDBOOK_BIN" --version)"
say "Built build/site/index.html ($pages pages, plus 404.html and print.html); publish staging in build/site-publish/ (CNAME $SITE_DOMAIN)."
say "Preview:  python3 -m http.server -d build/site 8000   then open http://localhost:8000/"
if [ "$SITE_REWRITE_REPO_LINKS" = 1 ]; then
  say "Note: links from the book into apps/, labs/ and other repository paths now point to $SITE_REPO_URL/{tree,blob}/$SITE_REPO_BRANCH/."
  say "      While that repository is private those addresses answer 404 for everyone without access; they work once it is public."
  say "      SITE_REWRITE_REPO_LINKS=0 leaves them as relative links (which do not work on the site)."
fi

#!/bin/sh
# Build the book as an HTML website with mdBook (https://rust-lang.github.io/mdBook/). Output: build/site/
# If mdBook is not installed this prints how to install it and exits 0.
set -eu
. "$(dirname "$0")/common.sh"
cd "$ROOT"
if ! have mdbook; then
  say "mdBook is not installed, so the website was not built (nothing is wrong with the book itself)."
  case "$(os_family)" in
    macos) say "Install it with:  brew install mdbook" ;;
    *) say "Install it with:  cargo install mdbook   (or your package manager)" ;;
  esac
  say "Then run make site again. The book reads fine on GitHub without it."
  exit 0
fi
# The site title is the first heading of README.md, so the name lives in one place. The config is generated
# into build/ so there is no book.toml to keep in step.
TITLE=$(sed -n 's/^# *//p' README.md | head -n 1)
CFG="$ROOT/build/mdbook"
rm -rf "$CFG"; mkdir -p "$CFG"
cat > "$CFG/book.toml" <<TOML
[book]
title = "${TITLE:-Book}"
src = "../../book"

[build]
build-dir = "../site"
create-missing = false
TOML
mdbook build "$CFG"
say "Built build/site/index.html"

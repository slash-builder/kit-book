#!/bin/sh
# Source this file (after common.sh): it makes the SITE_* settings and PUBLISH available to a script.
# The values are written in one place, the Makefile. `make` exports them; when a script is run without make
# (sh tools/site.sh), they are read from the "NAME ?= value" lines of the Makefile. A value in the environment wins.

makefile_default() {
  sed -n "s/^$1 ?= *//p" "$ROOT/Makefile" | head -n 1 | sed 's/[[:space:]]*$//'
}

for _v in SITE_DOMAIN SITE_TITLE SITE_REPO_URL SITE_REPO_BRANCH SITE_REWRITE_REPO_LINKS SITE_INDEXABLE; do
  eval "_cur=\${$_v-}"
  if [ -z "$_cur" ]; then
    _cur=$(makefile_default "$_v")
    [ -n "$_cur" ] || die "$_v is not set and has no default in the Makefile"
  fi
  eval "$_v=\$_cur"
  export "$_v"
done
unset _v _cur
PUBLISH=${PUBLISH-}
SITE_REPO_URL=${SITE_REPO_URL%/}

case "$SITE_INDEXABLE" in 0|1) ;; *) die "SITE_INDEXABLE must be 0 or 1, not '$SITE_INDEXABLE'" ;; esac
case "$SITE_REWRITE_REPO_LINKS" in 0|1) ;; *) die "SITE_REWRITE_REPO_LINKS must be 0 or 1, not '$SITE_REWRITE_REPO_LINKS'" ;; esac

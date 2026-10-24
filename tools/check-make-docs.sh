#!/bin/sh
# Every target in the Makefile's help list must be described in book/90-reference/make-targets.md.
set -eu
. "$(dirname "$0")/common.sh"
cd "$ROOT"
page=book/90-reference/make-targets.md
rc=0
for t in $(awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { print $1 }' Makefile); do
  if ! grep -qF "### \`$t\`" "$page"; then
    warn "$page: target '$t' from the Makefile is not described"
    rc=1
  fi
done
[ "$rc" = 0 ] && say "make targets: every target in the Makefile is described in $page"
exit $rc

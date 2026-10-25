#!/bin/sh
# The launch gate: one read-only run, a checklist table (ok / warn / FAIL), exit 1 on any FAIL.  make go-public-check
# The logic and the list of checks are in tools/go-public-check.py (python3 tools/go-public-check.py --list).
# GO_PUBLIC_OFFLINE=1 skips the checks that need the network and ends INCOMPLETE (exit 3), never a pass.
set -u
. "$(dirname "$0")/common.sh"
have python3 || die "python3 is needed"
have curl || die "curl is needed (it asks github.com whether each core Kit is public)"
cd "$ROOT"
exec python3 "$TOOLS_DIR/go-public-check.py" "$@"

#!/bin/sh
# Say whether an app can be built here: it can unless a Kit its apps/<app>/kits.need names is missing from .kits/.
#
#   tools/app-gate.sh APP...             quiet when every app is fine; for an app that must be skipped prints one line
#                                        "skipped apps/APP: needs storage-kit (private; fetch with KITS=all)" and exits 1 at the end
#   tools/app-gate.sh --direct APP       for a person who asked for that app by name: says what to run, exits 2 if it cannot be built
#
# The Makefile loops (make apps) use the first form and carry on; `make app APP=x` and `make run APP=x` use --direct.
set -u
. "$(dirname "$0")/common.sh"

direct=0
if [ "${1:-}" = --direct ]; then direct=1; shift; fi
rc=0
for a in "$@"; do
  dir="$ROOT/apps/$a"
  [ -d "$dir" ] || { warn "No such app: $a"; exit 2; }
  reason=$(app_skip_reason "$dir")
  [ -n "$reason" ] || continue
  if [ "$direct" = 1 ]; then
    warn "apps/$a $reason, and that Kit is not fetched here, so the app cannot be built or run."
    case "$reason" in
      *private*) warn "Fetch it with: make setup KITS=all   (it needs a GitHub login: gh auth login, or GITHUB_TOKEN; make doctor shows the state)" ;;
      *) warn "Fetch it with: make setup" ;;
    esac
    rc=2
  else
    say "skipped apps/$a: $reason"
    [ "$rc" = 2 ] || rc=1
  fi
done
exit $rc

#!/bin/sh
# Be a stranger: clone the PUBLIC repository with no GitHub credentials, then run what the README tells a newcomer to run.
# Run it AFTER the repository is public. It is read-only toward GitHub (one clone) and touches nothing in this working tree.
#
#   make stranger-test                                    clone STRANGER_REPO_URL, then make doctor, make setup, make test-fast there
#   STRANGER_DRY=1 make stranger-test                     print the plan and what would be removed from the environment; clone nothing
#   STRANGER_REPO_URL=...   the repository to clone (default https://github.com/slash-builder/kit-book; a local path works for a rehearsal)
#   STRANGER_STEPS="doctor setup test-fast"   which steps to run, in order (default: all three)
#   STRANGER_KEEP=1         keep the temporary folder (it is printed) instead of deleting it
#
# The clone and every step run in a sanitised environment (tools/stranger-env.py): the GitHub token variables are removed, git may
# not ask for a password and has no credential helper (-c credential.helper=), and `gh` is not on PATH. So a step that needs a
# credential cannot quietly use yours: it fails or skips. A fetch that SKIPS for want of a login does not make make setup fail, so
# afterwards the script checks that every `core` Kit in kits.lock is public and was fetched at its pinned commit, and fails LOUDLY if not.
# What it prints is what a stranger would see. Exit status is non-zero if anything failed.
set -u
. "$(dirname "$0")/common.sh"

URL=${STRANGER_REPO_URL:-https://github.com/slash-builder/kit-book}
STEPS=${STRANGER_STEPS:-"doctor setup test-fast"}
ENVPY="$TOOLS_DIR/stranger-env.py"
have python3 || die "python3 is needed"
have git || die "git is needed"

say "Stranger test: what someone with no GitHub account would see"
say "  repository : $URL"
say "  steps      : clone, $STEPS"
say "  environment: $(python3 "$ENVPY" plan | sed '1!s/^/               /')"
if [ "${STRANGER_DRY:-0}" = 1 ]; then
  say ""
  say "STRANGER_DRY=1: nothing was cloned or run. The plan is:"
  say "  1. mktemp a folder; check the sanitised environment (no token variable, no gh on PATH, git cannot ask for a password)"
  say "  2. git -c credential.helper= clone --depth 1 $URL <folder>/kit-book   (GIT_TERMINAL_PROMPT=0)"
  say "  3. in the clone, in that environment:"
  for s in $STEPS; do
    case "$s" in
      doctor) say "       make doctor      (a stranger's first command)" ;;
      setup) say "       make setup       (KITS=public, the default: no private Kit is fetched)" ;;
      test-fast) say "       make test-fast   (every public Kit's tests and the demo apps; an app that needs a private Kit must skip with a message)" ;;
      *) die "unknown step in STRANGER_STEPS: $s (doctor, setup, test-fast)" ;;
    esac
  done
  say "  4. after setup: every core Kit in kits.lock must be public and fetched at its pinned commit, else FAIL: 'A STRANGER COULD NOT GET ...'"
  say "  5. print a summary table; exit non-zero if any step failed. Run without STRANGER_DRY once the repository is public."
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/stranger.XXXXXX")
cleanup() { if [ "${STRANGER_KEEP:-0}" = 1 ]; then say "kept: $WORK"; else rm -rf "$WORK"; fi; }
trap cleanup EXIT INT TERM
export STRANGER_FARM="$WORK/farm"
mkdir -p "$STRANGER_FARM"
SUMMARY="$WORK/summary"
: > "$SUMMARY"
FAILED=0

say ""
say "==> 0. sanitised environment"
if ! python3 "$ENVPY" check; then
  die "the sanitised environment still has a credential reachable (above). Nothing was cloned."
fi

# step LABEL COMMAND...: run COMMAND in the sanitised environment, show its output, record the result.
step() {
  label=$1; shift
  say ""
  say "==> $label"
  t0=$(date +%s)
  if python3 "$ENVPY" run -- "$@"; then rc=0; else rc=$?; fi
  t1=$(date +%s)
  if [ "$rc" = 0 ]; then res=ok; else res="FAIL (exit $rc)"; FAILED=1; fi
  printf '%s|%s|%ss\n' "$label" "$res" "$((t1 - t0))" >> "$SUMMARY"
  return "$rc"
}

CLONE_OK=0
if step "git clone $URL" git -c credential.helper= -c core.askPass= clone --depth 1 "$URL" "$WORK/kit-book"; then CLONE_OK=1
else
  warn ""
  warn "FAILED: a stranger cannot clone $URL. If the repository is private (or does not exist) git reports 'not found' or 'terminal prompts disabled'."
fi

if [ "$CLONE_OK" = 1 ]; then
  cd "$WORK/kit-book" || die "no clone to work in"
  for s in $STEPS; do
    case "$s" in
      doctor) step "make doctor" make doctor ;;
      setup) step "make setup (KITS=public)" env -u KITS make setup || true
        say ""
        say "==> core Kits: could a stranger get them?"
        if python3 "$ENVPY" core-kits .; then printf '%s|%s|%s\n' "core Kits fetched without a login" ok "-" >> "$SUMMARY"
        else printf '%s|%s|%s\n' "core Kits fetched without a login" "FAIL" "-" >> "$SUMMARY"; FAILED=1; fi ;;
      test-fast) step "make test-fast" env -u KITS make test-fast || true ;;
      *) die "unknown step in STRANGER_STEPS: $s (doctor, setup, test-fast)" ;;
    esac
  done
fi

say ""
say "Stranger test summary ($URL)"
awk -F'|' 'BEGIN { printf "  %-44s %-14s %s\n", "Step", "Result", "Time" } { printf "  %-44s %-14s %s\n", $1, $2, $3 }' "$SUMMARY"
if [ "$FAILED" = 1 ]; then
  say ""
  say "${C_RED}FAILED: a stranger would not get a working checkout. Read the output above; fix it before announcing.${C_OFF}"
  exit 1
fi
say ""
say "${C_GREEN}OK: with no GitHub login, the clone, make doctor, make setup and make test-fast all worked.${C_OFF}"

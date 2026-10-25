#!/bin/sh
# Run the test suites and print a summary table.
#
#   tools/test-run.sh all          fast suites, then the integration suites that can run here (make test)
#   tools/test-run.sh fast         skip anything that needs Docker, Redis or a running daemon (make test-fast)
#   tools/test-run.sh integration  only the suites that need Docker, Redis or a daemon (make test-integration)
#
# Fast suites: every fetched "core" Kit's own tests (its Makefile's test target if it has one, else the native
# command: dart test, flutter test, cargo test), then labs/interface_candidates, then each demo app (flutter test).
# Integration suites (Docker containers, a broker daemon, and an app's integration_test/ run inside the built app) are skipped
# with a message when what they need is absent. Skipping is not a failure.
# Exit status is non-zero when a suite that ran has failures.
set -u
. "$(dirname "$0")/common.sh"
cd "$ROOT"
MODE=${1:-all}
case "$MODE" in all|fast|integration) ;; *) die "usage: test-run.sh all|fast|integration" ;; esac

LOGDIR="$ROOT/build/test-logs"
mkdir -p "$LOGDIR"
RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT INT TERM
ANY_FAIL=0

now() { date +%s; }

# count_dart LOG -> "passed failed skipped" from the last progress line of `dart test` / `flutter test`
count_dart() {
  awk '/^[0-9][0-9:]* [+~-]/ { last = $0 }
       END {
         p = f = s = 0
         if (match(last, /\+[0-9]+/)) p = substr(last, RSTART + 1, RLENGTH - 1)
         if (match(last, /-[0-9]+/)) f = substr(last, RSTART + 1, RLENGTH - 1)
         if (match(last, /~[0-9]+/)) s = substr(last, RSTART + 1, RLENGTH - 1)
         print p, f, s
       }' "$1"
}
# count_cargo LOG -> sums every "test result:" line
count_cargo() {
  awk '/^test result:/ { for (i = 1; i <= NF; i++) { if ($(i+1) ~ /^passed/) p += $i; if ($(i+1) ~ /^failed/) f += $i; if ($(i+1) ~ /^ignored/) s += $i } }
       END { print p + 0, f + 0, s + 0 }' "$1"
}

# run_suite LABEL KIND DIR COMMAND...   KIND: dart | cargo | other
# (variables are prefixed rs_ because this shell has no local variables and callers keep loops going)
run_suite() {
  rs_label=$1; rs_kind=$2; rs_dir=$3; shift 3
  rs_slug=$(printf '%s' "$rs_label" | tr -c 'A-Za-z0-9\n' '-' | sed 's/--*/-/g')
  rs_log="$LOGDIR/$rs_slug.log"
  printf '  running %-52s ' "$rs_label" >&2
  rs_t0=$(now)
  if (cd "$rs_dir" && "$@") > "$rs_log" 2>&1; then rs_rc=0; else rs_rc=$?; fi
  rs_t1=$(now)
  case "$rs_kind" in
    dart) set -- $(count_dart "$rs_log") ;;
    cargo) set -- $(count_cargo "$rs_log") ;;
    *) set -- - - - ;;
  esac
  if [ "$rs_rc" = 0 ]; then rs_res=pass; else rs_res=FAIL; ANY_FAIL=1; fi
  printf '%s (%ss)\n' "$rs_res" "$((rs_t1 - rs_t0))" >&2
  if [ "$rs_rc" != 0 ]; then
    warn "    last lines of $rs_log:"; tail -n 25 "$rs_log" | sed 's/^/    | /' >&2
  fi
  printf '%s|%s|%s|%s|%s|%s\n' "$rs_label" "$1" "$2" "$3" "$((rs_t1 - rs_t0))" "$rs_res" >> "$RESULTS"
}

skip_suite() {
  printf '  %-60s skipped: %s\n' "$1" "$2" >&2
  printf '%s|-|-|-|0|skipped (%s)\n' "$1" "$2" >> "$RESULTS"
}

has_make_target() { [ -f "$1/Makefile" ] && grep -Eq "^$2:" "$1/Makefile"; }

fast_suites() {
  say "Kits:"
  found=0
  fetched_kits core | while read -r name dir; do echo "$name $dir"; done > "$LOGDIR/.kits"
  while read -r name dir; do
    found=1
    if has_make_target "$dir" test-fast; then run_suite "$name: make test-fast" other "$dir" make test-fast
    elif has_make_target "$dir" test; then run_suite "$name: make test" other "$dir" make test
    else
      for entry in $(dart_packages_in "$dir" | tr ' ' '|'); do
        kind=${entry%%|*}; pdir=${entry#*|}
        [ -d "$pdir/test" ] || continue
        rel=${pdir#"$dir"/}; [ "$pdir" = "$dir" ] && rel=.
        if [ "$kind" = flutter ]; then run_suite "$name/$rel: flutter test" dart "$pdir" flutter test -r expanded
        else run_suite "$name/$rel: dart test" dart "$pdir" dart test -r expanded; fi
      done
      for cdir in $(cargo_dirs_in "$dir"); do
        rel=${cdir#"$dir"/}; [ "$cdir" = "$dir" ] && rel=.
        if (cd "$cdir" && cargo metadata --format-version 1 >/dev/null 2>&1); then
          run_suite "$name/$rel: cargo test" cargo "$cdir" cargo test
        else
          skip_suite "$name/$rel: cargo test" "cargo cannot resolve the crate; a Kit it depends on is not fetched (make setup KITS=all)"
        fi
      done
    fi
  done < "$LOGDIR/.kits"
  rm -f "$LOGDIR/.kits"
  if [ ! -d "$KITS_DIR/app-context-kit" ]; then
    say "  (no Kit fetched: run make setup first. KITS=all while the Kits are private.)"
  fi
  say "Maintainer tools:"
  run_suite "tools: docs-pull unit tests" other "$ROOT" ${PYTHON:-python3} -m unittest discover -s tools/tests -p 'test_pull_docs.py'
  if ${PYTHON:-python3} -c 'import yaml' >/dev/null 2>&1; then
    run_suite "tools: catalog generator unit tests" other "$ROOT" ${PYTHON:-python3} -m unittest discover -s tools/tests -p 'test_gen_catalog.py'
  else
    skip_suite "tools: catalog generator unit tests" "PyYAML is not installed (python3 -m pip install pyyaml); only maintainers need it"
  fi
  say "Labs and demo apps:"
  run_suite "labs/interface_candidates: flutter test" dart "$ROOT/labs/interface_candidates" flutter test -r expanded
  for a in "$ROOT"/apps/*/; do
    a=${a%/}
    # An app with a Rust core: its own `cargo test` first (no Flutter, no native library needed), when the Kits it builds against are here.
    if [ -f "$a/rust/Cargo.toml" ]; then
      if (cd "$a/rust" && cargo metadata --format-version 1 >/dev/null 2>&1); then run_suite "apps/$(basename "$a")/rust: cargo test" cargo "$a/rust" cargo test
      else skip_suite "apps/$(basename "$a")/rust: cargo test" "cargo cannot resolve the crate; a Kit it depends on is not fetched (make setup KITS=all)"; fi
    fi
    if [ -d "$KITS_DIR/app-context-kit" ]; then run_suite "apps/$(basename "$a"): flutter test" dart "$a" flutter test -r expanded
    else skip_suite "apps/$(basename "$a"): flutter test" "app-context-kit is not fetched"; fi
  done
}

integration_suites() {
  say "Integration (needs Docker, Redis, a running daemon, or a desktop to run an app on):"
  # 1. Linux containers: a Kit that ships tools/linux-test.sh runs its Dart and Rust cores in throwaway containers.
  ran=0
  for dir in "$KITS_DIR"/*/; do
    dir=${dir%/}; name=$(basename "$dir")
    [ -f "$dir/tools/linux-test.sh" ] || continue
    ran=1
    if ! have docker; then skip_suite "$name: Linux containers" "docker is not installed"
    elif ! docker info >/dev/null 2>&1; then skip_suite "$name: Linux containers" "the docker daemon is not running"
    else run_suite "$name: Linux containers (docker)" other "$dir" sh tools/linux-test.sh; fi
  done
  [ "$ran" = 1 ] || skip_suite "Linux containers" "no fetched Kit ships a container test script"
  # 1b. An app that ships integration_test/ runs inside the built app (the real native library): needs a desktop to run on.
  for a in "$ROOT"/apps/*/; do
    a=${a%/}
    [ -d "$a/integration_test" ] || continue
    label="apps/$(basename "$a"): flutter test integration_test (the built app)"
    if [ ! -d "$KITS_DIR/app-context-kit" ]; then skip_suite "$label" "app-context-kit is not fetched"
    elif [ -f "$a/rust/Cargo.toml" ] && [ ! -d "$KITS_DIR/storage-kit" ]; then skip_suite "$label" "storage-kit is not fetched (make setup KITS=all)"
    elif [ "$(os_family)" = linux ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then skip_suite "$label" "no display (on Linux run it under xvfb-run)"
    elif [ "$(os_family)" = other ]; then skip_suite "$label" "no desktop target on this system"
    else
      dev=macos; [ "$(os_family)" = linux ] && dev=linux
      run_suite "$label" dart "$a" flutter test integration_test -d "$dev" -r expanded
    fi
  done
  # 2. A resource-broker daemon: the render-queue and Rust tests run for real when VENUE_TOKEN_FILE names a token.
  if [ -z "${VENUE_TOKEN_FILE:-}" ]; then
    skip_suite "resource-broker daemon tests" "VENUE_TOKEN_FILE is not set (the fast suites skip these tests themselves)"
  elif [ ! -d "$KITS_DIR/app-context-kit" ]; then
    skip_suite "resource-broker daemon tests" "app-context-kit is not fetched"
  else
    run_suite "apps/render-queue: flutter test (real daemon)" dart "$ROOT/apps/render-queue" flutter test -r expanded test/venue_real_test.dart
  fi
  # 3. Redis-backed message-hub probes live in a private repository.
  if have redis-server; then skip_suite "message-hub probes (redis)" "they run in a private repository; nothing here yet"
  else skip_suite "message-hub probes (redis)" "redis-server is not installed, and the probes run in a private repository"; fi
}

START=$(now)
case "$MODE" in
  fast) fast_suites ;;
  integration) integration_suites ;;
  all) fast_suites; integration_suites ;;
esac
END=$(now)

say ""
awk -F'|' 'BEGIN { printf "%-62s %7s %7s %8s %8s  %s\n", "Suite", "Passed", "Failed", "Skipped", "Seconds", "Result" }
           { printf "%-62s %7s %7s %8s %8s  %s\n", $1, $2, $3, $4, $5, $6; if ($2 ~ /^[0-9]+$/) { p += $2; f += $3; s += $4 } }
           END { printf "%-62s %7d %7d %8d\n", "Total", p, f, s }' "$RESULTS"
say "Wall time $((END - START))s. Logs: build/test-logs/"
if [ "$ANY_FAIL" = 1 ]; then say "${C_RED}FAILED${C_OFF}"; exit 1; fi
say "${C_GREEN}OK${C_OFF}"

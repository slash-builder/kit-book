# Shared helpers for the scripts in tools/. Source this file; do not run it.
# POSIX sh only (macOS /bin/sh and /bin/bash 3.2, Linux dash/bash).

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$TOOLS_DIR")
KITS_DIR="$ROOT/.kits"
KITS_LOCK="${KITS_LOCK:-$ROOT/kits.lock}"

# Colours only on a terminal, and never when NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$(printf '\033[31m'); C_GREEN=$(printf '\033[32m'); C_YELLOW=$(printf '\033[33m')
  C_BOLD=$(printf '\033[1m'); C_OFF=$(printf '\033[0m')
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_OFF=''
fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# The operating system family: macos, linux or other.
os_family() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    *) echo other ;;
  esac
}

# Print the lines of kits.lock that describe a Kit (no comments, no blank lines).
lock_lines() {
  [ -f "$KITS_LOCK" ] || die "no kits.lock at $KITS_LOCK"
  grep -v '^[[:space:]]*#' "$KITS_LOCK" | grep -v '^[[:space:]]*$' || true
}

# "https://github.com/org/repo(.git)" -> "org/repo"
repo_slug() {
  printf '%s\n' "$1" | sed -e 's#^https://github\.com/##' -e 's#^git@github\.com:##' -e 's#\.git$##' -e 's#/$##'
}

# gh installed and logged in?
gh_ready() { have gh && gh auth status >/dev/null 2>&1; }

# Packages and crates inside the Kits fetched for the "core" role (and the demo apps / labs in this repository).
# Prints "flutter <dir>" or "dart <dir>" for each Dart package that has a test folder or is a dependency.
dart_packages_in() {
  base=$1
  # the root, then dart/* and packages/*; never docs/ (its examples are the Kit's own samples)
  for d in "$base" "$base"/dart/* "$base"/packages/*; do
    [ -f "$d/pubspec.yaml" ] || continue
    # labs/interface_candidates is the copy this repository uses; skip an older copy that may still sit inside a Kit
    case "$d" in "$base"/*/interface_candidates) continue ;; esac
    if grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter' "$d/pubspec.yaml"; then echo "flutter $d"; else echo "dart $d"; fi
  done
}

# Directories holding a Cargo.toml for a Kit (root or rust/).
cargo_dirs_in() {
  base=$1
  for d in "$base" "$base/rust"; do
    [ -f "$d/Cargo.toml" ] && echo "$d"
  done
  return 0
}

# override_for NAME: the checkout kits.override names for that Kit (made absolute), or nothing. See kits.override.
override_for() {
  [ -f "$ROOT/kits.override" ] || return 0
  rel=$(grep -v '^[[:space:]]*#' "$ROOT/kits.override" | awk -v n="$1" '$1 == n { print $2; exit }')
  [ -n "$rel" ] || return 0
  case "$rel" in /*) printf '%s\n' "$rel" ;; *) printf '%s\n' "$ROOT/$rel" ;; esac
}

# The flutter_rust_bridge version an app pins: the `flutter_rust_bridge: X.Y.Z` line of its pubspec.yaml (an exact version).
frb_pinned_version() {
  sed -n 's/^[[:space:]]*flutter_rust_bridge:[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*\(#.*\)\{0,1\}$/\1/p' "$1/pubspec.yaml" | head -n 1
}

# The version of the flutter_rust_bridge_codegen on PATH (or in ~/.cargo/bin, where `cargo install` puts it); fails when none.
# Sets nothing: callers that run the tool should have that folder on PATH (the Makefile does).
frb_codegen_version() {
  bin=$(command -v flutter_rust_bridge_codegen 2>/dev/null || true)
  [ -n "$bin" ] || { [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/flutter_rust_bridge_codegen" ] && bin="${CARGO_HOME:-$HOME/.cargo}/bin/flutter_rust_bridge_codegen"; }
  [ -n "$bin" ] || return 1
  "$bin" --version 2>/dev/null | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1
}

# Print "name dir" for every fetched Kit whose role is one of the given words.
fetched_kits() {
  roles=" $* "
  lock_lines | while read -r name url commit vis role _rest; do
    case "$roles" in *" $role "*) ;; *) continue ;; esac
    [ -d "$KITS_DIR/$name" ] && echo "$name $KITS_DIR/$name"
  done
}

# --- per-app Kit requirements: apps/<app>/kits.need -----------------------------------------------------------------------
# An app may list, one Kit name per line (# comments allowed), the Kits it needs besides the App Context Kit. An app whose
# needed Kit is not in .kits/ is SKIPPED by setup, test, apps, frb and doctor with a one-line reason; it is never an error.
# app_needs DIR: the Kit names in DIR/kits.need, or nothing.
app_needs() {
  [ -f "$1/kits.need" ] || return 0
  sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1/kits.need" | grep -v '^$' || true
}

# app_missing_kits DIR: the Kits the app needs that are not in .kits/ (as a folder or a link, which is how fetch-kits.sh leaves them).
app_missing_kits() {
  for amk_k in $(app_needs "$1"); do
    [ -d "$KITS_DIR/$amk_k" ] || printf '%s\n' "$amk_k"
  done
}

# kit_visibility NAME: public or private as kits.lock says, or unknown when the Kit is not listed there.
kit_visibility() {
  lock_lines | awk -v n="$1" '$1 == n { print $4; found = 1; exit } END { if (!found) print "unknown" }'
}

# app_skip_reason DIR: "needs storage-kit (private; fetch with KITS=all)" when something is missing, nothing otherwise.
app_skip_reason() {
  asr_out=""
  for asr_k in $(app_missing_kits "$1"); do
    case "$(kit_visibility "$asr_k")" in
      private) asr_why="private; fetch with KITS=all" ;;
      public) asr_why="public; fetch with make setup" ;;
      *) asr_why="not listed in kits.lock" ;;
    esac
    asr_out="${asr_out:+$asr_out, }$asr_k ($asr_why)"
  done
  [ -z "$asr_out" ] || printf 'needs %s\n' "$asr_out"
}

# included_apps: the absolute folder of every app under apps/ whose needed Kits are all fetched.
included_apps() {
  for ia_d in "$ROOT"/apps/*/; do
    ia_d=${ia_d%/}
    [ -d "$ia_d" ] || continue
    [ -z "$(app_missing_kits "$ia_d")" ] && printf '%s\n' "$ia_d"
  done
  return 0
}

# Version helpers. ver_ge A B succeeds when A >= B (dotted numbers; extra text ignored).
ver_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".");
    n = (na > nb) ? na : nb;
    for (i = 1; i <= n; i++) {
      xi = x[i] + 0; yi = y[i] + 0;
      if (xi > yi) exit 0;
      if (xi < yi) exit 1;
    }
    exit 0
  }'
}

# ask_yn PROMPT: ask on the terminal; anything but y/yes (or no terminal at all) means no.
ask_yn() {
  printf '%s [y/N] ' "$1"
  ans=n
  if { : < /dev/tty; } 2>/dev/null; then read -r ans < /dev/tty || ans=n
  elif [ -t 0 ]; then read -r ans || ans=n
  else read -r ans || ans=n; fi
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

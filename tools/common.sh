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

# Print "name dir" for every fetched Kit whose role is one of the given words.
fetched_kits() {
  roles=" $* "
  lock_lines | while read -r name url commit vis role _rest; do
    case "$roles" in *" $role "*) ;; *) continue ;; esac
    [ -d "$KITS_DIR/$name" ] && echo "$name $KITS_DIR/$name"
  done
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

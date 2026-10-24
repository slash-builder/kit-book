#!/bin/sh
# Check the build environment and say, in plain words, what is missing and how to get it.
#
#   tools/doctor.sh                     print the table
#   tools/doctor.sh --require-apps      also treat the desktop-build tools as required (used by `make apps`)
#   tools/doctor.sh --install-commands  print only the install commands for missing REQUIRED tools (used by `make setup`)
#
# It installs NOTHING. It exits non-zero only when a REQUIRED tool is missing or too old.
set -u
. "$(dirname "$0")/common.sh"

REQUIRE_APPS=0
INSTALL_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --require-apps) REQUIRE_APPS=1 ;;
    --install-commands) INSTALL_ONLY=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

OS=$(os_family)
DISTRO=""
if [ "$OS" = linux ] && [ -r /etc/os-release ]; then
  DISTRO=$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")
fi
PKG=none
case "$OS" in
  macos) PKG=brew ;;
  linux) case "$DISTRO" in *debian*|*ubuntu*) PKG=apt ;; *) PKG=other ;; esac ;;
esac

# --- minimum versions, read from the code rather than written down twice -----------------------------------------
# Dart: the highest "sdk: ^X" found in the demo apps' pubspec files.
DART_MIN=$(cat "$ROOT"/apps/*/pubspec.yaml "$ROOT"/labs/*/pubspec.yaml 2>/dev/null |
  awk '/^environment:/ {e=1; next} /^[^ #]/ {e=0} e && $1=="sdk:" && $2 ~ /^\^?[0-9]/ {v=$2; sub(/^\^/, "", v); print v}' |
  awk 'BEGIN{best="0"} { if (best=="0") best=$1; else { n=split($1,a,"."); split(best,b,"."); for(i=1;i<=3;i++){ if (a[i]+0>b[i]+0){best=$1;break} if (a[i]+0<b[i]+0) break } } } END{print best}')
[ "$DART_MIN" = 0 ] && DART_MIN=3.0.0

# Rust: the highest rust-version declared by a Kit's crate or an app's Rust core; else the first release that supports the
# first crate's edition.
RUST_MIN=""
RUST_MIN_NOTE=""
for cf in "$KITS_DIR"/*/rust/Cargo.toml "$ROOT"/apps/*/rust/Cargo.toml; do
  [ -f "$cf" ] || continue
  rv=$(sed -n 's/^rust-version[[:space:]]*=[[:space:]]*"\([0-9.]*\)".*/\1/p' "$cf" | head -n 1)
  who=$(basename "$(dirname "$(dirname "$cf")")")
  if [ -n "$rv" ]; then
    if [ -z "$RUST_MIN" ] || ! ver_ge "$RUST_MIN" "$rv"; then RUST_MIN=$rv; RUST_MIN_NOTE="rust-version in $who"; fi
    continue
  fi
  [ -n "$RUST_MIN" ] && continue
  ed=$(sed -n 's/^edition[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$cf" | head -n 1)
  case "$ed" in
    2024) RUST_MIN=1.85.0 ;;
    2021) RUST_MIN=1.56.0 ;;
    2018) RUST_MIN=1.31.0 ;;
  esac
  [ -n "$RUST_MIN" ] && RUST_MIN_NOTE="edition $ed in $who"
done
if [ -z "$RUST_MIN" ]; then RUST_MIN=1.56.0; RUST_MIN_NOTE="default; run make setup to read it from the Rust crate"; fi

# --- install commands per OS -------------------------------------------------------------------------------------
# cmd_for TOOL prints the command a person would run on this machine.
cmd_for() {
  case "$PKG:$1" in
    brew:flutter|brew:dart) echo "brew install --cask flutter" ;;
    brew:rust) echo "brew install rust" ;;
    brew:docker) echo "brew install --cask docker   (then open Docker once)" ;;
    brew:redis) echo "brew install redis" ;;
    brew:protoc) echo "brew install protobuf" ;;
    brew:gh) echo "brew install gh && gh auth login" ;;
    brew:mdbook) echo "brew install mdbook" ;;
    brew:xcode) echo "xcode-select --install" ;;
    brew:python3) echo "brew install python" ;;
    apt:flutter|apt:dart) echo "sudo snap install flutter --classic" ;;
    apt:rust) echo "sudo apt-get install -y rustc cargo   (if too old: https://rustup.rs)" ;;
    apt:docker) echo "sudo apt-get install -y docker.io" ;;
    apt:redis) echo "sudo apt-get install -y redis-server" ;;
    apt:protoc) echo "sudo apt-get install -y protobuf-compiler" ;;
    apt:gh) echo "sudo apt-get install -y gh && gh auth login" ;;
    apt:mdbook) echo "cargo install mdbook" ;;
    apt:python3) echo "sudo apt-get install -y python3" ;;
    apt:curl) echo "sudo apt-get install -y curl" ;;
    apt:tar) echo "sudo apt-get install -y tar" ;;
    apt:desktop) echo "sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev" ;;
    *:frb) echo "cargo install flutter_rust_bridge_codegen --version ${FRB_PIN:-2.12.0} --locked   (then make sure ~/.cargo/bin is on PATH, or leave it: make finds it there)" ;;
    brew:pod) echo "brew install cocoapods" ;;
    *:xcode) echo "(macOS only)" ;;
    *) echo "see the tool's own install page" ;;
  esac
}

# --- the table ---------------------------------------------------------------------------------------------------
ROWS=$(mktemp)
FIXES=$(mktemp)
trap 'rm -f "$ROWS" "$FIXES"' EXIT INT TERM
MISSING_REQUIRED=0
MISSING_APPS=0

# row TOOL LEVEL STATUS FOUND NEEDED   (LEVEL: required | apps | optional)
row() { printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$ROWS"; }
# fix KEY LEVEL WHY: remember that something has to be installed
fix() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$(cmd_for "$4")" >> "$FIXES"; }

first_version() { grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1; }

# check_tool NAME LEVEL CMD VERSION_COMMAND MIN FIXKEY WHY
check_tool() {
  name=$1; level=$2; cmd=$3; vcmd=$4; min=$5; key=$6; why=$7
  if ! have "$cmd"; then
    row "$name" "$level" "MISSING" "-" "${min:--}"
    fix "$name" "$level" "$why" "$key"
    case "$level" in required) MISSING_REQUIRED=$((MISSING_REQUIRED + 1)) ;; apps) MISSING_APPS=$((MISSING_APPS + 1)) ;; esac
    return
  fi
  found=$(sh -c "$vcmd" 2>/dev/null | first_version)
  [ -z "$found" ] && found="?"
  if [ -n "$min" ] && [ "$found" != "?" ] && ! ver_ge "$found" "$min"; then
    row "$name" "$level" "TOO OLD" "$found" "$min"
    fix "$name" "$level" "$why (has $found, needs $min)" "$key"
    case "$level" in required) MISSING_REQUIRED=$((MISSING_REQUIRED + 1)) ;; apps) MISSING_APPS=$((MISSING_APPS + 1)) ;; esac
    return
  fi
  row "$name" "$level" "ok" "$found" "${min:--}"
}

# Flutter's own bundled Dart is what the apps are built with, so that is the version that matters.
if have flutter; then
  FL_VER=$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1)
  FL_DART=$(flutter --version 2>/dev/null | sed -n 's/.*Dart \([0-9][0-9.]*\).*/\1/p' | head -n 1)
  if [ -n "$FL_DART" ] && ! ver_ge "$FL_DART" "$DART_MIN"; then
    row "flutter" required "TOO OLD" "${FL_VER:-?} (Dart $FL_DART)" "Dart $DART_MIN or newer"
    fix flutter required "the apps need Dart $DART_MIN, this Flutter has $FL_DART" flutter
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  else
    row "flutter" required ok "${FL_VER:-?} (Dart ${FL_DART:-?})" "Dart $DART_MIN or newer"
  fi
else
  row "flutter" required MISSING "-" "Dart $DART_MIN or newer"
  fix flutter required "builds and tests the apps" flutter
  MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
fi
check_tool "dart" required dart "dart --version 2>&1" "$DART_MIN" dart "runs the Kits' Dart tests (it comes with Flutter)"
check_tool "rustc" required rustc "rustc --version" "$RUST_MIN" rust "builds the Rust crate ($RUST_MIN_NOTE)"
check_tool "cargo" required cargo "cargo --version" "" rust "fetches and tests the Rust crate"
check_tool "curl" required curl "curl --version" "" curl "downloads the Kits"
check_tool "tar" required tar "tar --version 2>&1 | head -n 1" "" tar "unpacks the Kits"
check_tool "python3" required python3 "python3 --version" "3.6" python3 "checks the book's links (make docs)"

if [ "$OS" = macos ]; then
  if xcode-select -p >/dev/null 2>&1; then
    row "Xcode command line tools" required ok "installed" "-"
  else
    row "Xcode command line tools" required MISSING "-" "-"
    fix "Xcode command line tools" required "the C compiler and make that Flutter and Rust use on macOS" xcode
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  fi
  if have xcodebuild && xcodebuild -version >/dev/null 2>&1; then
    row "Xcode (full app)" apps ok "$(xcodebuild -version 2>/dev/null | first_version)" "-"
  else
    row "Xcode (full app)" apps MISSING "-" "-"
    printf '%s|%s|%s|%s\n' "Xcode (full app)" apps "needed to build the macOS apps (make apps)" "install Xcode from the App Store, open it once, then: sudo xcodebuild -runFirstLaunch" >> "$FIXES"
    MISSING_APPS=$((MISSING_APPS + 1))
  fi
fi

if [ "$OS" = linux ]; then
  desk_missing=""
  for t in clang cmake ninja pkg-config; do have "$t" || desk_missing="$desk_missing $t"; done
  if have pkg-config && ! pkg-config --exists gtk+-3.0 2>/dev/null; then desk_missing="$desk_missing gtk3-dev"; fi
  if [ -z "$desk_missing" ]; then
    row "Linux desktop tools" apps ok "clang cmake ninja pkg-config gtk3" "-"
  else
    row "Linux desktop tools" apps MISSING "-" "clang cmake ninja pkg-config gtk3-dev"
    fix "Linux desktop tools" apps "build the Linux apps (missing:$desk_missing)" desktop
    MISSING_APPS=$((MISSING_APPS + 1))
  fi
fi

# Optional tools.
if have docker; then
  if docker info >/dev/null 2>&1; then row docker optional ok "$(docker --version | first_version) (running)" "-"
  else row docker optional "not running" "$(docker --version | first_version)" "-"; printf '%s|%s|%s|%s\n' docker optional "start Docker Desktop / the docker service to run the Linux container checks" "(start it)" >> "$FIXES"; fi
else
  row docker optional MISSING "-" "-"; fix docker optional "runs the Linux container checks (make test-integration)" docker
fi
if have redis-server; then row redis-server optional ok "$(redis-server --version | first_version)" "-"
else row redis-server optional MISSING "-" "-"; fix redis-server optional "integration tests that talk to a message hub" redis; fi
if have protoc; then row protoc optional ok "$(protoc --version | first_version)" "-"
else row protoc optional MISSING "-" "-"; fix protoc optional "compiles protocol definitions, used by some Kits" protoc; fi
# flutter_rust_bridge_codegen: REQUIRED when an app in the tree has a Rust core bridged with it (apps/notes_rust), at exactly the
# version that app pins in its pubspec.yaml (the generated glue only matches the flutter_rust_bridge package at that version).
# Optional otherwise.
FRB_APP=""
for y in "$ROOT"/apps/*/flutter_rust_bridge.yaml; do [ -f "$y" ] && { FRB_APP=$(dirname "$y"); break; }; done
if [ -n "$FRB_APP" ]; then
  FRB_PIN=$(frb_pinned_version "$FRB_APP")
  FRB_HAVE=$(frb_codegen_version) || FRB_HAVE=""
  if [ -z "$FRB_HAVE" ]; then
    row flutter_rust_bridge_codegen required MISSING "-" "$FRB_PIN (exactly; pinned by $(basename "$FRB_APP"))"
    fix flutter_rust_bridge_codegen required "joins the Flutter app $(basename "$FRB_APP") to its Rust core (make frb)" frb
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  elif [ "$FRB_HAVE" != "$FRB_PIN" ]; then
    row flutter_rust_bridge_codegen required "WRONG VERSION" "$FRB_HAVE" "$FRB_PIN (exactly; pinned by $(basename "$FRB_APP"))"
    fix flutter_rust_bridge_codegen required "$(basename "$FRB_APP") pins $FRB_PIN and the generated bridge must match it (has $FRB_HAVE)" frb
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  else
    row flutter_rust_bridge_codegen required ok "$FRB_HAVE" "$FRB_PIN (exactly)"
  fi
elif FRB_HAVE=$(frb_codegen_version); then row flutter_rust_bridge_codegen optional ok "$FRB_HAVE" "-"
else row flutter_rust_bridge_codegen optional MISSING "-" "-"; fix flutter_rust_bridge_codegen optional "joins a Flutter app to a Rust core (no app in the tree needs it)" frb; fi
if [ "$OS" = macos ] && ls "$ROOT"/apps/*/macos/Podfile >/dev/null 2>&1; then
  # An app with a native (CocoaPods) plugin, such as the cargokit glue of a Rust core, builds through CocoaPods.
  check_tool "pod (CocoaPods)" apps pod "pod --version 2>/dev/null" "" pod "builds the macOS apps that have a native plugin (a Rust core)"
fi
if gh_ready; then row "gh (GitHub CLI)" optional ok "logged in" "-"
elif have gh; then row "gh (GitHub CLI)" optional "not logged in" "-" "-"; printf '%s|%s|%s|%s\n' "gh (GitHub CLI)" optional "needed only for private Kits (KITS=all)" "gh auth login" >> "$FIXES"
else row "gh (GitHub CLI)" optional MISSING "-" "-"; fix "gh (GitHub CLI)" optional "needed only for private Kits (KITS=all)" gh; fi
if have mdbook; then row mdbook optional ok "$(mdbook --version | first_version)" "-"
else row mdbook optional MISSING "-" "-"; fix mdbook optional "builds the book as a website (make site)" mdbook; fi

# --- output ------------------------------------------------------------------------------------------------------
if [ "$INSTALL_ONLY" = 1 ]; then
  # Only REQUIRED tools; commands that are real shell commands (skip the parenthesised hints).
  awk -F'|' '$2=="required" && $4 !~ /^\(/ && $4 !~ /^install Homebrew/ && $4 !~ /^see / {print $4}' "$FIXES" | sed 's/   (.*//' | awk '!seen[$0]++'
  exit 0
fi

say "Build environment on $(uname -s) $(uname -m)"
say ""
printf '%s\n' "$(awk -F'|' 'BEGIN{printf "%-27s %-10s %-9s %-26s %s", "Tool", "Needed?", "Status", "Found", "Wanted"}')"
awk -F'|' -v R="$C_RED" -v G="$C_GREEN" -v Y="$C_YELLOW" -v O="$C_OFF" '
  { need = ($2=="required") ? "required" : ($2=="apps") ? "for apps" : "optional";
    col = ($3=="ok") ? G : ($2=="optional") ? Y : R;
    printf "%-27s %-10s %s%-9s%s %-26s %s\n", $1, need, col, $3, O, $4, $5 }' "$ROWS"
say ""
say "Needed?  required = nothing works without it; for apps = only needed to build and run the demo apps; optional = nice to have."

if [ -s "$FIXES" ]; then
  say ""
  say "What to do:"
  if [ "$PKG" = brew ] && ! have brew; then
    say "  Homebrew (the macOS package manager) is not installed. Install it first from https://brew.sh, then use the commands below."
  fi
  awk -F'|' '{ lvl = ($2=="required") ? "REQUIRED" : ($2=="apps") ? "for apps" : "optional";
               printf "  [%s] %s: %s\n        %s\n", lvl, $1, $3, $4 }' "$FIXES"
  say ""
  say "make doctor installs nothing. Run the commands above yourself, or let make setup run the REQUIRED ones: SETUP_INSTALL=1 make setup"
fi

say ""
if [ "$MISSING_REQUIRED" -gt 0 ]; then
  say "${C_RED}Result: $MISSING_REQUIRED required tool(s) missing or too old. Fix the [REQUIRED] items above, then run make doctor again.${C_OFF}"
  exit 1
fi
if [ "$REQUIRE_APPS" = 1 ] && [ "$MISSING_APPS" -gt 0 ]; then
  say "${C_RED}Result: $MISSING_APPS tool(s) needed to build the apps are missing. Fix the [for apps] items above.${C_OFF}"
  exit 1
fi
if [ "$MISSING_APPS" -gt 0 ]; then
  say "${C_YELLOW}Result: ready to fetch Kits and run tests. Building the apps (make apps) also needs the [for apps] items above.${C_OFF}"
else
  say "${C_GREEN}Result: everything required is installed.${C_OFF}"
fi
exit 0

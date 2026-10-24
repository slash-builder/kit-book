#!/bin/sh
# Set up this checkout so that `make test` and `make apps` work. Safe to run again at any time.
#
#   tools/setup.sh                      doctor, fetch public Kits, fetch packages
#   KITS=all tools/setup.sh             also fetch private Kits (needs a GitHub login)
#   SETUP_INSTALL=1 tools/setup.sh      offer to run the install commands for missing REQUIRED tools (asks y/N first)
set -eu
. "$(dirname "$0")/common.sh"
cd "$ROOT"

say "==> 1/4 Checking the toolchain"
if ! sh "$TOOLS_DIR/doctor.sh"; then
  if [ "${SETUP_INSTALL:-0}" = 1 ]; then
    cmds=$(sh "$TOOLS_DIR/doctor.sh" --install-commands)
    if [ -z "$cmds" ]; then die "required tools are missing and there is no automatic install command for this system. Follow the list above."; fi
    say ""
    say "SETUP_INSTALL=1 is set. These commands would be run:"
    printf '%s\n' "$cmds" | sed 's/^/    /'
    if ask_yn "Run them now?"; then
      printf '%s\n' "$cmds" | while IFS= read -r c; do say "+ $c"; sh -c "$c" || die "that command failed; fix it and run make setup again"; done
    else
      die "nothing installed. Install the missing tools yourself, then run make setup again."
    fi
    say ""
    sh "$TOOLS_DIR/doctor.sh" >/dev/null || die "some required tools are still missing after the install. Run make doctor."
  else
    say ""
    die "required tools are missing. Install them (commands above), or run: SETUP_INSTALL=1 make setup"
  fi
fi

say ""
say "==> 2/4 Fetching Kits (KITS=${KITS:-public})"
sh "$TOOLS_DIR/fetch-kits.sh"

say ""
say "==> 3/4 Fetching Dart and Flutter packages"
pub_get() {
  kind=$1; dir=$2
  rel=${dir#"$ROOT"/}
  printf '  %-9s %s\n' "$kind" "$rel"
  if [ "$kind" = flutter ]; then (cd "$dir" && flutter pub get >/dev/null 2>"$ROOT/.kits/.pubget.err") || { warn "pub get failed in $rel:"; cat "$ROOT/.kits/.pubget.err" >&2; return 1; }
  else (cd "$dir" && dart pub get >/dev/null 2>"$ROOT/.kits/.pubget.err") || { warn "pub get failed in $rel:"; cat "$ROOT/.kits/.pubget.err" >&2; return 1; }
  fi
}
FAIL=0
# Kit packages first (the apps depend on them), then labs, then apps.
fetched_kits core | while read -r name dir; do dart_packages_in "$dir"; done > "$KITS_DIR/.pkgs" || true
{ cat "$KITS_DIR/.pkgs"; dart_packages_in "$ROOT/labs/interface_candidates" | sed -n '1p'; for a in "$ROOT"/apps/*/; do dart_packages_in "${a%/}"; done; } > "$KITS_DIR/.pkgs.all"
if [ ! -s "$KITS_DIR/.pkgs" ]; then
  say "  (no Kit is fetched, so the demo apps cannot resolve their dependencies; run make setup KITS=all while the Kits are private)"
fi
HAVE_APPKIT=0; [ -d "$KITS_DIR/application-kit" ] && HAVE_APPKIT=1
while read -r kind dir; do
  case "$dir" in
    "$ROOT"/apps/*) if [ "$HAVE_APPKIT" = 0 ]; then printf '  %-9s %s  (skipped: application-kit not fetched)\n' "$kind" "${dir#"$ROOT"/}"; continue; fi ;;
  esac
  pub_get "$kind" "$dir" || FAIL=1
done < "$KITS_DIR/.pkgs.all"
rm -f "$KITS_DIR/.pkgs" "$KITS_DIR/.pkgs.all" "$KITS_DIR/.pubget.err"

say ""
say "==> 4/4 Fetching Rust crates"
FOUND_CARGO=0
fetched_kits core | while read -r name dir; do
  for c in $(cargo_dirs_in "$dir"); do
    rel=${c#"$ROOT"/}
    if (cd "$c" && cargo fetch >"$KITS_DIR/.cargo.out" 2>&1); then printf '  cargo     %s\n' "$rel"
    else printf '  cargo     %s  (skipped: could not resolve; a path dependency on a Kit that is not fetched? try make setup KITS=all)\n' "$rel"; fi
  done
done
rm -f "$KITS_DIR/.cargo.out"
[ -n "$(fetched_kits core)" ] || say "  (no Rust crate to fetch yet)"

say ""
if [ "$FAIL" = 0 ]; then say "Setup finished. Next: make test-fast"; else die "setup finished with errors (see above)"; fi

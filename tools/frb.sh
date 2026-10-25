#!/bin/sh
# Regenerate the flutter_rust_bridge glue of every app that has a flutter_rust_bridge.yaml (today: apps/notes_rust).
#
#   tools/frb.sh            run `flutter_rust_bridge_codegen generate` in each such app
#
# The generated files (lib/src/rust/* and rust/src/frb_generated.rs) are COMMITTED, so a clean checkout builds without this
# tool; run it after changing the bridge layer (rust/src/api/*.rs) and commit the result. It refuses to run with a codegen
# whose version differs from the one the app pins, because a different version writes different glue that does not match the
# flutter_rust_bridge package (Dart) and crate (Rust) at the pinned version.
set -eu
. "$(dirname "$0")/common.sh"
cd "$ROOT"

found=0
skipped=0
for yaml in apps/*/flutter_rust_bridge.yaml; do
  [ -f "$yaml" ] || continue
  app=$(dirname "$yaml")
  # an app whose needed Kit is not fetched (apps/<app>/kits.need) is skipped, not an error
  reason=$(app_skip_reason "$ROOT/$app")
  if [ -n "$reason" ]; then say "skipped $app: $reason"; skipped=1; continue; fi
  found=1
  want=$(frb_pinned_version "$app")
  have_v=$(frb_codegen_version) || die "flutter_rust_bridge_codegen is not installed. Install it: cargo install flutter_rust_bridge_codegen --version $want --locked"
  [ "$have_v" = "$want" ] || die "flutter_rust_bridge_codegen is $have_v but $app pins $want. Install the pinned one: cargo install flutter_rust_bridge_codegen --version $want --locked --force"
  say "==> $app: flutter_rust_bridge_codegen $have_v generate"
  (cd "$app" && flutter_rust_bridge_codegen generate)
done
if [ "$found" = 0 ]; then
  if [ "$skipped" = 1 ]; then say "nothing to generate here: the app(s) with a bridge are skipped (see above)"
  else say "no app has a flutter_rust_bridge.yaml: nothing to generate"; fi
fi

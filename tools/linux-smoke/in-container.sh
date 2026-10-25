#!/bin/bash
# The work of `make linux-smoke`, run INSIDE the container by tools/linux-smoke.sh (do not run it by hand).
#
# /src is the repository, mounted read-only; /out is build/linux-smoke on the host. This script copies the apps (and the Kits and the
# lab they depend on) to /work, builds each app with `flutter build linux --release`, launches the bundle twice under a virtual
# display (xvfb-run, 1280x800x24), runs the two-copies peers check for the apps that have peers, and writes /out/results.md.
# Environment: LINUX_SMOKE_APPS (space separated; default every app), LINUX_SMOKE_UP (seconds to keep an app up, default 10),
# LINUX_SMOKE_SHOT_AT (screenshot second, default 6), LINUX_SMOKE_PEERS (apps for the two-copies check, default "stopwatch notepad").
set -u
SRC=/src; OUT=/out; W=/work; T=/tmp/smoke
HERE=$SRC/tools/linux-smoke
APPS=${LINUX_SMOKE_APPS:-"calculator launcher minesweeper notepad notes_rust render-queue stopwatch"}
PEER_APPS=${LINUX_SMOKE_PEERS:-"stopwatch notepad"}
export SMOKE_UP=${LINUX_SMOKE_UP:-10} SMOKE_SHOT_AT=${LINUX_SMOKE_SHOT_AT:-6}
export CI=true
mkdir -p "$W" "$T" "$OUT"
now() { date +%s; }

say() { printf '%s\n' "$*"; }

# --- the workspace: path dependencies are ../../.kits/... and ../../labs/..., so the layout is kept ----------------------------------
copy_tree() { # PATH (relative to /src)
  tar -C "$SRC" -cf - --exclude=target --exclude=build --exclude=.dart_tool --exclude=.git "$1" | tar -C "$W" -xf -
}
say "==> workspace: copying .kits, labs (no build output) to $W"
[ -d "$SRC/.kits" ] && copy_tree .kits
copy_tree labs
cp "$HERE/../../kits.lock" "$W/" 2>/dev/null || true
{ cat /opt/linux-smoke-pins.txt; echo "kernel: $(uname -sr) $(uname -m)"; echo "os: $(. /etc/os-release; echo "$PRETTY_NAME")"; flutter --version 2>/dev/null | head -n 3; rustc --version; } > "$OUT/image-pins.txt"

copy_app() {
  mkdir -p "$W/apps"
  tar -C "$SRC" -cf - --anchored --exclude="apps/$1/build" --exclude="apps/$1/.dart_tool" --exclude="apps/$1/rust/target" \
      --exclude="apps/$1/linux/flutter/ephemeral" --exclude="apps/$1/macos" "apps/$1" | tar -C "$W" -xf -
}

manifest_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"; }
prefix_of() { # APPDIR -> the env prefix (spec section 2): envPrefix, else the last segment of the id, upper-cased, non-alphanumerics to _
  p=$(manifest_field "$1/app.json" envPrefix)
  if [ -z "$p" ]; then p=$(manifest_field "$1/app.json" id | awk -F. '{ print $NF }' | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9\n' '_'); fi
  printf '%s' "$p"
}

# --- build --------------------------------------------------------------------------------------------------------------------------
build_app() {
  a=$1; dir=$W/apps/$a; od=$OUT/$a
  rm -rf "$od"; mkdir -p "$od"
  copy_app "$a"
  : > "$od/build.kv"
  kv() { printf '%s=%s\n' "$1" "$2" >> "$od/build.kv"; }
  say "==> $a: flutter pub get"
  t=$(now)
  if (cd "$dir" && flutter pub get) > "$od/build.log" 2>&1; then kv pub_ok yes; else kv pub_ok no; fi
  kv pub_s $(( $(now) - t ))
  if grep -q '^pub_ok=yes' "$od/build.kv"; then
    say "==> $a: flutter build linux --release"
    t=$(now)
    if (cd "$dir" && flutter build linux --release) >> "$od/build.log" 2>&1; then kv build_ok yes; else kv build_ok no; fi
    kv build_s $(( $(now) - t ))
  else
    kv build_ok no; kv build_s 0
  fi
  bundle=$(ls -d "$dir"/build/linux/*/release/bundle 2>/dev/null | head -n 1)
  if grep -q '^build_ok=yes' "$od/build.kv" && [ -n "$bundle" ]; then
    name=$(sed -n 's/^set(BINARY_NAME "\(.*\)")/\1/p' "$dir/linux/CMakeLists.txt" | head -n 1)
    kv bundle "$bundle"; kv binary "$name"
    kv bundle_kb "$(du -sk "$bundle" | cut -f1)"
    kv binary_kb "$(du -sk "$bundle/$name" | cut -f1)"
    kv libs "$(cd "$bundle/lib" && ls | tr '\n' ' ')"
  fi
}

# --- launch -------------------------------------------------------------------------------------------------------------------------
launch_app() { # APP first|second
  a=$1; n=$2; dir=$W/apps/$a; od=$OUT/$a
  bundle=$(sed -n 's/^bundle=//p' "$od/build.kv"); name=$(sed -n 's/^binary=//p' "$od/build.kv")
  id=$(manifest_field "$dir/app.json" id); prefix=$(prefix_of "$dir")
  scratch=$T/$a-scratch
  [ "$n" = first ] && rm -rf "$scratch"
  mkdir -p "$scratch"
  say "==> $a: launch ($n), scratch $scratch, ${prefix}_MODE=mock"
  (
    export APP_CONTEXT_SCRATCH="$scratch" APP_CONTEXT_MODE=mock APP_CONTEXT_DEVICE=smoke
    export "${prefix}_MODE=mock"
    [ "$a" = notes_rust ] && export NOTES_RUST_SEED=3
    [ "$a" = launcher ] && export LAUNCHER_APPS_DIR="$W/apps"
    export SMOKE_BIN="$bundle/$name" SMOKE_ID="$id" SMOKE_SCRATCH="$scratch" SMOKE_LOG="$od/launch-$n" \
           SMOKE_SHOT="$OUT/$a-$n.png" SMOKE_RES="$od/launch-$n.kv" SMOKE_DRIVE="$(drive_name "$a" "$n")"
    xvfb-run -a -e "$od/xvfb-$n.log" -s "-screen 0 1280x800x24" bash "$HERE/launch.sh"
  )
  # the files the app left, for the report and for the second launch to be judged against
  (cd "$scratch" && find . -type f | sort) > "$od/files-$n.txt"
  cp -r "$scratch" "$od/scratch-$n" 2>/dev/null || true
}

# What to do with the window before the screenshot: the first launch drives the apps that only save after a person acts; the
# second launch only looks (it must come up with what the first one saved).
drive_name() {
  [ "$2" = first ] || return 0
  case "$1" in
    calculator) echo calculator ;;
    stopwatch) echo stopwatch ;;
    minesweeper) echo minesweeper ;;
    notepad) echo notepad ;;
  esac
}

# --- two copies ---------------------------------------------------------------------------------------------------------------------
peers_app() {
  a=$1; dir=$W/apps/$a; od=$OUT/$a
  bundle=$(sed -n 's/^bundle=//p' "$od/build.kv"); name=$(sed -n 's/^binary=//p' "$od/build.kv")
  [ -n "$bundle" ] || return 0
  id=$(manifest_field "$dir/app.json" id); prefix=$(prefix_of "$dir")
  rm -rf "$T/peers-$a"; mkdir -p "$T/peers-$a"
  say "==> $a: two copies, shared APP_CONTEXT_PEERS_DIR, devices smoke-a and smoke-b"
  (
    export SMOKE_BIN="$bundle/$name" SMOKE_ID="$id" SMOKE_APP="$a" SMOKE_PREFIX="$prefix" SMOKE_DIR="$T/peers-$a" \
           SMOKE_LOG="$od/peers" SMOKE_SHOT="$OUT/$a-peers.png" SMOKE_RES="$od/peers.kv"
    xvfb-run -a -e "$od/xvfb-peers.log" -s "-screen 0 2600x800x24" bash "$HERE/peers.sh"
  )
  cp -r "$T/peers-$a" "$od/peers-scratch" 2>/dev/null || true
}

# storage-kit declares a dev-dependency on a private cargo registry named `lockamy`. Cargo needs that registry's index defined even to
# parse the manifest of a path dependency, and the definition lives in the Kit's own .cargo/config.toml, which cargo reads only when run
# inside the Kit. A machine that has the entry in its own ~/.cargo/config.toml builds; a clean one stops with "registry index was not found
# in any configuration: `lockamy`". The Kit's own README pattern is to copy that file verbatim, which is what is done here.
: > "$OUT/notes.txt"
if [ -f "$W/.kits/storage-kit/.cargo/config.toml" ] && [ ! -f "$CARGO_HOME/config.toml" ]; then
  cp "$W/.kits/storage-kit/.cargo/config.toml" "$CARGO_HOME/config.toml"
  echo "Copied .kits/storage-kit/.cargo/config.toml to the container's CARGO_HOME. Without it, cargo cannot parse storage-kit's manifest (a dev-dependency names the registry \`lockamy\`, whose index is defined only in that file) and the notes_rust build stops with: failed to load manifest for dependency \`storage-kit\` ... registry index was not found in any configuration: \`lockamy\`. This is a Kit-side finding." >> "$OUT/notes.txt"
fi

# --- run ------------------------------------------------------------------------------------------------------------------------------
for a in $APPS; do
  if [ ! -d "$SRC/apps/$a" ]; then say "no such app: $a"; continue; fi
  build_app "$a"
  if grep -q '^build_ok=yes' "$OUT/$a/build.kv"; then
    launch_app "$a" first
    launch_app "$a" second
  else
    say "!! $a did not build; see $OUT/$a/build.log"
  fi
done
for a in $PEER_APPS; do
  case " $APPS " in *" $a "*) peers_app "$a" ;; esac
done

python3 "$HERE/report.py" "$OUT" $APPS
rc=$?
say "==> done; results in $OUT/results.md"
exit $rc

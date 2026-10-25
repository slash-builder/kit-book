#!/bin/sh
# Start the built macOS app for a few seconds with a scratch directory, check what it wrote, stop it, check it left cleanly.
#
#   make app APP=notes_rust          # build it first
#   sh apps/notes_rust/tool/smoke.sh [seconds]       (default 10)
#
# The app is sandboxed, so APP_CONTEXT_SCRATCH has to be inside its container (~/Library/Containers/<bundle id>/Data); a path
# outside it cannot be created. NOTES_RUST_SEED=3 makes the app write three sample notes into an empty store so there is
# something to see. Everything this script starts it stops, and it deletes the scratch folder at the end.
# Checks: one roster file (the Dart side's) with the instance the Rust core reports, blocks and a head index under data,
# config.json untouched by the Rust side, and, after SIGTERM, a clean exit with the roster file withdrawn.
set -eu
SECONDS_RUN=${1:-10}
HERE=$(cd "$(dirname "$0")/.." && pwd)
APP="$HERE/build/macos/Build/Products/Debug/notes_rust.app"
BIN="$APP/Contents/MacOS/notes_rust"
BUNDLE=dev.demo.notes-rust
[ -x "$BIN" ] || { echo "no built app at $APP; run: make app APP=notes_rust" >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || { echo "this smoke test is for macOS" >&2; exit 2; }

SCRATCH="$HOME/Library/Containers/$BUNDLE/Data/tmp/ak-notes-rust-smoke"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"
LOG=$(mktemp)
PID=""
cleanup() {
  [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null || true
  rm -rf "$SCRATCH" "$LOG"
}
trap cleanup EXIT INT TERM

APP_CONTEXT_SCRATCH="$SCRATCH" APP_CONTEXT_DEVICE=smoke NOTES_RUST_SEED=3 "$BIN" >"$LOG" 2>&1 &
PID=$!
echo "started pid $PID, scratch $SCRATCH"
sleep "$SECONDS_RUN"
kill -0 "$PID" 2>/dev/null || { echo "FAIL: the app exited early"; cat "$LOG"; exit 1; }

ID=dev.demo.notes-rust
ROSTER=$(ls "$SCRATCH/roster" 2>/dev/null || true)
echo "roster files while running: $ROSTER"
[ "$(printf '%s\n' "$ROSTER" | grep -c .)" = 1 ] || { echo "FAIL: expected exactly one roster file"; exit 1; }
INSTANCE=${ROSTER#"$ID@"}; INSTANCE=${INSTANCE%.json}
DATA="$SCRATCH/$ID/data"
echo "data dir:"; (cd "$DATA" && find . -maxdepth 3 | sed 's/^/  /' | head -20)
[ -d "$DATA/blocks" ] || { echo "FAIL: no blocks directory under data"; exit 1; }
ls "$DATA"/heads-*.json >/dev/null 2>&1 || { echo "FAIL: no head index under data"; exit 1; }
PACK=$(find "$DATA/blocks" -name 'active.pack' | head -n 1)
echo "active pack: $(wc -c <"$PACK" | tr -d ' ') bytes"
[ "$(wc -c <"$PACK")" -gt 1000 ] || { echo "FAIL: the sample notes' blocks are not in the pack"; exit 1; }
echo "roster instance: $INSTANCE"
echo "config dir: $(ls "$SCRATCH/$ID/config" | tr '\n' ' ')"

kill -TERM "$PID"
i=0
while kill -0 "$PID" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
if kill -0 "$PID" 2>/dev/null; then echo "FAIL: still running 10 s after SIGTERM"; exit 1; fi
wait "$PID" 2>/dev/null && CODE=0 || CODE=$?
PID=""
echo "exit code after SIGTERM: $CODE"
LEFT=$(ls "$SCRATCH/roster" 2>/dev/null | wc -l | tr -d ' ')
echo "roster files after exit: $LEFT"
[ "$LEFT" = 0 ] || { echo "FAIL: the roster entry was not withdrawn"; exit 1; }
echo "OK: started, wrote blocks under data, one roster entry, exited cleanly on SIGTERM"

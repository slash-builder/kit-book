#!/bin/bash
# One launch of one built app, run INSIDE a virtual display (tools/linux-smoke/in-container.sh starts it under xvfb-run).
#
# Timeline: start the bundle; wait for its window; optionally drive it with xdotool (a click, some typing) so it has something to
# save; screenshot at SMOKE_SHOT_AT seconds; at SMOKE_UP seconds check it is still running and list the roster and the files it
# wrote; send SIGTERM; record the exit code, whether the roster entry was withdrawn, and the files left.
#
# Inputs (environment): SMOKE_BIN (the executable), SMOKE_ID (manifest id), SMOKE_SCRATCH (APP_CONTEXT_SCRATCH, which the caller has
# also exported with the app's other variables), SMOKE_LOG (prefix: writes <prefix>.out and <prefix>.err), SMOKE_SHOT (png path),
# SMOKE_RES (key=value result file), SMOKE_DRIVE (a driver name from tools/linux-smoke/drive.sh, or empty), SMOKE_UP (default 10),
# SMOKE_SHOT_AT (default 6). Not meant to be run by hand.
set -u
SMOKE_UP=${SMOKE_UP:-10}
SMOKE_SHOT_AT=${SMOKE_SHOT_AT:-6}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=drive.sh
. "$here/drive.sh"

alive() { [ -r "/proc/$1/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status"; }
since() { awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }'; }
sleep_until() { # seconds after the start
  rem=$(awk -v a="$t0" -v b="$(date +%s.%N)" -v t="$1" 'BEGIN { r = t - (b - a); if (r < 0) r = 0; printf "%.2f", r }')
  sleep "$rem"
}
files_of() { (cd "$SMOKE_SCRATCH" 2>/dev/null && find . -type f -printf '%P %s\n' | sort) | tr '\n' ';'; }
roster_of() { ls "$SMOKE_SCRATCH/roster" 2>/dev/null | tr '\n' ' '; }

: > "$SMOKE_RES"
res() { printf '%s=%s\n' "$1" "$2" >> "$SMOKE_RES"; }

cd "$(dirname "$SMOKE_BIN")" || exit 2
t0=$(date +%s.%N)
"$SMOKE_BIN" > "$SMOKE_LOG.out" 2> "$SMOKE_LOG.err" &
pid=$!

win=""
i=0
while [ $i -lt 100 ]; do
  win=$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -n 1)
  [ -n "$win" ] && break
  alive "$pid" || break
  sleep 0.1; i=$((i + 1))
done
if [ -n "$win" ]; then res window_s "$(since)"; res window "$(xdotool getwindowgeometry "$win" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')"; else res window_s none; fi

if [ -n "${SMOKE_DRIVE:-}" ] && [ -n "$win" ]; then
  sleep 2
  drive "$SMOKE_DRIVE" "$win" > "$SMOKE_LOG.drive" 2>&1
  res drive "$SMOKE_DRIVE"
fi

sleep_until "$SMOKE_SHOT_AT"
import -window root "$SMOKE_SHOT" 2> "$SMOKE_LOG.shot" && res screenshot_at "$(since)"

sleep_until "$SMOKE_UP"
if alive "$pid"; then res running_at_up yes; else res running_at_up no; fi
res roster_during "$(roster_of)"
res files_during "$(files_of)"

if alive "$pid"; then
  kill -TERM "$pid" 2>/dev/null
  tk=$(date +%s.%N)
  i=0
  while alive "$pid" && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  res term_to_exit_s "$(awk -v a="$tk" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }')"
  if alive "$pid"; then res hung_after_sigterm yes; kill -KILL "$pid" 2>/dev/null; fi
fi
wait "$pid" 2>/dev/null; code=$?
res exit_code "$code"
res roster_after "$(roster_of)"
res files_after "$(files_of)"
exit 0

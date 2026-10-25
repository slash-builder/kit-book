#!/bin/bash
# Two copies of one built app in one virtual display, sharing APP_CONTEXT_PEERS_DIR and with distinct APP_CONTEXT_DEVICE values, in real
# (not mock) mode so the Kit's loopback provider is used: announcement files in the peers directory and TCP on 127.0.0.1.
# Run INSIDE xvfb-run (tools/linux-smoke/in-container.sh does it; the screen is wide enough for two 1280-pixel windows).
# The apps do not log peers, so what this records is: the announcement files each copy wrote, the TCP connections between the two
# processes (read from /proc), where the second window went, a screenshot, and (notepad) a note seeded into copy A's folder
# that should arrive in copy B's folder through the app's own sync.
#
# Inputs (environment): SMOKE_BIN, SMOKE_ID, SMOKE_APP, SMOKE_PREFIX, SMOKE_DIR (a fresh working directory), SMOKE_LOG (prefix),
# SMOKE_SHOT (png), SMOKE_RES (result file), SMOKE_WAIT (seconds to let them find each other, default 9).
set -u
SMOKE_WAIT=${SMOKE_WAIT:-9}
alive() { [ -r "/proc/$1/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status"; }
: > "$SMOKE_RES"
res() { printf '%s=%s\n' "$1" "$2" >> "$SMOKE_RES"; }

peers=$SMOKE_DIR/peers
mkdir -p "$peers" "$SMOKE_DIR/a" "$SMOKE_DIR/b"

# A note seeded into copy A before it starts (notepad only): the folder layout and file format are the app's (apps/notepad/lib/logic).
if [ "$SMOKE_APP" = notepad ]; then
  d=$SMOKE_DIR/a/$SMOKE_ID/data/notes
  mkdir -p "$d"
  printf '%s\n' '{"v":1,"id":"seededbysmoke","title":"Seeded by the smoke test","body":"This note was written into copy A folder by the harness.","createdAt":"2026-10-24T12:00:00.000Z","updatedAt":"2026-10-24T12:00:00.000Z"}' > "$d/seededbysmoke.json"
  res seeded_note_in_a "$d/seededbysmoke.json"
fi

launch() { # a|b DEVICE
  (
    export APP_CONTEXT_SCRATCH="$SMOKE_DIR/$1" APP_CONTEXT_MODE=real APP_CONTEXT_PEERS_DIR="$peers" APP_CONTEXT_DEVICE="$2"
    export "${SMOKE_PREFIX}_MODE=real"
    cd "$(dirname "$SMOKE_BIN")" && exec "$SMOKE_BIN" > "$SMOKE_LOG-$1.out" 2> "$SMOKE_LOG-$1.err"
  ) &
  LAST_PID=$!
}
window_of() { # pid
  i=0; w=""
  while [ $i -lt 100 ]; do
    w=$(xdotool search --onlyvisible --pid "$1" 2>/dev/null | head -n 1)
    [ -n "$w" ] && break
    sleep 0.1; i=$((i + 1))
  done
  echo "$w"
}

launch a smoke-a; pa=$LAST_PID
wa=$(window_of "$pa")
launch b smoke-b; pb=$LAST_PID
wb=$(window_of "$pb")
res pids "a=$pa b=$pb"
res windows "a=${wa:-none} b=${wb:-none}"
[ -n "$wb" ] && xdotool windowmove "$wb" 1290 0
sleep "$SMOKE_WAIT"

if alive "$pa"; then res a_running yes; else res a_running no; fi
if alive "$pb"; then res b_running yes; else res b_running no; fi
res announcements "$(cd "$peers" && find . -type f | sort | tr '\n' ' ')"
res announcement_contents "$(cd "$peers" && find . -type f | sort | while read -r f; do printf '%s: ' "$f"; tr -d '\n' < "$f"; printf ' | '; done)"

# TCP connections on 127.0.0.1 between a socket of A and a socket of B, from /proc (no ss in the image).
python3 - "$pa" "$pb" >> "$SMOKE_RES" <<'PY'
import os, sys
pa, pb = sys.argv[1:3]
def inodes(pid):
    out = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                l = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if l.startswith("socket:["):
                out.add(l[8:-1])
    except OSError:
        pass
    return out
ia, ib = inodes(pa), inodes(pb)
est, listen = [], []
for line in open("/proc/net/tcp").read().splitlines()[1:]:
    f = line.split()
    local, remote, st, inode = f[1], f[2], f[3], f[9]
    owner = "a" if inode in ia else "b" if inode in ib else "-"
    lp, rp = int(local.split(":")[1], 16), int(remote.split(":")[1], 16)
    if st == "0A" and owner != "-":
        listen.append(f"{owner}:{lp}")
    if st == "01" and owner != "-":
        est.append(f"{owner}:{lp}->{rp}")
print("listening=" + " ".join(sorted(listen)))
print("established=" + " ".join(sorted(est)))
# a connection between the two copies: an a-side socket (local, remote) whose mirror (remote, local) is a b-side socket
def pairs(owner):
    r = set()
    for p in est:
        if p.startswith(owner + ":"):
            loc, rem = p[2:].split("->")
            r.add((int(loc), int(rem)))
    return r
linked = any((r, l) in pairs("b") for (l, r) in pairs("a"))
print("linked_a_b=" + ("yes" if linked else "no"))
PY

import -window root "$SMOKE_SHOT" 2> "$SMOKE_LOG.shot"

if [ "$SMOKE_APP" = notepad ]; then
  res b_has_seeded_note "$([ -f "$SMOKE_DIR/b/$SMOKE_ID/data/notes/seededbysmoke.json" ] && echo yes || echo no)"
  res b_notes "$(ls "$SMOKE_DIR/b/$SMOKE_ID/data/notes" 2>/dev/null | tr '\n' ' ')"
fi

kill -TERM "$pa" "$pb" 2>/dev/null
i=0
while { alive "$pa" || alive "$pb"; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
wait "$pa" 2>/dev/null; res a_exit_code $?
wait "$pb" 2>/dev/null; res b_exit_code $?
res announcements_after "$(cd "$peers" && find . -type f | sort | tr '\n' ' ')"
res roster_after "$(ls "$SMOKE_DIR/a/roster" "$SMOKE_DIR/b/roster" 2>/dev/null | tr '\n' ' ')"
exit 0

#!/usr/bin/env python3
"""Reads what tools/linux-smoke/in-container.sh recorded under OUT and writes OUT/results.md (and prints it).

Usage: report.py OUT APP...   Standard library only. Runs in the container (ImageMagick's `identify` is used when present, to say
whether a screenshot is blank)."""
import glob
import json
import os
import re
import subprocess
import sys

out = sys.argv[1]
apps = sys.argv[2:]

# What "state persisted" means per app: the file (relative to the scratch directory) the app writes when a person uses it.
STATE = {
    "stopwatch": "dev.demo.stopwatch/state/state.json",
    "minesweeper": "dev.demo.minesweeper/data/game.json",
    "notepad": "dev.demo.notepad/data/notes/*.json",
    "notes_rust": "dev.demo.notes-rust/data/heads-*.json",
}
GTK = re.compile(r"(Gtk|Gdk|GLib|Pango|GdkPixbuf|GLib-GObject)[A-Za-z-]*-(WARNING|CRITICAL|ERROR)|\*\* \(.*\): (WARNING|CRITICAL)|-CRITICAL|-WARNING")
A11Y = re.compile(r"AT-SPI|atk_socket_embed")
EXC = re.compile(r"Unhandled Exception|EXCEPTION CAUGHT|Exception[: ]|\bError: |\[ERROR:flutter|FATAL|Segmentation|Aborted")


def kv(path):
    d = {}
    try:
        for line in open(path, errors="replace"):
            line = line.rstrip("\n")
            if "=" in line:
                k, v = line.split("=", 1)
                d[k] = v
    except OSError:
        pass
    return d


def lines_of(prefix):
    res = []
    for ext in ("out", "err"):
        try:
            res += [l.rstrip("\n") for l in open(f"{prefix}.{ext}", errors="replace") if l.strip()]
        except OSError:
            pass
    return res


def files(s):
    """'a 12;b 3;' -> {'a': 12, 'b': 3}"""
    d = {}
    for item in s.split(";"):
        item = item.strip()
        if not item:
            continue
        name, _, size = item.rpartition(" ")
        d[name] = int(size) if size.isdigit() else 0
    return d


def match(files_d, pattern):
    import fnmatch
    return {k: v for k, v in files_d.items() if fnmatch.fnmatch(k, pattern)}


def colors(png):
    if not os.path.exists(png):
        return None
    try:
        n = subprocess.run(["identify", "-format", "%k", png], capture_output=True, text=True, timeout=60).stdout.strip()
        return int(n)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def dedupe(lines, cap=12):
    seen, outl = set(), []
    for l in lines:
        if l not in seen:
            seen.add(l)
            outl.append(l)
    return outl[:cap], max(0, len(outl) - cap)


rows, details, peers_rows, peers_details = [], [], [], []
for a in apps:
    od = os.path.join(out, a)
    b = kv(f"{od}/build.kv")
    if not b:
        rows.append([a, "not run", "", "", "", "", "", ""])
        continue
    manifest = {}
    for cand in (f"/work/apps/{a}/app.json", f"/src/apps/{a}/app.json"):
        if os.path.exists(cand):
            manifest = json.load(open(cand))
            break
    appid = manifest.get("id", "")
    if b.get("build_ok") != "yes":
        tail = " ".join(open(f"{od}/build.log", errors="replace").read().splitlines()[-3:])[:160]
        rows.append([a, f"FAILED ({b.get('build_s', '0')} s; see {a}/build.log)", "-", "-", "-", "-", "-", "-"])
        details.append(f"### {a}: build failed\n\n```\n{tail}\n```\n")
        continue
    mb = int(b.get("bundle_kb", "0")) / 1024.0
    build = f"ok, {b.get('build_s')} s (+{b.get('pub_s')} s pub get), {mb:.0f} MB"
    l1, l2 = kv(f"{od}/launch-first.kv"), kv(f"{od}/launch-second.kv")
    up = f"{l1.get('running_at_up', '?')} / {l2.get('running_at_up', '?')}"
    codes = f"{l1.get('exit_code', '?')} / {l2.get('exit_code', '?')}"
    appeared = "yes" if re.search(re.escape(appid) + r"@[0-9a-f]+\.json", l1.get("roster_during", "")) else "NO"
    withdrawn = "yes" if appeared == "yes" and not l1.get("roster_after", "").strip() else ("n/a" if appeared == "NO" else "NO")
    roster = f"{appeared} / {withdrawn}"
    if l2:
        a2 = "yes" if re.search(re.escape(appid) + r"@[0-9a-f]+\.json", l2.get("roster_during", "")) else "NO"
        w2 = "yes" if a2 == "yes" and not l2.get("roster_after", "").strip() else "NO"
        roster += f" (2nd: {a2} / {w2})"
    # warnings and exceptions, both launches
    gtk, a11y, exc, other = [], [], [], []
    for n in ("first", "second"):
        for line in lines_of(f"{od}/launch-{n}"):
            if A11Y.search(line):
                a11y.append(line)
            elif GTK.search(line):
                gtk.append(line)
            elif EXC.search(line):
                exc.append(line)
            else:
                other.append(line)
    warn = f"Gtk/GLib {len(gtk) + len(a11y)} ({len(a11y)} of them the missing accessibility bus), exceptions {len(exc)}"
    # state
    pattern = STATE.get(a)
    if pattern:
        f1d, f1a, f2d = files(l1.get("files_during", "")), files(l1.get("files_after", "")), files(l2.get("files_during", ""))
        m1, m1a, m2 = match(f1d, pattern), match(f1a, pattern), match(f2d, pattern)
        state = (f"created in 1st: {'yes' if m1 or m1a else 'NO'} ({', '.join(f'{os.path.basename(k)} {v} B' for k, v in (m1a or m1).items()) or '-'}); "
                 f"present in 2nd: {'yes' if m2 else 'NO'}")
    else:
        state = "n/a (no data file expected)"
    shot = f"{a}-first.png ({colors(os.path.join(out, a + '-first.png'))} colours), {a}-second.png ({colors(os.path.join(out, a + '-second.png'))} colours)"
    rows.append([a, build, up, codes, roster, warn, state, shot])
    # details
    d = [f"### {a}", ""]
    d.append(f"* manifest id `{appid}`; window appeared after {l1.get('window_s', '?')} s (1st) / {l2.get('window_s', '?')} s (2nd); {l1.get('window', '')}")
    if l1.get("drive"):
        d.append(f"* driven with xdotool in the first launch: `{l1['drive']}`")
    d.append(f"* SIGTERM to exit: {l1.get('term_to_exit_s', '?')} s (1st), {l2.get('term_to_exit_s', '?')} s (2nd); hung after SIGTERM: {l1.get('hung_after_sigterm', 'no')} / {l2.get('hung_after_sigterm', 'no')}")
    d.append(f"* roster while running (1st): `{l1.get('roster_during', '').strip() or '-'}`; after exit: `{l1.get('roster_after', '').strip() or '-'}`")
    d.append(f"* files under the scratch directory after the 1st launch: `{l1.get('files_after', '').strip() or '-'}`")
    d.append(f"* files after the 2nd launch: `{l2.get('files_after', '').strip() or '-'}`")
    d.append(f"* bundle: {b.get('libs', '').strip()}; executable {int(b.get('binary_kb', '0')) / 1024.0:.1f} MB")
    for title, ls in (("Gtk/GLib/Pango warnings: the accessibility bus (AT-SPI/ATK) is absent in the container", a11y), ("other Gtk/GLib/Pango warnings", gtk), ("exceptions and errors", exc), ("other output on stdout or stderr", other)):
        shown, more = dedupe(ls)
        if shown:
            d.append(f"* {title} ({len(ls)} lines, {len(set(ls))} distinct):")
            d.append("")
            d.append("  ```")
            d += ["  " + s[:240] for s in shown]
            if more:
                d.append(f"  ... and {more} more distinct lines")
            d.append("  ```")
    d.append("")
    details.append("\n".join(d))

    p = kv(f"{od}/peers.kv")
    if p:
        ann = p.get("announcements", "").split()
        linked = p.get("linked_a_b", "?")
        seed = p.get("b_has_seeded_note", "")
        peers_rows.append([
            a,
            f"{p.get('a_running', '?')} / {p.get('b_running', '?')}",
            f"{len(ann)} file(s) in the shared peers directory",
            f"{linked} ({p.get('established', '').strip() or 'no connection'})",
            (f"seeded note in A reached B: {seed}" if seed else "n/a"),
            f"{p.get('a_exit_code', '?')} / {p.get('b_exit_code', '?')}",
            "yes" if not p.get("announcements_after", "").strip() else "NO: " + p.get("announcements_after", "").strip(),
            f"{a}-peers.png ({colors(os.path.join(out, a + '-peers.png'))} colours)",
        ])
        pd = [f"### {a}: two copies", "", f"* announcement files: `{p.get('announcements', '').strip()}`",
              f"* listening sockets (owner:port): `{p.get('listening', '').strip()}`; established (owner:local->remote): `{p.get('established', '').strip()}`",
              f"* windows: {p.get('windows', '')}; roster entries left after exit: `{p.get('roster_after', '').strip() or '-'}`"]
        if p.get("b_notes") is not None and seed:
            pd.append(f"* copy B's notes folder after {9} s: `{p.get('b_notes', '').strip() or '-'}`")
        errl = []
        for c in ("a", "b"):
            errl += lines_of(f"{od}/peers-{c}")
        shown, more = dedupe(errl)
        if shown:
            pd += ["* output of the two copies:", "", "  ```"] + ["  " + s[:240] for s in shown] + ["  ```"]
        pd.append("")
        peers_details.append("\n".join(pd))


def table(head, body):
    if not body:
        return "(none)\n"
    s = "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
    for r in body:
        s += "| " + " | ".join(c.replace("|", "\\|") for c in r) + " |\n"
    return s


pins = ""
try:
    pins = open(os.path.join(out, "image-pins.txt")).read().strip()
except OSError:
    pass

notes_md = []
try:
    nl = [l.strip() for l in open(os.path.join(out, "notes.txt"), errors="replace") if l.strip()]
    if nl:
        notes_md = ["## Notes from the harness", ""] + [f"* {l}" for l in nl] + [""]
except OSError:
    pass
md = ["# Linux smoke test", "",
      "Headless: every app was built with `flutter build linux --release` and launched under Xvfb (1280x800x24) in a linux container, with "
      "`APP_CONTEXT_SCRATCH` set, `APP_CONTEXT_MODE=mock` and the app's own `<PREFIX>_MODE=mock`. It is **not** a real desktop session "
      "(no window manager, no compositor) and **not** a real GPU (software OpenGL).", "",
      "## Results", "",
      table(["App", "Build (release)", "Up at 10 s (1st / 2nd launch)", "Exit code after SIGTERM", "Roster appeared / withdrawn",
             "Warnings", "State persisted", "Screenshots"], rows),
      "## Two copies on one machine (real mode, shared `APP_CONTEXT_PEERS_DIR`, devices `smoke-a` and `smoke-b`)", "",
      table(["App", "A / B running", "Announcements", "TCP link between the two processes", "Data synced", "Exit codes A / B",
             "Announcements withdrawn", "Screenshot"], peers_rows),
      "## Environment", "", "```", pins, "```", ""] + notes_md + ["## Details", ""] + details + peers_details
text = "\n".join(md) + "\n"
open(os.path.join(out, "results.md"), "w").write(text)
print(text)
# non-zero when an app did not build, was not up at the end of its time, or did not exit
bad = [r[0] for r in rows if r[1].startswith(("FAILED", "not run")) or r[2].split(" / ")[0] != "yes"]
sys.exit(1 if bad else 0)

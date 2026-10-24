#!/bin/sh
# Public-safety scan over the whole tree (not .kits, not build output). Run it before every push.
# Prints file:line for every hit and exits non-zero if there is any.
#
# What it looks for:
#   internal hostnames, ticket ids, local absolute paths with a user name, notes-vault paths,
#   references to agent instruction files, studio repository URLs that are not public Kits in kits.lock,
#   people named in credits or licence text other than the author, and secret patterns.
#
# This file is excluded from its own scan because it has to spell the patterns out.
set -u
. "$(dirname "$0")/common.sh"
cd "$ROOT"

HITS=$(mktemp)
FILES=$(mktemp)
trap 'rm -f "$HITS" "$FILES"' EXIT INT TERM

# The files to scan: everything on disk that is not fetched, built or generated (a Flutter app with plugins gets a git-ignored
# .flutter-plugins-dependencies that holds absolute paths of the machine it was made on).
find . \( -name .git -o -name .kits -o -name build -o -name .dart_tool -o -name target -o -name Pods \
          -o -name ephemeral -o -name node_modules -o -name .idea -o -name .vscode \) -prune -o -type f -print |
  sed 's#^\./##' | grep -v -e '^tools/check-public\.sh$' -e '\.DS_Store$' -e '/\.flutter-plugins-dependencies$' > "$FILES"

# scan LABEL EXTENDED-REGEX [-i]   (binary files are skipped by grep -I)
scan() {
  label=$1; re=$2; flag=${3:--e}
  [ "$flag" = -i ] && opts="-nIiE" || opts="-nIE"
  tr '\n' '\0' < "$FILES" | xargs -0 grep $opts -- "$re" 2>/dev/null |
    sed "s#^\\([^:]*\\):\\([0-9]*\\):#\\1:\\2: [$label] #" >> "$HITS"
}

scan "internal hostname"   '(softsurve|jenkins|nexus)' -i
scan "ticket id"           '(^|[^A-Za-z])(CLUS|LS|QR|SOF)-[0-9]+'
scan "local path"          '/(Users|home)/[A-Za-z0-9._-]+'
scan "vault path"          '(^|[^A-Za-z])vault/|dlockamy|\.obsidian|wiki/(ideas|projects|meta|sources)|\.raw/'
scan "agent file"          '(AGENTS?|CLAUDE)\.md'
scan "secret"              'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-[A-Za-z0-9-]{10,}'

# Studio repository URLs: only public Kits listed in kits.lock may be linked. kits.lock itself is the list, so it is
# not scanned for this rule (its private lines are reported separately below).
PUBLIC=$(lock_lines | awk '$4=="public" {print $2}' | sed -e 's#^https://github\.com/##' -e 's#\.git$##')
grep -v '^kits\.lock$' "$FILES" | tr '\n' '\0' |
  xargs -0 grep -nIoE 'github\.com[/:](slash-builder|lockamy-studios|lockamystudios|softsurve)/[A-Za-z0-9._-]+' 2>/dev/null |
  while IFS= read -r line; do
    slug=$(printf '%s' "$line" | sed -e 's#^.*github\.com[/:]##' -e 's#\.git$##')
    ok=0
    for p in $PUBLIC; do [ "$p" = "$slug" ] && ok=1; done
    [ "$ok" = 1 ] || printf '%s\n' "$line" | sed 's#^\([^:]*\):\([0-9]*\):\(.*\)$#\1:\2: [studio repository that is not a public Kit in kits.lock] \3#' >> "$HITS"
  done

# People named in credit or licence text. In Markdown files, lines under a Credits/Authors/Licence heading and lines
# that start "By " or "Author"; in LICENSE files, lines starting "Copyright". Only the author may be named.
for f in $(grep -E '(\.md$|^LICENSE)' "$FILES"); do
  awk -v F="$f" '
    function strip(s) {
      gsub(/Douglas Lockamy/, "", s); gsub(/Slash[ ]?Builder/, "", s); gsub(/Lockamy Studios/, "", s)
      gsub(/Apache License/, "", s); gsub(/Creative Commons/, "", s); gsub(/Attribution [0-9]/, "", s)
      # ordinary capitalised words that start sentences or name things in licence text are not people
      gsub(/(^|[^A-Za-z])(The|This|That|These|Kits?|Code|Documentation|Licen[cs]e[sd]?|Apache|Application|Venue|Attribution|Full|Human|Summary|Under|Your|You|Share|Adapt|Public|Domain|Hearth|Message|Storage|Identity|Interface|Fabric)([^A-Za-z]|$)/, " ", s)
      return s
    }
    function nameish(s) { s = strip(s); return match(s, /[A-Z][a-z]+ [A-Z][a-z]+/) }
    /^#+ / { in_credit = ($0 ~ /[Cc]redit|[Aa]uthor|[Ll]icen[cs]e|[Aa]cknowledg|[Mm]aintainer|[Cc]ontributor/) ; next }
    F ~ /^LICENSE/ { if ($0 ~ /^[[:space:]]*Copyright/ && $0 !~ /\[/ && nameish($0)) print F ":" NR ": [person named in licence] " $0; next }
    in_credit && nameish($0) { print F ":" NR ": [person named in credits] " $0; next }
    /^(By|Author|Authors|Written by|Credits?|Thanks to)[: ]/ && nameish($0) { print F ":" NR ": [person named in credits] " $0 }
  ' "$f" >> "$HITS"
done

sort -u "$HITS" -o "$HITS"
if [ -s "$HITS" ]; then
  cat "$HITS"
  n=$(wc -l < "$HITS" | tr -d ' ')
  warn ""
  warn "check-public: $n hit(s). Fix them; do not weaken the scan."
  exit 1
fi

say "check-public: no hits in $(wc -l < "$FILES" | tr -d ' ') files."
priv=$(lock_lines | awk '$4=="private" {print $1}' | tr '\n' ' ')
if [ -n "$priv" ]; then
  say "note: kits.lock lists private Kit(s): $priv"
  say "      They are only fetched with KITS=all. Each must be made public, or no longer needed, before this repository is made public."
  if [ "${CHECK_PUBLIC_STRICT:-0}" = 1 ]; then warn "CHECK_PUBLIC_STRICT=1: failing because of private Kits in kits.lock"; exit 1; fi
fi
exit 0

#!/bin/sh
# Show how the pins in kits.lock would move to each Kit's newest commit, and rewrite kits.lock only after
# you have seen the difference and said yes.
#
#   tools/lock.sh                  every Kit
#   tools/lock.sh app-context-kit  one Kit
#   LOCK_YES=1 tools/lock.sh       do not ask (for scripts; the difference is still printed)
#
# The newest commit is the tip of the Kit's default branch, read from the GitHub API (through gh when it is
# logged in, which also works for private Kits; otherwise curl, with GITHUB_TOKEN if set).
# After it rewrites kits.lock, run: make setup, make test-fast, and commit kits.lock if everything is green.
set -eu
. "$(dirname "$0")/common.sh"

ONLY=${1:-}
have curl || have gh || die "curl or gh is needed to ask GitHub for the newest commit"

# newest SLUG -> prints the commit id, or nothing on failure
newest() {
  slug=$1
  if gh_ready; then
    gh api -H "Accept: application/vnd.github.sha" "repos/$slug/commits/HEAD" 2>/dev/null || true
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$slug/commits/HEAD" 2>/dev/null || true
  else
    curl -fsSL -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$slug/commits/HEAD" 2>/dev/null || true
  fi
}

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT INT TERM
CHANGED=0
MATCHED=0

say "Pins in $(basename "$KITS_LOCK") compared with the newest commit of each Kit:"
say ""
lock_lines | while read -r name url commit vis role _rest; do
  if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then continue; fi
  slug=$(repo_slug "$url")
  tip=$(newest "$slug")
  case "$tip" in
    [0-9a-f]*) [ "${#tip}" -eq 40 ] || tip="" ;;
    *) tip="" ;;
  esac
  if [ -z "$tip" ]; then
    printf '  %-18s could not read the newest commit (%s Kit; %s)\n' "$name" "$vis" "$(gh_ready && echo 'gh is logged in; check the repository name' || echo 'for a private Kit run gh auth login or set GITHUB_TOKEN')"
    continue
  fi
  if [ "$tip" = "$commit" ]; then
    printf '  %-18s unchanged at %s\n' "$name" "$(printf '%s' "$commit" | cut -c1-7)"
  else
    printf '  %-18s %s -> %s\n' "$name" "$(printf '%s' "$commit" | cut -c1-7)" "$(printf '%s' "$tip" | cut -c1-7)"
    printf '  %-18s see what changed: https://github.com/%s/compare/%s...%s\n' "" "$slug" "$(printf '%s' "$commit" | cut -c1-7)" "$(printf '%s' "$tip" | cut -c1-7)"
    printf '%s %s\n' "$name" "$tip" >> "$NEW"
  fi
done

if [ -n "$ONLY" ] && ! lock_lines | awk -v n="$ONLY" '$1==n {f=1} END {exit !f}'; then
  die "no Kit called '$ONLY' in kits.lock"
fi

if [ ! -s "$NEW" ]; then
  say ""
  say "Nothing to change."
  exit 0
fi

say ""
if [ "${LOCK_YES:-0}" != 1 ]; then
  ask_yn "Rewrite kits.lock with these new pins?" || { say "kits.lock left as it was."; exit 0; }
fi

# Rewrite only the commit field, and keep every comment and blank line.
awk -v newfile="$NEW" '
  BEGIN { while ((getline line < newfile) > 0) { split(line, p, " "); tip[p[1]] = p[2] } }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
  ($1 in tip) { $3 = tip[$1] }
  { print $1, $2, $3, $4, $5 }
' "$KITS_LOCK" > "$KITS_LOCK.new"
mv "$KITS_LOCK.new" "$KITS_LOCK"
say "kits.lock updated. Now run: make setup   then: make test-fast   and commit kits.lock if both are green."

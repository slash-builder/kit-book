#!/bin/sh
# Download each Kit listed in kits.lock, at its pinned commit, into .kits/<name>/.
#
#   tools/fetch-kits.sh                 public Kits only (the default)
#   KITS=all tools/fetch-kits.sh        public and private Kits (needs a GitHub login, see below)
#   KITS_LOCK=other.lock ...            read a different lock file (used for testing)
#
# No git and no submodules: each Kit is one tarball. Public Kits come from a plain curl download.
# Private Kits need `gh` (logged in with `gh auth login`) or a GITHUB_TOKEN environment variable.
# Prints one line per Kit: fetched, up to date, or skipped (with the reason).
# Exits non-zero only when a Kit it tried to fetch could not be fetched.
set -eu
. "$(dirname "$0")/common.sh"

WHICH="${KITS:-public}"
case "$WHICH" in public|all) ;; *) die "KITS must be 'public' or 'all' (got '$WHICH')" ;; esac
have curl || die "curl is needed to download Kits"
have tar || die "tar is needed to unpack Kits"

mkdir -p "$KITS_DIR"
TMP=$(mktemp -d "$KITS_DIR/.tmp.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

FAILED=0
report() { printf '  %-18s %s\n' "$1" "$2"; }

# download_private SLUG COMMIT OUTFILE: succeed with the tarball in OUTFILE, else print a reason to stdout and fail.
download_private() {
  slug=$1; commit=$2; out=$3
  if gh_ready; then
    gh api "repos/$slug/tarball/$commit" > "$out" 2>"$TMP/err" && return 0
    echo "gh could not download it: $(tr '\n' ' ' < "$TMP/err" | cut -c1-120)"
    return 1
  fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      -o "$out" "https://api.github.com/repos/$slug/tarball/$commit" 2>"$TMP/err" && return 0
    echo "GITHUB_TOKEN was rejected or has no access: $(tr '\n' ' ' < "$TMP/err" | cut -c1-120)"
    return 1
  fi
  echo "no GitHub login: install gh and run 'gh auth login', or set GITHUB_TOKEN"
  return 2
}

say "Kits (KITS=$WHICH):"
lock_lines | while read -r name url commit vis role _rest; do
  slug=$(repo_slug "$url")
  dest="$KITS_DIR/$name"
  short=$(printf '%s' "$commit" | cut -c1-7)

  case "$commit" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) report "$name" "FAILED: commit '$commit' in kits.lock is not a commit id"; echo x >> "$TMP/failed"; continue ;;
  esac
  [ "${#commit}" -eq 40 ] || { report "$name" "FAILED: kits.lock needs the full 40-character commit id"; echo x >> "$TMP/failed"; continue; }

  if [ "$vis" = private ] && [ "$WHICH" != all ]; then
    if [ -f "$dest/.fetched" ]; then report "$name" "kept (private Kit, fetched earlier at $(cut -c1-7 "$dest/.fetched"); not refreshed without KITS=all)"
    else report "$name" "skipped (private Kit; run: make setup KITS=all)"; fi
    continue
  fi
  if [ -f "$dest/.fetched" ] && [ "$(cat "$dest/.fetched")" = "$commit" ]; then
    report "$name" "up to date ($short)"
    continue
  fi

  tarball="$TMP/$name.tar.gz"
  rm -f "$tarball"
  if [ "$vis" = private ]; then
    reason=$(download_private "$slug" "$commit" "$tarball") && ok=1 || ok=0
    if [ "$ok" = 0 ]; then
      case "$reason" in
        "no GitHub login"*) report "$name" "skipped ($reason)" ;;
        *) report "$name" "FAILED: $reason"; echo x >> "$TMP/failed" ;;
      esac
      continue
    fi
  else
    if ! curl -fsSL -o "$tarball" "https://github.com/$slug/archive/$commit.tar.gz" 2>"$TMP/err"; then
      report "$name" "FAILED: download from github.com/$slug failed ($(tr '\n' ' ' < "$TMP/err" | cut -c1-100))"
      echo x >> "$TMP/failed"; continue
    fi
  fi

  # Verify we got the commit we asked for: GitHub names the top folder <repo>-<commit> (public)
  # or <org>-<repo>-<7-char commit> (API); either way it ends with the commit id (or its first 7 characters).
  top=$(tar -tzf "$tarball" 2>/dev/null | head -n 1 | cut -d/ -f1)
  case "$top" in
    *"$commit"|*"-$short") ;;
    *) report "$name" "FAILED: the download is not commit $short (top folder: '$top')"; echo x >> "$TMP/failed"; continue ;;
  esac

  stage="$TMP/stage-$name"
  rm -rf "$stage"; mkdir -p "$stage"
  if ! tar -xzf "$tarball" -C "$stage" --strip-components=1 2>"$TMP/err"; then
    report "$name" "FAILED: could not unpack ($(tr '\n' ' ' < "$TMP/err" | cut -c1-100))"
    echo x >> "$TMP/failed"; continue
  fi
  printf '%s\n' "$commit" > "$stage/.fetched"
  rm -rf "$dest"
  mv "$stage" "$dest"
  report "$name" "fetched ($short, $vis, $role)"
done

if [ -f "$TMP/failed" ]; then
  warn "Some Kits could not be fetched."
  exit 1
fi

#!/bin/sh
# Commit the built website (build/site-publish/, made by tools/site.sh) to the gh-pages branch as ONE orphan commit,
# and push it only when it is allowed to be pushed.
#
#   Always:            build the commit on the local branch gh-pages and print what would be pushed (a dry run, exit 0).
#   Pushes only when:  PUBLISH=1, and the repository behind the remote "origin" is public (asked with gh repo view),
#                      and the working tree is clean and on the branch the site's links point to (SITE_REPO_BRANCH).
#                      The push is a force push guarded by --force-with-lease, because every publish is a new root commit.
#
# The commit is made without checking anything out: a scratch index, with the staging folder as the work tree, builds the
# tree object, so main, the real index and the working tree are never touched. The scratch index lives in a temporary
# folder that is deleted on exit. Nothing here changes a GitHub setting or any DNS record.
set -eu
. "$(dirname "$0")/common.sh"
. "$TOOLS_DIR/site-env.sh"
cd "$ROOT"

PUB="$ROOT/build/site-publish"
BRANCH=gh-pages
REF=refs/heads/$BRANCH

[ -f "$PUB/index.html" ] || die "no built site in build/site-publish/. Run make publish-site (it builds first), or make site."
[ -f "$PUB/CNAME" ] && [ "$(cat "$PUB/CNAME")" = "$SITE_DOMAIN" ] || die "build/site-publish/CNAME is missing or is not exactly $SITE_DOMAIN. Run make site again."
[ -f "$PUB/.nojekyll" ] || die "build/site-publish/.nojekyll is missing. Run make site again."
[ -f "$PUB/THIRD-PARTY-NOTICES.md" ] || die "build/site-publish/THIRD-PARTY-NOTICES.md is missing (the vendored diagram script's licences ask for it to be published with it). Run make site again."
cmp -s "$PUB/THIRD-PARTY-NOTICES.md" "$ROOT/THIRD-PARTY-NOTICES.md" || die "build/site-publish/THIRD-PARTY-NOTICES.md differs from the one at the repository root. Run make site again."
have git || die "git is required"

GIT_DIR_ABS=$(git rev-parse --absolute-git-dir)
SRC_COMMIT=$(git rev-parse --short HEAD)
SRC_BRANCH=$(git rev-parse --abbrev-ref HEAD)
DIRTY=
[ -z "$(git status --porcelain)" ] || DIRTY=1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# 1. One orphan commit holding exactly the staging folder.
TREE=$(cd "$PUB" && GIT_DIR="$GIT_DIR_ABS" GIT_WORK_TREE="$PUB" GIT_INDEX_FILE="$TMP/index" \
  sh -c 'git add -A -f . && git write-tree')
MSG="Publish the site built from $SRC_COMMIT on $SRC_BRANCH${DIRTY:+ (with uncommitted changes)}"
if [ -z "$(git config user.name || true)" ] || [ -z "$(git config user.email || true)" ]; then
  export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-kit-book publish}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-noreply@invalid}"
  export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-kit-book publish}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-noreply@invalid}"
fi
COMMIT=$(git commit-tree "$TREE" -m "$MSG")
git update-ref "$REF" "$COMMIT"
FILES=$(git ls-tree -r --name-only "$COMMIT" | wc -l | tr -d ' ')
BYTES=$(git ls-tree -r -l "$COMMIT" | awk '{s += $4} END {print s + 0}')
say "Committed the site to the local branch $BRANCH: $(git rev-parse --short "$COMMIT") (orphan, no parent), $FILES files, $BYTES bytes."
say "  message:  $MSG"
say "  CNAME:    $(git show "$COMMIT:CNAME")"
say "  .nojekyll: $(git cat-file -s "$COMMIT:.nojekyll") bytes"
say "  top level: $(git ls-tree --name-only "$COMMIT" | tr '\n' ' ')"
[ "$SITE_INDEXABLE" = 1 ] || say "  robots:   every page says noindex (SITE_INDEXABLE=0); set SITE_INDEXABLE=1 at publish time to let search engines index the site."

# 2. Is the push allowed?
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
VIS=unknown
WHY=
case "$ORIGIN_URL" in
  *github.com*)
    if have gh; then
      VIS=$(gh repo view "$(repo_slug "$ORIGIN_URL")" --json visibility -q .visibility 2>/dev/null || true)
      [ -n "$VIS" ] || VIS=unknown
    fi ;;
esac
if [ "$PUBLISH" != 1 ]; then WHY="PUBLISH=1 was not given"
elif [ -z "$ORIGIN_URL" ]; then WHY="there is no remote named origin"
elif [ "$VIS" != PUBLIC ]; then WHY="the repository behind origin is not known to be public (visibility: $VIS)"
elif [ -n "$DIRTY" ]; then WHY="the working tree has uncommitted changes; commit them so the published site matches a commit"
elif [ "$SRC_BRANCH" != "$SITE_REPO_BRANCH" ]; then WHY="the current branch is $SRC_BRANCH, but the site's links point at $SITE_REPO_BRANCH"
fi

if [ -n "$WHY" ]; then
  say ""
  say "DRY RUN: nothing was pushed ($WHY)."
  say "Repository visibility: $VIS."
  say "With PUBLISH=1 on a public repository this would have run:"
  say "  git push --force-with-lease=$REF:<what origin has now> origin $BRANCH:$REF"
  say "to replace the gh-pages branch of $(repo_slug "${ORIGIN_URL:-origin}") with that one commit, which would then be served at https://$SITE_DOMAIN/ once Pages is on."
  say "Undo the local branch with: git branch -D $BRANCH"
  exit 0
fi

# 3. Push, guarded by a lease on whatever origin holds right now (empty: the branch must not exist yet).
EXPECT=$(git ls-remote origin "$REF" | awk '{print $1}')
say ""
say "Pushing $BRANCH to origin (force, with a lease on ${EXPECT:-'no existing branch'}) ..."
git push --force-with-lease="$REF:$EXPECT" origin "$BRANCH:$REF"
say "Pushed. Pages serves it when it is switched on for the gh-pages branch; see book/90-reference/publishing.md."

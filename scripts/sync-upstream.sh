#!/usr/bin/env bash
# sync-upstream.sh — bring upstream Dray into Wain, already renamed (FORK-PLAN.md §1).
#
#   scripts/sync-upstream.sh
#
# 1. Fetches upstream/main.
# 2. Stops if upstream's LICENSE changed since the last sync: code already here
#    stays Apache-2.0, but a relicense needs a human decision before taking more.
# 3. Renames a temporary checkout of it with scripts/rebrand.mjs and commits that
#    tree onto upstream-renamed. Parents: the previous sync and the upstream tip,
#    so the merge base for wain is always the last sync, and git log still shows
#    which upstream commit each sync came from (trailer "Upstream:").
# 4. Merges upstream-renamed into the current branch when that is main and clean;
#    otherwise prints the command.
#
# Env: UPSTREAM_REMOTE (upstream), UPSTREAM_BRANCH (main), WAIN_BRANCH (main).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
REMOTE="${UPSTREAM_REMOTE:-upstream}"
BRANCH="${UPSTREAM_BRANCH:-main}"
WAIN_BRANCH="${WAIN_BRANCH:-main}"
TARGET="refs/heads/upstream-renamed"

git fetch -q "$REMOTE" "$BRANCH"
U=$(git rev-parse "$REMOTE/$BRANCH")
PREV=$(git rev-parse -q --verify "$TARGET" || true)

if [[ -n "$PREV" ]]; then
  LAST=$(git log -1 --format='%(trailers:key=Upstream,valueonly)' "$PREV" | tr -d '[:space:]')
  if [[ "$LAST" == "$U" ]]; then
    echo "upstream-renamed is already at upstream ${U:0:12}"
    exit 0
  fi
  if ! git diff --quiet "$LAST" "$U" -- LICENSE; then
    echo "STOP: upstream changed LICENSE between ${LAST:0:12} and ${U:0:12}. Read it before syncing:"
    echo "  git diff $LAST $U -- LICENSE"
    exit 1
  fi
fi

TMP="$(mktemp -d)/tree"
git worktree add -q --detach "$TMP" "$U"
trap 'git worktree remove --force "$TMP"' EXIT

# Exits non-zero on a warning (a leftover casing, a brand word inside data), which
# stops the sync for a look rather than committing a half-renamed tree.
node scripts/rebrand.mjs "$TMP"
git -C "$TMP" add -A
TREE=$(git -C "$TMP" write-tree)

if [[ -n "$PREV" ]]; then
  C=$(git commit-tree "$TREE" -p "$PREV" -p "$U" \
    -m "Sync upstream ${U:0:12}, renamed to Wain" -m "Upstream: $U")
else
  C=$(git commit-tree "$TREE" -p "$U" \
    -m "Rename upstream Dray ${U:0:12} to Wain" -m "Upstream: $U")
fi
git update-ref "$TARGET" "$C" ${PREV:+"$PREV"}
echo "upstream-renamed → ${C:0:12} (upstream ${U:0:12})"

CURRENT=$(git symbolic-ref --short -q HEAD || true)
if [[ "$CURRENT" == "$WAIN_BRANCH" ]] && git diff --quiet && git diff --cached --quiet; then
  git merge --no-edit upstream-renamed
else
  echo "next: git switch $WAIN_BRANCH && git merge upstream-renamed"
fi

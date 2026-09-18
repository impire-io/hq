#!/usr/bin/env bash
#
# 05-TOOLS/session-workspace-notice.sh — say, at the start of a session, where it is.
#
# A session opens with its working directory in the shared clone, where reading
# is legitimate and constant. Nothing marks the moment work starts, so work
# starts there. This states the boundary before the first edit rather than after
# it: 05-TOOLS/guard-readonly-clone.py refuses the write, but a refusal is a wasted turn
# and this is the cheaper half.
#
# Wired as a SessionStart hook (`.claude/settings.json`); its stdout becomes
# context for the session. It only ever prints — it changes nothing, and it says
# nothing at all when the session is already in a workspace and correct.
#
# Usage:  ./05-TOOLS/session-workspace-notice.sh [--here <dir>]

set -euo pipefail

HERE="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "${1:-}" = "--here" ] && HERE="${2:?--here needs a directory}"

COMMON_GIT="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[ -n "$COMMON_GIT" ] || exit 0
ROOT="$(cd "$(dirname "$COMMON_GIT")/.." && pwd)"
HERE="$(cd "$HERE" && pwd)"

# In a workspace already: say which one, and leave it there.
case "$HERE" in
  "$ROOT"/.work/*)
    rest="${HERE#"$ROOT"/.work/}"
    echo "Workspace: ${rest%%/*} (under .work/). Commit and push every checkpoint; the draft MR is the claim."
    exit 0
    ;;
esac

# The hq repo is the one this script lives in — derive its name from the
# clone directory that holds it, which is right in clones and worktrees alike.
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
HQ_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HQ_COMMON="$(git -C "$HQ_SELF" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
HQ_REPO="${HQ_REPO:-$(basename "$(dirname "${HQ_COMMON:-$HQ_SELF/..}")")}"

echo "This is the shared $(basename "$HERE") clone at $ROOT — read-only."
echo "Reading it is what it is for. Editing, committing, branching and pushing here are refused."
echo
echo "To start or join work, open a workspace first — one worktree per repo, $HQ_REPO always included:"
echo "    $ROOT/$HQ_REPO/05-TOOLS/open-workspace.sh <work-id> [repo...]"
echo "then work in $ROOT/.work/<work-id>/<repo>/. Run it again later to add a repo."

# What is already in flight on this machine. Not a substitute for the
# group-wide `glab mr list --group <group>` query, which sees the fleet;
# this only sees the disk, and is here because it costs nothing.
if [ -d "$ROOT/.work" ]; then
  items=()
  for path in "$ROOT"/.work/*/; do
    [ -d "$path" ] || continue
    id="$(basename "$path")"
    # An empty item directory is a workspace that was half torn down; say so
    # rather than printing the unmatched glob.
    repos=""
    for repo in "$path"*/; do
      [ -d "$repo" ] || continue
      repo="${repo%/}"
      repos="$repos $(basename "$repo")"
    done
    items+=("  $id —${repos:- no worktrees}")
  done
  if [ ${#items[@]} -gt 0 ]; then
    echo
    echo "In flight on this machine (${#items[@]}), other people's work included:"
    printf '%s\n' "${items[@]}"
  fi
fi

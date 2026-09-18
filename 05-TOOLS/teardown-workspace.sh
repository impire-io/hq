#!/usr/bin/env bash
#
# 05-TOOLS/teardown-workspace.sh — remove one work item's workspace, and nothing else.
#
# Playbook 07 step 8, as a command instead of a set of steps to retype. It takes
# a work id, refuses anything that is not exactly one, removes that item's
# worktrees, deletes the local branch, and removes only `.work/<work-id>/`.
#
# It exists because the alternative is people composing `rm -rf` by hand next to
# other agents' worktrees, which is how an unrelated work item got destroyed.
#
# Usage:
#   ./05-TOOLS/teardown-workspace.sh <work-id> [--delete-remote] [--dry-run]
#
#   --delete-remote  also delete the branch on origin. Off by default: the
#                    branch may be someone's only copy of an unmerged idea, and
#                    GitLab often deletes it on merge anyway.
#   --dry-run        print what would happen, touch nothing.

set -euo pipefail

WORK_ID=""
DELETE_REMOTE=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --delete-remote) DELETE_REMOTE=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    -*)              echo "unknown option: $arg" >&2; exit 2 ;;
    *)
      if [ -n "$WORK_ID" ]; then
        echo "give exactly one work id (got '$WORK_ID' and '$arg')" >&2
        exit 2
      fi
      WORK_ID="$arg"
      ;;
  esac
done

if [ -z "$WORK_ID" ]; then
  echo "usage: $0 <work-id> [--delete-remote] [--dry-run]" >&2
  exit 2
fi

# The whole point of this script is that the target cannot widen. A work id is
# one path segment: no separator, no glob, no traversal, no leading dash.
case "$WORK_ID" in
  */*|*'*'*|*'?'*|*'['*|.|..|.work|-*|"")
    echo "refusing '$WORK_ID': a work id is a single path segment, no globs or traversal" >&2
    exit 2
    ;;
esac

# The directory holding the clones. Derived from git rather than from this
# script's own path, because the script is often run from inside a worktree
# (`.work/<id>/<hq-repo>`), where walking up one level lands in the workspace
# instead of the fleet root. --git-common-dir points at the main clone's .git
# from any worktree of it — and the clone's directory name is the hq repo's.
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_GIT="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$COMMON_GIT" ]; then
  echo "cannot locate the hq clone from $HERE" >&2
  exit 2
fi
HQ_REPO="${HQ_REPO:-$(basename "$(dirname "$COMMON_GIT")")}"
ROOT="$(cd "$(dirname "$COMMON_GIT")/.." && pwd)"
TARGET="$ROOT/.work/$WORK_ID"

if [ ! -d "$TARGET" ]; then
  echo "nothing to do: $TARGET does not exist" >&2
  exit 0
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would run: $*"
  else
    "$@"
  fi
}

echo "tearing down $TARGET"

# Each subdirectory is a worktree named after the repo it came from.
for path in "$TARGET"/*/; do
  [ -d "$path" ] || continue
  repo="$(basename "$path")"
  clone="$ROOT/$repo"
  if [ ! -d "$clone/.git" ]; then
    echo "  ! $repo has no clone at $clone, leaving $path alone" >&2
    continue
  fi
  echo "  $repo"
  run git -C "$clone" worktree remove --force "${path%/}" || \
    echo "    ! worktree remove failed, continuing" >&2
  if git -C "$clone" show-ref --verify --quiet "refs/heads/$WORK_ID"; then
    run git -C "$clone" branch -D "$WORK_ID" >/dev/null 2>&1 || true
  fi
  if [ "$DELETE_REMOTE" -eq 1 ]; then
    run git -C "$clone" push origin --delete "$WORK_ID" || \
      echo "    ! remote branch delete failed (already gone?), continuing" >&2
  fi
done

# Only ever this one directory. Never its parent.
run rm -rf "$TARGET"
run git -C "$ROOT/$HQ_REPO" worktree prune

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run: nothing was changed"
else
  echo "done: $TARGET removed"
fi

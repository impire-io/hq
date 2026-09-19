#!/usr/bin/env bash
#
# 05-TOOLS/open-workspace.sh — open one work item's workspace, or add a repo to it.
#
# Playbook 07 step 2, as a command instead of a set of steps to retype. It takes
# a work id and the repos the work touches, and creates one worktree per repo
# under `.work/<work-id>/`, all on a branch named exactly for the work id.
#
# The hq repo is always included, named or not: it holds the work item, the
# `lands:` block, and the edit that closes the record. Work whose last act is a
# code merge closes nothing here, and no one comes back for it.
#
# It is idempotent. A repo already open is reported and left alone, so **adding a
# repo mid-work is this same command run again** with the new repo named.
#
# It exists because every part of step 2 that people had to retype has drifted in
# practice: a workspace ended up inside a clone rather than beside it, another
# with no `.work/` segment at all, and one holding a branch whose name was not
# its work id. The path is derived here and the branch name cannot diverge from
# the directory.
#
# Usage:
#   ./05-TOOLS/open-workspace.sh <work-id> [repo...] [--dry-run]
#
#   repo...    the code repos this work touches, by directory name.
#              The hq repo is added for you.
#   --dry-run  print what would happen, touch nothing.
#
# Where the branch already exists on origin, the worktree is created from it —
# joining work someone else has already claimed rather than forking it.

set -euo pipefail

WORK_ID=""
REPOS=()
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)        echo "unknown option: $arg" >&2; exit 2 ;;
    *)
      if [ -z "$WORK_ID" ]; then
        WORK_ID="$arg"
      else
        REPOS+=("$arg")
      fi
      ;;
  esac
done

if [ -z "$WORK_ID" ]; then
  echo "usage: $0 <work-id> [repo...] [--dry-run]" >&2
  exit 2
fi

# A work id is one path segment, and it is also a branch name. Anything with a
# separator, a glob or a traversal in it would put the worktree somewhere other
# than where every other tool looks for it.
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

# The hq repo first and always; then the named repos, in order, without repeating one.
ORDERED=("$HQ_REPO")
for repo in ${REPOS+"${REPOS[@]}"}; do
  case "$repo" in
    */*|.|..|-*|"") echo "refusing repo '$repo': give a directory name, not a path" >&2; exit 2 ;;
  esac
  for seen in "${ORDERED[@]}"; do
    [ "$seen" = "$repo" ] && continue 2
  done
  ORDERED+=("$repo")
done

# Validate every repo before creating anything, so a typo in the third repo does
# not leave a half-open workspace behind.
MISSING=()
for repo in "${ORDERED[@]}"; do
  [ -e "$ROOT/$repo/.git" ] || MISSING+=("$repo")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "no clone for: ${MISSING[*]}" >&2
  echo "expected under $ROOT — run ./05-TOOLS/sync.sh to clone what the group holds" >&2
  exit 2
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would run: $*"
  else
    "$@"
  fi
}

echo "opening $TARGET"

OPENED=0
for repo in "${ORDERED[@]}"; do
  clone="$ROOT/$repo"
  path="$TARGET/$repo"

  if [ -d "$path" ]; then
    echo "  $repo — already open, leaving it alone"
    continue
  fi

  echo "  $repo"
  run git -C "$clone" fetch origin --quiet
  # A workspace removed by hand rather than by 05-TOOLS/teardown-workspace.sh leaves the
  # worktree still registered in the clone, and `worktree add` then refuses the
  # path it is asked for. Clearing stale registrations first costs nothing and
  # removes nothing live.
  run git -C "$clone" worktree prune

  if git -C "$clone" show-ref --verify --quiet "refs/heads/$WORK_ID"; then
    # The branch is already here — a worktree for it was torn down, or it was
    # created outside a workspace. Reuse it rather than refusing.
    run git -C "$clone" worktree add "$path" "$WORK_ID"
  elif git -C "$clone" show-ref --verify --quiet "refs/remotes/origin/$WORK_ID"; then
    # Someone has already pushed this work id. Join it: branch from their work,
    # tracking it, so a push continues their MR instead of forking beside it.
    echo "    joining origin/$WORK_ID"
    run git -C "$clone" worktree add -b "$WORK_ID" "$path" "origin/$WORK_ID"
  else
    run git -C "$clone" worktree add -b "$WORK_ID" "$path" origin/main
    # `worktree add -b <id> … origin/main` leaves the new branch *tracking*
    # origin/main, so a bare `git push` in the worktree aims at main and is
    # refused only by git's `simple` default requiring matching names — one
    # config difference away from pushing to main by accident.
    run git -C "$path" branch --unset-upstream
  fi
  OPENED=$((OPENED + 1))
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run: nothing was changed"
  exit 0
fi

if [ "$OPENED" -eq 0 ]; then
  echo "done: nothing to open, $TARGET was already complete"
  exit 0
fi

echo "done: $OPENED worktree(s) on branch $WORK_ID"
echo
echo "Next: work there, then open the draft MR/PR on the first push — it is the claim."
echo "  cd $TARGET/<repo>"
if [ "$(hq_forge)" = github ]; then
  echo "  git push -u origin $WORK_ID"
  echo "  gh pr create --draft --label \"work/$WORK_ID\" \\"
  echo "    --title \"$WORK_ID: <what it does>\" --body \"$HQ_REPO: <path/to/work-item.md>\""
else
  echo "  glab mr create --draft --push --yes --label \"work/$WORK_ID\" \\"
  echo "    --title \"$WORK_ID: <what it does>\" --description \"$HQ_REPO: <path/to/work-item.md>\""
fi

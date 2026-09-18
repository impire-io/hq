#!/usr/bin/env bash
#
# commit-to-main.sh — the one code path that pushes to the hq repo's main.
#
# Sourced by allocate-issue.sh and claim.sh; run directly only as
# `bash 05-TOOLS/commit-to-main.sh --self-test`. The caller defines
# `apply_edit <worktree-dir>` which edits a pristine checkout of main and sets
# COMMIT_MSG (and optionally RESULT). This runs the compare-and-swap loop:
#
#   temp worktree at <remote>/main -> apply_edit -> commit -> push HEAD:main
#
# On a fast-forward race — a non-fast-forward push rejection — the edit is
# RECOMPUTED from scratch against the new main — never rebased — so a race
# loser mints the next number instead of colliding. That rejection is the
# allocation protocol working. A push refused for any other reason (a
# protected branch, an auth failure) is NOT retried — retrying would just
# burn attempts on a rejection that will not change.
#
# commit_to_main installs a process-global EXIT trap on every attempt (to
# clean up its temp worktree) and clears it before returning. Callers must
# not rely on their own EXIT trap surviving a call to commit_to_main — it
# will be overwritten while the call is in progress.
#
# apply_edit return codes:  0 edit ready   3 permanent refusal (do not retry)
#                           4 no-op success (nothing to push)   else error
# commit_to_main returns the same codes; 1 means retries exhausted.
#
# Env: HQ_DIR (repo dir override), HQ_REMOTE (default origin),
#      CTM_DRY_RUN=1 (show what would be committed, push nothing).
set -euo pipefail

CTM_ATTEMPTS=5

ctm_hq_dir() {
  if [ -n "${HQ_DIR:-}" ]; then
    echo "$HQ_DIR"
    return
  fi
  local here common
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  common="$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)"
  dirname "$common"
}

ctm_cleanup() { # <hq> <tmpdir>
  git -C "$1" worktree remove --force "$2/wt" >/dev/null 2>&1 || true
  git -C "$1" worktree prune >/dev/null 2>&1 || true
  rm -rf "$2"
}

commit_to_main() {
  local hq remote attempt tmp rc pushed_err
  hq="$(ctm_hq_dir)"
  remote="${HQ_REMOTE:-origin}"
  pushed_err=""
  for attempt in $(seq 1 "$CTM_ATTEMPTS"); do
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/hq-ctm.XXXXXX")"
    # shellcheck disable=SC2064  # expand now: tmp is per-iteration
    trap "ctm_cleanup '$hq' '$tmp'" EXIT
    git -C "$hq" fetch "$remote" main --quiet
    git -C "$hq" worktree add --detach --quiet "$tmp/wt" "refs/remotes/$remote/main"
    COMMIT_MSG="" RESULT=""
    set +e; apply_edit "$tmp/wt"; rc=$?; set -e
    case "$rc" in
      3|4) ctm_cleanup "$hq" "$tmp"; trap - EXIT; return "$rc" ;;
      0)   : ;;
      *)   ctm_cleanup "$hq" "$tmp"; trap - EXIT; return "$rc" ;;
    esac
    git -C "$tmp/wt" add -A
    if [ "${CTM_DRY_RUN:-0}" = 1 ]; then
      echo "dry run — would commit to main:" >&2
      git -C "$tmp/wt" status --short >&2
      ctm_cleanup "$hq" "$tmp"; trap - EXIT; return 0
    fi
    [ -n "$COMMIT_MSG" ] || { echo "apply_edit set no COMMIT_MSG" >&2; ctm_cleanup "$hq" "$tmp"; trap - EXIT; return 2; }
    git -C "$tmp/wt" commit --quiet -m "$COMMIT_MSG"
    if declare -f ctm_pre_push_hook >/dev/null; then ctm_pre_push_hook "$attempt"; fi
    set +e
    pushed_err="$(git -C "$tmp/wt" push "$remote" HEAD:main --quiet 2>&1)"
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then
      ctm_cleanup "$hq" "$tmp"; trap - EXIT; return 0
    fi
    if printf '%s\n' "$pushed_err" | grep -qiE 'non-fast-forward|fetch first|stale info|failed to push some refs.*behind'; then
      echo "push rejected (attempt $attempt/$CTM_ATTEMPTS) — recomputing against new main" >&2
      ctm_cleanup "$hq" "$tmp"; trap - EXIT
    else
      echo "$pushed_err" >&2
      echo "push refused for a non-race reason — if this is a permissions error, the protected main branch may not yet allow developer pushes (see 05-TOOLS/README.md prerequisites)" >&2
      ctm_cleanup "$hq" "$tmp"; trap - EXIT
      return 1
    fi
  done
  echo "gave up after $CTM_ATTEMPTS attempts; nothing was pushed. Last error:" >&2
  echo "$pushed_err" >&2
  return 1
}

# --- test fixture, shared by every 05-TOOLS self-test --------------------
# Only self-tests call this. It shields them from the machine's git config
# (identity includes, commit signing) so they pass on any machine, and gives
# the clone its own identity for commits that rely on ambient config.
ctm_make_fixture() { # <dir> -> echoes the clone path
  local dir="$1"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  git init --bare -q -b main "$dir/origin.git"
  git clone -q "$dir/origin.git" "$dir/seed"
  mkdir -p "$dir/seed/04-ISSUES/001-seed"
  printf -- '---\nkind: bug\nstatus: open\npriority: normal\n---\n\n# Seed\n\nseed issue\n' \
    > "$dir/seed/04-ISSUES/001-seed/00-report.md"
  git -C "$dir/seed" add -A
  git -C "$dir/seed" -c user.email=fixture@test -c user.name=fixture commit -qm seed
  git -C "$dir/seed" push -q origin main
  git clone -q "$dir/origin.git" "$dir/clone"
  git -C "$dir/clone" config user.email fixture@test
  git -C "$dir/clone" config user.name fixture
  echo "$dir/clone"
}

# --- self-test -----------------------------------------------------------
ctm_self_test() {
  local T pass=0 fail=0 clone
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-ctm-test.XXXXXX")"
  ok()  { echo "  PASS $1"; pass=$((pass+1)); }
  bad() { echo "  FAIL $1"; fail=$((fail+1)); }

  # case 1: a plain edit lands on main
  clone="$(ctm_make_fixture "$T/c1")"
  apply_edit() { echo hi > "$1/note.md"; COMMIT_MSG="test: note"; }
  ( cd / && HQ_DIR="$clone" commit_to_main ) \
    && git -C "$T/c1/origin.git" cat-file -e main:note.md 2>/dev/null \
    && ok "plain edit pushed" || bad "plain edit pushed"

  # case 2: race — an interloper takes main between checkout and push;
  # the retry must land on the NEW main, both commits present
  clone="$(ctm_make_fixture "$T/c2")"
  apply_edit() { echo mine > "$1/mine.md"; COMMIT_MSG="test: mine"; }
  ctm_pre_push_hook() {
    if [ "$1" = 1 ]; then
      git clone -q "$T/c2/origin.git" "$T/c2/interloper"
      echo theirs > "$T/c2/interloper/theirs.md"
      git -C "$T/c2/interloper" add -A
      git -C "$T/c2/interloper" -c user.email=i@test -c user.name=i commit -qm interloper
      git -C "$T/c2/interloper" push -q origin main
    fi
  }
  HQ_DIR="$clone" commit_to_main \
    && git -C "$T/c2/origin.git" cat-file -e main:mine.md 2>/dev/null \
    && git -C "$T/c2/origin.git" cat-file -e main:theirs.md 2>/dev/null \
    && ok "race retried and both landed" || bad "race retried and both landed"
  unset -f ctm_pre_push_hook

  # case 3: permanent refusal — rc 3, nothing pushed
  clone="$(ctm_make_fixture "$T/c3")"
  apply_edit() { echo "refused: held by someone else" >&2; return 3; }
  local rc=0; HQ_DIR="$clone" commit_to_main || rc=$?
  [ "$rc" = 3 ] && [ "$(git -C "$T/c3/origin.git" rev-list --count main)" = 1 ] \
    && ok "refusal aborts, main untouched" || bad "refusal aborts, main untouched"

  # case 4: retry exhaustion — perpetual interloper, rc 1, our file never lands
  clone="$(ctm_make_fixture "$T/c4")"
  git clone -q "$T/c4/origin.git" "$T/c4/interloper"
  apply_edit() { echo mine > "$1/mine.md"; COMMIT_MSG="test: mine"; }
  ctm_pre_push_hook() {
    echo "round $1" >> "$T/c4/interloper/theirs.md"
    git -C "$T/c4/interloper" add -A
    git -C "$T/c4/interloper" -c user.email=i@test -c user.name=i commit -qm "interloper $1"
    git -C "$T/c4/interloper" push -q origin main
  }
  rc=0; HQ_DIR="$clone" commit_to_main 2>/dev/null || rc=$?
  [ "$rc" = 1 ] && ! git -C "$T/c4/origin.git" cat-file -e main:mine.md 2>/dev/null \
    && ok "exhaustion gives up cleanly" || bad "exhaustion gives up cleanly"
  unset -f ctm_pre_push_hook

  rm -rf "$T"
  echo "commit-to-main self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --self-test) ctm_self_test ;;
    -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}" ;;
    *) echo "commit-to-main.sh is sourced by its callers; run --self-test or --help" >&2; exit 2 ;;
  esac
fi

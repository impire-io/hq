#!/usr/bin/env bash
#
# claim.sh — record intent on an issue: claimed-by + claimed date in its
# frontmatter, committed directly to main. A claim is intent;
# the draft MR remains the "work has started" signal (playbook 07).
#
# Usage:
#   claim.sh <issue>            claim it (idempotent for the holder)
#   claim.sh <issue> --release  release your own claim (no-op if unclaimed)
#   claim.sh <issue> --steal    take over another's claim — explicit, attributed
#                                (no-op if you already hold it)
#
# <issue> is a number (63, 063) or a full id (063-piano-...). Refused, with
# who and since when, if someone else holds it. Claiming or stealing a
# resolved/wontfix issue is refused; releasing one is not — the closing edit
# drops the claim (playbook 03 step 4), and --release is the cleanup for one it
# missed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/commit-to-main.sh"

cl_self_test() {
  local T clone pass=0 fail=0 rc before after
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-cl-test.XXXXXX")"
  clone="$(ctm_make_fixture "$T")"
  git -C "$clone" config user.email alice@test; git -C "$clone" config user.name alice

  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 1 >/dev/null \
    && git -C "$T/origin.git" show main:04-ISSUES/001-seed/00-report.md | grep -q '^claimed-by: alice@test' \
    && { echo "  PASS claim writes fields"; pass=$((pass+1)); } || { echo "  FAIL claim writes fields"; fail=$((fail+1)); }

  before="$(git -C "$T/origin.git" rev-list --count main)"
  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 >/dev/null 2>&1 || true
  after="$(git -C "$T/origin.git" rev-list --count main)"
  [ "$before" = "$after" ] \
    && { echo "  PASS re-claim is a no-op success"; pass=$((pass+1)); } || { echo "  FAIL re-claim is a no-op success"; fail=$((fail+1)); }

  git -C "$clone" config user.email bob@test
  rc=0; HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] && { echo "  PASS other holder refused"; pass=$((pass+1)); } || { echo "  FAIL other holder refused"; fail=$((fail+1)); }

  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 --steal >/dev/null \
    && git -C "$T/origin.git" show main:04-ISSUES/001-seed/00-report.md | grep -q '^claimed-by: bob@test' \
    && git -C "$T/origin.git" log -1 --format=%s main | grep -q 'stolen by bob@test from alice@test' \
    && { echo "  PASS steal is attributed"; pass=$((pass+1)); } || { echo "  FAIL steal is attributed"; fail=$((fail+1)); }

  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 --release >/dev/null \
    && ! git -C "$T/origin.git" show main:04-ISSUES/001-seed/00-report.md | grep -q '^claimed-by:' \
    && { echo "  PASS release removes fields"; pass=$((pass+1)); } || { echo "  FAIL release removes fields"; fail=$((fail+1)); }

  # a claim on a terminal issue: claiming is refused, releasing is not
  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 >/dev/null
  git -C "$clone" pull -q --ff-only origin main
  sed -i.bak 's/^status: open$/status: resolved/' "$clone/04-ISSUES/001-seed/00-report.md" && rm -f "$clone/04-ISSUES/001-seed/00-report.md.bak"
  git -C "$clone" -c user.email=bob@test -c user.name=bob commit -qam "close 001 without dropping the claim"
  git -C "$clone" push -q origin main
  rc=0; HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 --steal >/dev/null 2>&1 || rc=$?
  [ "$rc" = 3 ] && { echo "  PASS claim on a terminal issue refused"; pass=$((pass+1)); } || { echo "  FAIL claim on a terminal issue refused"; fail=$((fail+1)); }
  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 001 --release >/dev/null \
    && ! git -C "$T/origin.git" show main:04-ISSUES/001-seed/00-report.md | grep -q '^claimed-by:' \
    && { echo "  PASS release on a terminal issue works"; pass=$((pass+1)); } || { echo "  FAIL release on a terminal issue works"; fail=$((fail+1)); }

  rm -rf "$T"
  echo "claim self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

fm_of() { awk 'NR==1{if($0!="---")exit} NR>1&&$0=="---"{exit} NR>1{print}' "$1"; }

ISSUE="" MODE="claim"
while [ $# -gt 0 ]; do
  case "$1" in
    --release)   MODE="release" ;;
    --steal)     MODE="steal" ;;
    --self-test) cl_self_test; exit ;;
    -h|--help)   awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)  [ -z "$ISSUE" ] && ISSUE="$1" || { echo "one issue only" >&2; exit 2; } ;;
  esac; shift
done
[ -n "$ISSUE" ] || { echo "usage: claim.sh <issue> [--release|--steal]" >&2; exit 2; }
case "$ISSUE" in
  ''|*[!0-9]*) ;;  # not a bare number — treat as a full issue id, unchanged
  *) ISSUE="$(printf '%03d' "$((10#$ISSUE))")" ;;
esac

apply_edit() { # $1 = pristine worktree of main, at this attempt
  local wt="$1" dir report holder since status ME today
  ME="$(git -C "$wt" config user.email)"
  [ -n "$ME" ] || { echo "git config user.email is empty in $wt — a claim needs an identity" >&2; return 3; }

  case "$ISSUE" in
    [0-9][0-9][0-9]) dir="$(cd "$wt/04-ISSUES" && ls -d "$ISSUE"-*/ 2>/dev/null | head -1 | sed 's#/$##')" ;;
    *)               dir="$(cd "$wt/04-ISSUES" && ls -d "$ISSUE"/ 2>/dev/null | sed 's#/$##')" ;;
  esac
  [ -n "$dir" ] || { echo "no issue matching '$ISSUE' on main" >&2; return 3; }
  report="$wt/04-ISSUES/$dir/00-report.md"
  status="$(fm_of "$report" | sed -nE 's/^status: *//p')"
  holder="$(fm_of "$report" | sed -nE 's/^claimed-by: *//p')"
  since="$(fm_of "$report" | sed -nE 's/^claimed: *//p')"
  # A terminal issue is not claimable, but a claim left on one can always be
  # released: that is the flag status.sh raises, and this is its remedy.
  case "$MODE:$status" in
    claim:resolved|claim:wontfix|steal:resolved|steal:wontfix)
      echo "refusing: $dir is $status — a terminal issue is not claimable" >&2; return 3 ;;
  esac

  case "$MODE" in
    claim)
      if [ "$holder" = "$ME" ]; then
        echo "already yours (since $since) — nothing to do" >&2; return 4
      fi
      if [ -n "$holder" ]; then
        echo "refused: $dir is claimed by $holder since $since (use --steal to take it over)" >&2; return 3
      fi
      COMMIT_MSG="claim: $dir by $ME"
      ;;
    release)
      if [ -z "$holder" ]; then
        echo "not claimed — nothing to do" >&2; return 4
      fi
      if [ "$holder" != "$ME" ]; then
        echo "refused: $dir is claimed by $holder, not you" >&2; return 3
      fi
      COMMIT_MSG="claim: $dir released by $ME"
      ;;
    steal)
      if [ -z "$holder" ]; then
        COMMIT_MSG="claim: $dir by $ME"
      elif [ "$holder" = "$ME" ]; then
        echo "already yours (since $since) — nothing to do" >&2; return 4
      else
        COMMIT_MSG="claim: $dir stolen by $ME from $holder"
      fi
      ;;
  esac

  today="$(date +%F)"
  awk -v mode="$MODE" -v user="$ME" -v d="$today" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { if (mode!="release") { print "claimed-by: " user; print "claimed: " d }
                         infm=0; print; next }
    infm && (/^claimed-by:/ || /^claimed:/) { next }
    { print }
  ' "$report" > "$report.tmp" && mv "$report.tmp" "$report" || {
    rm -f "$report.tmp"
    echo "failed to rewrite frontmatter in $report" >&2
    return 2
  }
  RESULT="$dir"
}

rc=0; commit_to_main || rc=$?
case "$rc" in
  0) echo "$RESULT" ;;
  4) rc=0 ;;
esac
exit "$rc"

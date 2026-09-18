#!/usr/bin/env bash
#
# allocate-issue.sh — mint the next issue number by committing the record to
# main. The committed report is real and minimal; the work that
# claims the issue expands it by MR. Stdout is exactly one line — the
# allocated ID — so callers can take it as the work ID:
#
#   WORK_ID="$(05-TOOLS/allocate-issue.sh gateway-timeout --symptom "...")"
#
# Usage:
#   allocate-issue.sh <slug> --symptom "one line" [--kind bug|task]
#       [--priority high|normal|low] [--located-in repo[,repo]]
#       [--feature <name>] [--discovered-while "..."] [--claim] [--dry-run]
#
# --kind task requires --located-in (a task already knows its repo).
# --feature names a doc in 06-FEATURES/ (without .md); refused otherwise.
# --claim sets claimed-by/claimed in the same single commit.
# The duplicate-symptom search across 04-ISSUES/ is the CALLER's job, first.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/commit-to-main.sh"

ai_self_test() {
  local T clone id id2 pass=0 fail=0
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-ai-test.XXXXXX")"
  clone="$(ctm_make_fixture "$T")"
  git -C "$clone" config user.email tester@test
  git -C "$clone" config user.name tester
  mkdir -p "$clone/06-FEATURES"
  printf '# Alpha\n' > "$clone/06-FEATURES/alpha.md"
  git -C "$clone" add -A && git -C "$clone" commit -qm features && git -C "$clone" push -q origin main

  id="$(HQ_DIR="$clone" "${BASH_SOURCE[0]}" first-bug --symptom "it broke")"
  [ "$id" = "002-first-bug" ] \
    && git -C "$T/origin.git" cat-file -e "main:04-ISSUES/002-first-bug/00-report.md" \
    && { echo "  PASS allocates 002"; pass=$((pass+1)); } \
    || { echo "  FAIL allocates 002"; fail=$((fail+1)); }

  id2="$(HQ_DIR="$clone" "${BASH_SOURCE[0]}" second-task --symptom "do it" --kind task --located-in alpha --claim)"
  [ "$id2" = "003-second-task" ] \
    && git -C "$T/origin.git" show "main:04-ISSUES/003-second-task/00-report.md" | grep -q '^claimed-by: tester@test' \
    && git -C "$T/origin.git" show "main:04-ISSUES/003-second-task/00-report.md" | grep -q '^located-in: \[alpha\]' \
    && { echo "  PASS task+claim fields"; pass=$((pass+1)); } \
    || { echo "  FAIL task+claim fields"; fail=$((fail+1)); }

  id="$(HQ_DIR="$clone" "${BASH_SOURCE[0]}" third-tagged --symptom "tagged" --feature alpha)"
  [ "$id" = "004-third-tagged" ] \
    && git -C "$T/origin.git" show "main:04-ISSUES/004-third-tagged/00-report.md" | grep -q '^feature: alpha$' \
    && { echo "  PASS --feature writes feature:"; pass=$((pass+1)); } \
    || { echo "  FAIL --feature writes feature:"; fail=$((fail+1)); }

  HQ_DIR="$clone" "${BASH_SOURCE[0]}" fourth-bad --symptom x --feature nope 2>/dev/null \
    && { echo "  FAIL refuses unknown feature"; fail=$((fail+1)); } \
    || { echo "  PASS refuses unknown feature"; pass=$((pass+1)); }

  HQ_DIR="$clone" "${BASH_SOURCE[0]}" 004-numbered --symptom x 2>/dev/null \
    && { echo "  FAIL rejects numbered slug"; fail=$((fail+1)); } \
    || { echo "  PASS rejects numbered slug"; pass=$((pass+1)); }

  rm -rf "$T"
  echo "allocate-issue self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

SLUG="" SYMPTOM="" KIND="bug" PRIORITY="normal" LOCATED="" FEATURE="" DISCOVERED="" CLAIM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --symptom)          SYMPTOM="${2:?}"; shift ;;
    --kind)             KIND="${2:?}"; shift ;;
    --priority)         PRIORITY="${2:?}"; shift ;;
    --located-in)       LOCATED="${2:?}"; shift ;;
    --feature)          FEATURE="${2:?}"; shift ;;
    --discovered-while) DISCOVERED="${2:?}"; shift ;;
    --claim)            CLAIM=1 ;;
    --dry-run)          export CTM_DRY_RUN=1 ;;
    --self-test)        ai_self_test; exit ;;
    -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)  [ -z "$SLUG" ] && SLUG="$1" || { echo "one slug only" >&2; exit 2; } ;;
  esac; shift
done

usage_fail() { echo "$1" >&2; exit 2; }
[ -n "$SLUG" ] || usage_fail "usage: allocate-issue.sh <slug> --symptom \"...\" (see --help)"
case "$SLUG" in
  */*|*'*'*|*'?'*|*'['*|.|..|-*|[0-9][0-9][0-9]-*|"")
    usage_fail "refusing '$SLUG': one path segment, no globs, and no number — the number is allocated here" ;;
esac
[ -n "$SYMPTOM" ] || usage_fail "--symptom is required: the record must be real, not a stub"
case "$KIND" in bug|task) ;; *) usage_fail "--kind must be bug or task" ;; esac
case "$PRIORITY" in high|normal|low) ;; *) usage_fail "--priority must be high, normal or low" ;; esac
[ "$KIND" = task ] && [ -z "$LOCATED" ] && usage_fail "--kind task requires --located-in: a task already knows its repo"

title="$(echo "$SLUG" | tr '-' ' ')"
title="$(printf '%s' "$title" | awk '{ $1=toupper(substr($1,1,1)) substr($1,2) } 1')"

apply_edit() { # $1 = pristine worktree of main, at this attempt
  local wt="$1" next id dir
  if [ -n "$FEATURE" ] && [ ! -f "$wt/06-FEATURES/$FEATURE.md" ]; then
    echo "refused: '$FEATURE' is not a feature — no 06-FEATURES/$FEATURE.md" >&2; return 3
  fi
  next=$(( $(ls "$wt/04-ISSUES" | sed -nE 's/^([0-9]{3})-.*/\1/p' | sort -n | tail -1 | sed 's/^0*//') + 1 ))
  id="$(printf '%03d-%s' "$next" "$SLUG")"
  dir="$wt/04-ISSUES/$id"
  mkdir "$dir"
  {
    echo '---'
    echo "kind: $KIND"
    echo 'status: open'
    echo "priority: $PRIORITY"
    [ -n "$LOCATED" ]    && echo "located-in: [$(echo "$LOCATED" | sed 's/,/, /g')]"
    [ -n "$FEATURE" ]    && echo "feature: $FEATURE"
    [ -n "$DISCOVERED" ] && echo "discovered-while: $DISCOVERED"
    if [ "$CLAIM" = 1 ]; then
      echo "claimed-by: $(git -C "$wt" config user.email)"
      echo "claimed: $(date +%F)"
    fi
    echo '---'
    echo
    echo "# $title"
    echo
    echo "$SYMPTOM"
    echo
    echo '*Filed by allocate-issue.sh; report to be expanded by the work that claims it.*'
  } > "$dir/00-report.md"
  COMMIT_MSG="allocate: $id"
  RESULT="$id"
}

commit_to_main
echo "$RESULT"

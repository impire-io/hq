#!/usr/bin/env bash
#
# set-issue.sh — set an issue report's scalar state fields, committed straight
# to main. One command per transition playbook 03 describes, instead of a
# workspace, a branch, an MR and a merge for a one-line deterministic edit.
#
# Usage:
#   set-issue.sh <issue> key=value [key=value ...] [--dry-run]
#
# Keys and values:
#   kind        bug | task
#   priority    high | normal | low
#   status      open | diagnosing | located | blocked | resolved | wontfix
#   located-in  repo[,repo]   each a row of 00-META/repos.md; written as [a, b]
#   blocked-by  free text
#   feature     the name of a doc in 06-FEATURES/ (without .md)
#   resolved    YYYY-MM-DD    stamped today by status=resolved|wontfix if unset
#   reopened    YYYY-MM-DD
#
# An empty value (key=) removes the key. claimed-by/claimed belong to claim.sh;
# fixed-by, lands and amended-design carry evidence and stay by MR.
#
# Rules, all from playbook 03: status=located needs located-in (on the record
# or in the same call); blocked-by goes only with status=blocked, and leaving
# blocked clears it; a terminal status
# (resolved|wontfix) stamps resolved: and drops the claim; leaving a terminal
# status is refused — a later defect is a new issue, never a reopening. A close
# runs check-claims.sh --only <issue> before pushing and is refused when a ref
# does not verify (SET_ISSUE_CHECK overrides the command; the self-test uses it).
#
# Exit: 0 done (or nothing to change), 2 usage, 3 refused, 1 push retries exhausted.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/commit-to-main.sh"

fm_of() { awk 'NR==1{if($0!="---")exit} NR>1&&$0=="---"{exit} NR>1{print}' "$1"; }
fm_get() { fm_of "$1" | sed -nE "s/^$2: *//p" | head -1; }

si_self_test() {
  local T clone rep pass=0 fail=0 before after today
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-si-test.XXXXXX")"
  clone="$(ctm_make_fixture "$T")"
  git -C "$clone" config user.email tester@test
  git -C "$clone" config user.name tester
  # The fixture has no repos.md; located-in validates against it.
  mkdir -p "$clone/00-META"
  printf '| `gateway` | the gateway service |\n| `auth` | the auth service |\n' > "$clone/00-META/repos.md"
  mkdir -p "$clone/06-FEATURES"
  printf '# Alpha\n' > "$clone/06-FEATURES/alpha.md"
  git -C "$clone" add -A && git -C "$clone" commit -qm repos && git -C "$clone" push -q origin main
  rep() { git -C "$T/origin.git" show "main:04-ISSUES/001-seed/00-report.md"; }
  ok()  { echo "  PASS $1"; pass=$((pass+1)); }
  bad() { echo "  FAIL $1"; fail=$((fail+1)); }
  run() { HQ_DIR="$clone" SET_ISSUE_CHECK="${CHECK:-true}" "${BASH_SOURCE[0]}" "$@"; }
  today="$(date +%F)"

  run 1 priority=low >/dev/null 2>&1 \
    && rep | grep -q '^priority: low$' \
    && git -C "$T/origin.git" log -1 --format=%s main | grep -q '^set: 001-seed priority normal -> low by tester@test$' \
    && ok "sets priority and commits set: message" || bad "sets priority and commits set: message"

  before="$(git -C "$T/origin.git" rev-parse main)"
  run 1 priority=low >/dev/null 2>&1; after="$(git -C "$T/origin.git" rev-parse main)"
  [ "$before" = "$after" ] && ok "no-op pushes nothing" || bad "no-op pushes nothing"

  run 1 foo=bar >/dev/null 2>&1 && bad "refuses unknown key" || ok "refuses unknown key"
  run 1 claimed-by=x >/dev/null 2>&1 && bad "refuses claimed-by" || ok "refuses claimed-by"
  run 1 priority=urgent >/dev/null 2>&1 && bad "refuses bad value" || ok "refuses bad value"
  run 1 resolved=2026-13-45 >/dev/null 2>&1 && bad "refuses bad date" || ok "refuses bad date"
  run 1 located-in=nope >/dev/null 2>&1 && bad "refuses repo not in repos.md" || ok "refuses repo not in repos.md"
  run 1 feature=nope >/dev/null 2>&1 && bad "refuses feature without a doc" || ok "refuses feature without a doc"
  run 1 feature=alpha >/dev/null 2>&1 \
    && rep | grep -q '^feature: alpha$' \
    && ok "sets feature from 06-FEATURES" || bad "sets feature from 06-FEATURES"
  run 1 status=located >/dev/null 2>&1 && bad "located needs located-in" || ok "located needs located-in"

  run 1 status=located located-in=gateway,auth >/dev/null 2>&1 \
    && rep | grep -q '^located-in: \[gateway, auth\]$' \
    && rep | grep -q '^status: located$' \
    && ok "located with located-in list" || bad "located with located-in list"

  run 1 blocked-by="waiting on 002" >/dev/null 2>&1 && bad "blocked-by needs status=blocked" || ok "blocked-by needs status=blocked"
  run 1 status=blocked blocked-by="waiting on 002" >/dev/null 2>&1 \
    && rep | grep -q '^blocked-by: waiting on 002$' \
    && ok "blocked with blocked-by" || bad "blocked with blocked-by"
  run 1 status=located >/dev/null 2>&1 \
    && ! rep | grep -q '^blocked-by:' \
    && ok "leaving blocked clears blocked-by" || bad "leaving blocked clears blocked-by"

  run 1 priority= >/dev/null 2>&1 \
    && ! rep | grep -q '^priority:' \
    && ok "empty value removes the key" || bad "empty value removes the key"

  HQ_DIR="$clone" "$(dirname "${BASH_SOURCE[0]}")/claim.sh" 1 >/dev/null 2>&1
  CHECK=false run 1 status=resolved >/dev/null 2>&1 \
    && bad "close refused when the check fails" \
    || { rep | grep -q '^status: located$' && rep | grep -q '^claimed-by: tester@test$' \
         && ok "close refused when the check fails" || bad "close refused when the check fails"; }

  run 1 status=resolved >/dev/null 2>&1 \
    && rep | grep -q "^resolved: $today$" \
    && ! rep | grep -q '^claimed' \
    && ok "close stamps resolved and drops the claim" || bad "close stamps resolved and drops the claim"

  run 1 status=open >/dev/null 2>&1 && bad "refuses leaving a terminal status" || ok "refuses leaving a terminal status"

  rm -rf "$T"
  echo "set-issue self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

ISSUE="" SETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   export CTM_DRY_RUN=1 ;;
    --self-test) si_self_test; exit ;;
    -h|--help)   awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *=*) SETS+=("$1") ;;
    *)  [ -z "$ISSUE" ] && ISSUE="$1" || { echo "one issue only" >&2; exit 2; } ;;
  esac; shift
done
[ -n "$ISSUE" ] && [ "${#SETS[@]}" -gt 0 ] \
  || { echo "usage: set-issue.sh <issue> key=value [key=value ...] [--dry-run]" >&2; exit 2; }
case "$ISSUE" in
  ''|*[!0-9]*) ;;
  *) ISSUE="$(printf '%03d' "$((10#$ISSUE))")" ;;
esac

ALLOWED="kind priority status located-in feature blocked-by resolved reopened"
rank_of() { # canonical order for inserting a key that is not yet present
  case "$1" in
    kind) echo 1 ;; status) echo 2 ;; priority) echo 3 ;; located-in) echo 4 ;;
    feature) echo 5 ;; discovered-while) echo 6 ;; claimed-by) echo 7 ;; claimed) echo 8 ;;
    blocked-by) echo 9 ;; resolved) echo 10 ;; reopened) echo 11 ;; *) echo 100 ;;
  esac
}
is_date() { [[ "$1" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; }

# Parse key=value pairs once; validation that needs the tree waits for apply_edit.
KEYS=() VALS=()
for kv in "${SETS[@]}"; do
  k="${kv%%=*}"; v="${kv#*=}"
  case " $ALLOWED " in
    *" $k "*) ;;
    *)
      case "$k" in
        claimed-by|claimed) echo "refused: $k is set by 05-TOOLS/claim.sh" >&2 ;;
        *) echo "refused: '$k' is not a scalar state field (allowed: $ALLOWED)" >&2 ;;
      esac
      exit 3 ;;
  esac
  if [ -n "$v" ]; then
    case "$k" in
      kind)     case "$v" in bug|task) ;; *) echo "refused: kind must be bug|task" >&2; exit 3 ;; esac ;;
      priority) case "$v" in high|normal|low) ;; *) echo "refused: priority must be high|normal|low" >&2; exit 3 ;; esac ;;
      status)   case "$v" in open|diagnosing|located|blocked|resolved|wontfix) ;;
                  *) echo "refused: status must be open|diagnosing|located|blocked|resolved|wontfix" >&2; exit 3 ;; esac ;;
      resolved|reopened) is_date "$v" || { echo "refused: $k must be YYYY-MM-DD" >&2; exit 3; } ;;
      located-in) v="$(echo "$v" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | paste -sd, - | sed 's/,/, /g')"
                  v="[$v]" ;;
    esac
  fi
  KEYS+=("$k"); VALS+=("$v")
done

apply_edit() { # $1 = pristine worktree of main, at this attempt
  local wt="$1" dir report ME i k v cur status new_status changes="" edits
  ME="$(git -C "$wt" config user.email)"
  [ -n "$ME" ] || { echo "git config user.email is empty in $wt — an edit needs an identity" >&2; return 3; }

  case "$ISSUE" in
    [0-9][0-9][0-9]) dir="$(cd "$wt/04-ISSUES" && ls -d "$ISSUE"-*/ 2>/dev/null | head -1 | sed 's#/$##')" ;;
    *)               dir="$(cd "$wt/04-ISSUES" && ls -d "$ISSUE"/ 2>/dev/null | sed 's#/$##')" ;;
  esac
  [ -n "$dir" ] || { echo "no issue matching '$ISSUE' on main" >&2; return 3; }
  report="$wt/04-ISSUES/$dir/00-report.md"
  status="$(fm_get "$report" status)"

  # Effective values after this call, for the cross-field rules.
  new_status="$status"; local new_located; new_located="$(fm_get "$report" located-in)"
  local new_resolved; new_resolved="$(fm_get "$report" resolved)"
  for i in "${!KEYS[@]}"; do
    case "${KEYS[$i]}" in
      status)     new_status="${VALS[$i]}" ;;
      located-in) new_located="${VALS[$i]}" ;;
      resolved)   new_resolved="${VALS[$i]}" ;;
    esac
  done

  case "$status" in
    resolved|wontfix)
      if [ "$new_status" != "$status" ]; then
        echo "refused: $dir is $status — a later defect is a new issue, never a reopening (playbook 03); the MR path remains for the exception" >&2
        return 3
      fi ;;
  esac
  if [ "$new_status" = located ] && [ -z "$new_located" ]; then
    echo "refused: status=located needs located-in (on the record or in this call)" >&2; return 3
  fi
  for i in "${!KEYS[@]}"; do
    if [ "${KEYS[$i]}" = blocked-by ] && [ -n "${VALS[$i]}" ] && [ "$new_status" != blocked ]; then
      echo "refused: blocked-by goes only with status=blocked (playbook 03)" >&2; return 3
    fi
  done
  for i in "${!KEYS[@]}"; do
    if [ "${KEYS[$i]}" = feature ] && [ -n "${VALS[$i]}" ]; then
      [ -f "$wt/06-FEATURES/${VALS[$i]}.md" ] \
        || { echo "refused: '${VALS[$i]}' is not a feature — no 06-FEATURES/${VALS[$i]}.md" >&2; return 3; }
    fi
  done
  for i in "${!KEYS[@]}"; do
    if [ "${KEYS[$i]}" = located-in ] && [ -n "${VALS[$i]}" ]; then
      local name
      for name in $(echo "${VALS[$i]}" | tr -d '[],'); do
        grep -q "^| \`$name\` |" "$wt/00-META/repos.md" \
          || { echo "refused: '$name' is not a repo in 00-META/repos.md" >&2; return 3; }
      done
    fi
  done

  # Derived edits: the implicit ones playbook 03 attaches to a status change.
  edits="$(mktemp "${TMPDIR:-/tmp}/hq-si-edits.XXXXXX")"
  for i in "${!KEYS[@]}"; do
    printf '%s\t%s\n' "${KEYS[$i]}" "${VALS[$i]}" >> "$edits"
  done
  if [ "$new_status" != "$status" ]; then
    [ "$status" = blocked ] && [ "$new_status" != blocked ] && printf 'blocked-by\t\n' >> "$edits"
    case "$new_status" in
      blocked)
        local nb; nb="$(fm_get "$report" blocked-by)"
        for i in "${!KEYS[@]}"; do [ "${KEYS[$i]}" = blocked-by ] && nb="${VALS[$i]}"; done
        [ -n "$nb" ] || echo "note: blocked without blocked-by — name the blocker when you know it" >&2 ;;
      resolved|wontfix)
        [ -n "$new_resolved" ] || printf 'resolved\t%s\n' "$(date +%F)" >> "$edits"
        printf 'claimed-by\t\nclaimed\t\n' >> "$edits" ;;
    esac
  fi

  # Report each real change; drop the ones that change nothing.
  local kept; kept="$(mktemp "${TMPDIR:-/tmp}/hq-si-kept.XXXXXX")"
  while IFS=$'\t' read -r k v; do
    cur="$(fm_get "$report" "$k")"
    [ "$cur" = "$v" ] && continue
    printf '%s\t%s\n' "$k" "$v" >> "$kept"
    case " $ALLOWED " in *" $k "*) changes="${changes:+$changes, }$k ${cur:-(none)} -> ${v:-(none)}" ;; esac
  done < "$edits"
  rm -f "$edits"
  if [ ! -s "$kept" ]; then
    rm -f "$kept"; echo "nothing to change on $dir" >&2; return 4
  fi

  awk -F'\t' -v ranks="$(for k in kind status priority located-in feature discovered-while claimed-by claimed blocked-by resolved reopened; do printf '%s=%s ' "$k" "$(rank_of "$k")"; done)" '
    function rank(k,   n, i, kv) {
      n = split(ranks, arr, " ")
      for (i = 1; i <= n; i++) { split(arr[i], kv, "="); if (kv[1] == k) return kv[2] }
      return 100
    }
    FNR == 1 { pass++ }
    pass == 1 { key[$1] = 1; val[$1] = $2; order[++nk] = $1; next }
    pass == 2 {   # first pass over the report: which keys exist
      if (FNR == 1 && $0 == "---") { p = 1; next }
      if (p && $0 == "---") { p = 0; next }
      if (p && match($0, /^[a-z][a-z-]*:/)) present[substr($0, 1, RLENGTH - 1)] = 1
      next
    }
    FNR == 1 && $0 == "---" { infm = 1; print; next }
    infm && $0 == "---" {
      for (i = 1; i <= nk; i++) if (!done[order[i]] && !(order[i] in present) && val[order[i]] != "") print order[i] ": " val[order[i]]
      infm = 0; print; next
    }
    infm && match($0, /^[a-z][a-z-]*:/) {
      k = substr($0, 1, RLENGTH - 1)
      for (i = 1; i <= nk; i++)
        if (!done[order[i]] && !(order[i] in present) && val[order[i]] != "" && rank(order[i]) < rank(k)) {
          print order[i] ": " val[order[i]]; done[order[i]] = 1
        }
      if (k in key) { done[k] = 1; if (val[k] != "") print k ": " val[k]; next }
      print; next
    }
    { print }
  ' "$kept" "$report" "$report" > "$report.tmp" && mv "$report.tmp" "$report" || {
    rm -f "$report.tmp" "$kept"; echo "failed to rewrite frontmatter in $report" >&2; return 2
  }
  rm -f "$kept"

  # A close must prove its refs before it lands on main (playbook 03 step 4).
  if [ "$new_status" != "$status" ]; then
    case "$new_status" in
      resolved|wontfix)
        local check="${SET_ISSUE_CHECK:-bash $wt/05-TOOLS/check-claims.sh --only $dir}"
        if ! (cd "$wt" && eval "$check") >&2; then
          echo "refused: closing $dir — a fixed-by/lands ref did not verify; fix the record by MR, or run 05-TOOLS/sync.sh if a sibling clone is missing" >&2
          return 3
        fi ;;
    esac
  fi

  COMMIT_MSG="set: $dir $changes by $ME"
  RESULT="$dir"
}

rc=0; commit_to_main || rc=$?
case "$rc" in
  0) echo "$RESULT" ;;
  4) rc=0 ;;
esac
exit "$rc"

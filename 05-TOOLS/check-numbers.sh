#!/usr/bin/env bash
#
# 05-TOOLS/check-numbers.sh — every numbered record must have a unique number:
# issue folders in 04-ISSUES/ (NNN) and decision records in 03-DECISIONS/ (NNNN).
#
# Numbers are allocated "highest + 1" by scanning the tree. Under the isolated
# -worktree model (playbook 07) two in-flight branches each allocate against a
# base that lacks the other's new record, so both mint the same number and it
# collides silently at merge. Allocating against origin/main narrows the
# window; this guard closes it, turning a silent collision into a loud,
# pre-merge failure. Issues are minted atomically by allocate-issue.sh;
# decision records are still numbered by hand — hence both trees are checked.
#
# Fails if, in either tree:
#   - two records in the working tree share a number, or
#   - this branch adds a record whose number is already taken on origin/main.
#
# Resolution: renumber the LATER arrival to the next free number and repoint
# any references. The earlier number wins.
#
# Usage:
#   ./05-TOOLS/check-numbers.sh             # local
#   NO_FETCH=1 ./05-TOOLS/check-numbers.sh  # local, offline: skip the origin/main compare
#   CI=true ./05-TOOLS/check-numbers.sh     # CI
#   ./05-TOOLS/check-numbers.sh --self-test # both failure modes, both trees, on a throwaway repo
#
# Reads only the hq repo itself — no siblings, no deploy token.
set -euo pipefail

# num_of <path> <digits> — the leading number of a record's basename, or nothing.
num_of() { basename "$1" | sed -nE "s#^([0-9]{$2})-.*#\1#p"; }

# records <dir> <digits> — every record path in the working tree: folders under
# 04-ISSUES/, files under 03-DECISIONS/.
records() {
  local entry
  for entry in "$1"/*; do
    if [ -n "$(num_of "$entry" "$2")" ]; then echo "$entry"; fi
  done
  return 0
}

# check_tree <dir> <digits> <label> — both failure modes for one tree; leaves
# the number of records checked in COUNT; returns 1 on a collision.
check_tree() {
  local dir="$1" digits="$2" label="$3" failed=0 dups number entry slug main_numbers
  dups=$(records "$dir" "$digits" | while read -r entry; do num_of "$entry" "$digits"; done | sort | uniq -d || true)
  if [ -n "$dups" ]; then
    echo "Duplicate $label number(s) in the working tree:"
    for number in $dups; do
      echo "  $number:"
      for entry in "$dir"/"$number"-*; do echo "    $entry"; done
    done
    failed=1
  fi
  if [ "${NO_FETCH:-}" != "1" ] && [ -n "${MAIN_OK:-}" ]; then
    main_numbers=$(git ls-tree --name-only "origin/main:$dir" 2>/dev/null \
      | sed -nE "s#^([0-9]{$digits})-.*#\1#p" | sort -u || true)
    while read -r entry; do
      slug=$(basename "$entry")
      number=$(num_of "$entry" "$digits")
      if git cat-file -e "origin/main:$dir/$slug" 2>/dev/null; then
        continue
      fi
      if printf '%s\n' "$main_numbers" | grep -qx "$number"; then
        echo "$label number $number ($slug) is already taken on origin/main under a different name."
        failed=1
      fi
    done < <(records "$dir" "$digits")
  fi
  if [ "$failed" -ne 0 ]; then
    local max
    max=$(records "$dir" "$digits" | while read -r entry; do num_of "$entry" "$digits"; done | sort -n | tail -1 | sed 's/^0*//')
    printf 'Renumber the later %s to the next free number (%0*d) and repoint any references.\n' "$label" "$digits" "$(( ${max:-0} + 1 ))"
    return 1
  fi
  COUNT=$(records "$dir" "$digits" | wc -l | tr -d ' ')
}

self_test() {
  local tmp pass=0 fail=0 out
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hq-cn-test.XXXXXX")"
  git init -q "$tmp/origin" && git -C "$tmp/origin" -c user.email=t@test -c user.name=t commit -q --allow-empty -m seed
  mkdir -p "$tmp/origin/04-ISSUES/001-seed" "$tmp/origin/03-DECISIONS"
  echo r > "$tmp/origin/04-ISSUES/001-seed/00-report.md"; echo d > "$tmp/origin/03-DECISIONS/0001-seed.md"
  git -C "$tmp/origin" add -A && git -C "$tmp/origin" -c user.email=t@test -c user.name=t commit -qm records
  git -C "$tmp/origin" branch -M main
  git clone -q "$tmp/origin" "$tmp/work" && cp "${BASH_SOURCE[0]}" "$tmp/work/check-numbers.sh"
  local run="bash $tmp/work/check-numbers.sh"

  out=$(cd "$tmp/work" && $run 2>&1) && { echo "  PASS clean tree"; pass=$((pass+1)); } || { echo "  FAIL clean tree: $out"; fail=$((fail+1)); }

  mkdir -p "$tmp/work/04-ISSUES/001-other"
  out=$(cd "$tmp/work" && $run 2>&1) && { echo "  FAIL duplicate issue not caught"; fail=$((fail+1)); } || { echo "  PASS duplicate issue caught"; pass=$((pass+1)); }
  rmdir "$tmp/work/04-ISSUES/001-other"

  echo d > "$tmp/work/03-DECISIONS/0001-other.md"
  out=$(cd "$tmp/work" && $run 2>&1) && { echo "  FAIL duplicate decision not caught"; fail=$((fail+1)); } || { echo "  PASS duplicate decision caught"; pass=$((pass+1)); }
  rm "$tmp/work/03-DECISIONS/0001-other.md"

  # a number already taken on main under another name: mint 0002 on main, then on the branch
  echo d > "$tmp/origin/03-DECISIONS/0002-main.md"
  git -C "$tmp/origin" add -A && git -C "$tmp/origin" -c user.email=t@test -c user.name=t commit -qm 0002
  echo d > "$tmp/work/03-DECISIONS/0002-branch.md"
  out=$(cd "$tmp/work" && $run 2>&1) && { echo "  FAIL decision taken on main not caught"; fail=$((fail+1)); } || { echo "  PASS decision taken on main caught"; pass=$((pass+1)); }
  rm "$tmp/work/03-DECISIONS/0002-branch.md"

  mkdir -p "$tmp/origin/04-ISSUES/002-main"; echo r > "$tmp/origin/04-ISSUES/002-main/00-report.md"
  git -C "$tmp/origin" add -A && git -C "$tmp/origin" -c user.email=t@test -c user.name=t commit -qm 002
  mkdir -p "$tmp/work/04-ISSUES/002-branch"
  out=$(cd "$tmp/work" && $run 2>&1) && { echo "  FAIL issue taken on main not caught"; fail=$((fail+1)); } || { echo "  PASS issue taken on main caught"; pass=$((pass+1)); }

  rm -rf "$tmp"
  echo "check-numbers self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit; fi

# The tools tree sits one level below the repo root; the self-test copies the
# script to a fixture root, so accept either.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$here/04-ISSUES" ]; then cd "$here"; else cd "$here/.."; fi

MAIN_OK=""
if [ "${NO_FETCH:-}" != "1" ]; then
  if git fetch -q origin main 2>/dev/null; then
    MAIN_OK=1
  else
    echo "warning: could not fetch origin/main; skipped the cross-main check." >&2
  fi
fi

failed=0 COUNT=0
check_tree 04-ISSUES 3 issue || failed=1
issues=$COUNT
check_tree 03-DECISIONS 4 decision || failed=1
decisions=$COUNT
[ "$failed" -eq 0 ] || exit 1
echo "checked ${issues} issue folder(s) and ${decisions} decision record(s); no number collisions"
echo "OK"

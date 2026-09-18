#!/usr/bin/env bash
#
# 05-TOOLS/check-features.sh — every `feature:` names a feature doc, and every
# feature doc sits on the roadmap exactly once.
#
# A feature (06-FEATURES/<name>.md) carries no status and no member list:
# records join it by writing `feature: <name>` in their own frontmatter, and
# the README's numbered list is the roadmap. Two things can drift, and both
# are one grep away from being caught, so CI catches them:
#
#   - a `feature:` value on a research overview, a design doc, or an issue
#     report that names no doc in 06-FEATURES/ — a typo, or a feature that was
#     renamed without its members. set-issue.sh and allocate-issue.sh refuse
#     this on the direct-to-main route; research and design frontmatter travel
#     by MR and have no writer in front of them.
#   - a feature doc that is missing from the README's list, or listed twice,
#     or a list entry with no doc behind it — the roadmap is meant to be
#     complete, so an unlisted feature is a feature nobody has placed.
#
# It also refuses frontmatter on a feature doc: the doc states no contract, so
# a status there is either a duplicate of its designs' or wrong about them.
#
# Reads the working tree of the hq repo — the question is whether it *as it
# stands here* is consistent — and nothing else. No fetch, no siblings.
#
# Usage:
#   ./05-TOOLS/check-features.sh              # check this tree; exit 1 on any finding
#   ./05-TOOLS/check-features.sh --self-test  # exercise every finding on a throwaway tree
#
# Env: HQ_ROOT (tree to check; defaults to the repo this script sits in).

set -uo pipefail

fm_get() { # <file> <key> -> the value on "key: ..." inside the leading --- block
  awk -v k="$2" 'NR==1{if($0!="---")exit} NR>1&&$0=="---"{exit} \
    $0~"^"k": *"{sub("^"k": *",""); print; exit}' "$1"
}

check_tree() { # <root> -> prints findings, returns their count
  local root="$1" n=0 f v name known=" "
  local features="$root/06-FEATURES"

  if [ ! -d "$features" ]; then
    echo "MISSING  06-FEATURES/ does not exist"; return 1
  fi

  for f in "$features"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .md)"
    [ "$name" = README ] && continue
    known="$known$name "
    if [ "$(head -1 "$f")" = "---" ]; then
      echo "FRONTMATTER  06-FEATURES/$name.md carries frontmatter — a feature doc states no status; its designs do"
      n=$((n+1))
    fi
  done

  # The README's list: every doc once, every entry a doc.
  local listed
  listed="$(sed -nE 's/^[0-9]+\. +\[[^]]*\]\(([a-z0-9-]+)\.md\).*/\1/p' "$features/README.md" 2>/dev/null)"
  for name in $known; do
    case "$(printf '%s\n' "$listed" | grep -cx "$name")" in
      0) echo "UNLISTED  06-FEATURES/$name.md is not on the roadmap list in 06-FEATURES/README.md"; n=$((n+1)) ;;
      1) ;;
      *) echo "TWICE     06-FEATURES/$name.md is listed more than once in 06-FEATURES/README.md"; n=$((n+1)) ;;
    esac
  done
  for name in $listed; do
    case "$known" in *" $name "*) ;; *)
      echo "DANGLING  06-FEATURES/README.md lists $name, which has no 06-FEATURES/$name.md"; n=$((n+1)) ;;
    esac
  done

  # Every feature: value on a record names a doc.
  while IFS= read -r f; do
    v="$(fm_get "$f" feature)"
    [ -n "$v" ] || continue
    case "$known" in *" $v "*) ;; *)
      echo "UNKNOWN   ${f#$root/} names feature '$v', which has no 06-FEATURES/$v.md"; n=$((n+1)) ;;
    esac
  done < <(
    { ls "$root"/01-RESEARCH/[0-9]*/00-overview.md
      find "$root/02-DESIGN" -name '*.md'
      ls "$root"/04-ISSUES/[0-9]*/00-report.md; } 2>/dev/null | sort
  )

  return "$n"
}

self_test() {
  local T pass=0 fail=0 out
  ok()  { echo "  PASS $1"; pass=$((pass+1)); }
  bad() { echo "  FAIL $1"; fail=$((fail+1)); }
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-cf-test.XXXXXX")"

  mkdir -p "$T/06-FEATURES" "$T/01-RESEARCH/001-r" "$T/02-DESIGN/x" "$T/04-ISSUES/001-i" "$T/04-ISSUES/002-j"
  printf '# 06-FEATURES\n\n1. [Alpha](alpha.md)\n2. [Beta](beta.md)\n3. [Beta](beta.md)\n4. [Ghost](ghost.md)\n' > "$T/06-FEATURES/README.md"
  printf '# Alpha\n' > "$T/06-FEATURES/alpha.md"
  printf '# Beta\n' > "$T/06-FEATURES/beta.md"
  printf -- '---\nstatus: designed\n---\n# Gamma\n' > "$T/06-FEATURES/gamma.md"
  printf -- '---\nstatus: active\nfeature: alpha\n---\n# R\n' > "$T/01-RESEARCH/001-r/00-overview.md"
  printf -- '---\nstatus: designed\nfeature: nope\n---\n# D\n' > "$T/02-DESIGN/x/d.md"
  printf -- '---\nkind: bug\nstatus: open\nfeature: beta\n---\n# I\n' > "$T/04-ISSUES/001-i/00-report.md"
  printf -- '---\nkind: bug\nstatus: open\n---\n# J\n' > "$T/04-ISSUES/002-j/00-report.md"

  out="$(check_tree "$T")"; local rc=$?
  [ "$rc" = 5 ] && ok "five findings on the fixture (got $rc)" || bad "five findings on the fixture (got $rc)"
  printf '%s\n' "$out" | grep -q '^FRONTMATTER  06-FEATURES/gamma.md' && ok "frontmatter on a feature doc" || bad "frontmatter on a feature doc"
  printf '%s\n' "$out" | grep -q '^UNLISTED  06-FEATURES/gamma.md' && ok "unlisted doc" || bad "unlisted doc"
  printf '%s\n' "$out" | grep -q '^TWICE     06-FEATURES/beta.md' && ok "doc listed twice" || bad "doc listed twice"
  printf '%s\n' "$out" | grep -q '^DANGLING  06-FEATURES/README.md lists ghost' && ok "dangling list entry" || bad "dangling list entry"
  printf '%s\n' "$out" | grep -q "^UNKNOWN   02-DESIGN/x/d.md names feature 'nope'" && ok "unknown feature value" || bad "unknown feature value"
  printf '%s\n' "$out" | grep -q '001-r\|001-i\|002-j' && bad "valid and untagged records are silent" || ok "valid and untagged records are silent"

  printf '# 06-FEATURES\n\n1. [Alpha](alpha.md)\n2. [Beta](beta.md)\n' > "$T/06-FEATURES/README.md"
  printf '# Gamma\n' > "$T/06-FEATURES/gamma.md"
  printf '1. [Gamma](gamma.md)\n' >> "$T/06-FEATURES/README.md"
  printf -- '---\nstatus: designed\nfeature: gamma\n---\n# D\n' > "$T/02-DESIGN/x/d.md"
  check_tree "$T" >/dev/null && ok "clean tree passes" || bad "clean tree passes"

  rm -rf "$T"
  echo "check-features self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit ;;
  -h|--help)   awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

ROOT="${HQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if check_tree "$ROOT"; then
  echo "check-features: ok"
else
  echo "check-features: findings above — a feature: value or the roadmap list is inconsistent" >&2
  exit 1
fi

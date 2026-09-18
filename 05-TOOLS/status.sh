#!/usr/bin/env bash
#
# status.sh — render the hq repo's status view from frontmatter at
# origin/main. Light by design: one fetch of this repo, zero sibling repos. To
# verify the board against the fleet's git history, run
# 05-TOOLS/check-unclaimed.sh — deliberately NOT part of this.
#
# Usage:
#   status.sh                issues triage board (default)
#   status.sh --research     research by status
#   status.sh --design       design by implementation state
#   status.sh --repo <name>  outstanding for one repo (issues + designs)
#   status.sh --roadmap      the feature sequence from 06-FEATURES/README.md, each
#                            with its rollup derived from the records naming it
#   status.sh --feature <n>  one feature: its research, designs and issues
#   status.sh --all          every view
#   status.sh --no-fetch     offline; the render may be stale and says so
#
# Env: HQ_DIR (repo dir override), HQ_REF (default origin/main).
set -euo pipefail

# --- frontmatter / git plumbing ------------------------------------------

show() { git -C "$HQ" show "$REF:$1" 2>/dev/null || true; }

fm() { # <content> <key> -> value on the line "key: ..." inside the --- block
  awk -v k="$2" 'NR==1{if($0!="---")exit} NR>1&&$0=="---"{exit} \
    $0~"^"k": *"{sub("^"k": *",""); print; exit}' <<<"$1"
}

has_fm() { [ "$(printf '%s' "$1" | head -1)" = "---" ]; } # first line is the fence

fm_fields() { # <content> <key>... -> the keys' values joined by IFS_TSV, one awk pass
  local c="$1"; shift
  awk -v keys="$*" -v sep="$IFS_TSV" '
    BEGIN { n = split(keys, k, " ") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    { for (i = 1; i <= n; i++) if (!(i in v) && substr($0, 1, length(k[i]) + 1) == k[i] ":") {
        v[i] = substr($0, length(k[i]) + 2); sub(/^ */, "", v[i]) } }
    END { out = ""; for (i = 1; i <= n; i++) out = out (i > 1 ? sep : "") v[i]; print out }' <<<"$c"
}

# epoch(): GNU date first (Linux), then BSD date -j -f (macOS); empty on failure.
epoch() { date -d "$1" +%s 2>/dev/null || date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || echo ""; }

age_d() { # <YYYY-MM-DD> -> integer days since, or "?"
  local e
  e="$(epoch "$1")"
  if [ -n "$e" ]; then echo "$(( ($(date +%s) - e) / 86400 ))"; else echo "?"; fi
}

flag() { FLAGS="${FLAGS}- $1"$'\n'; } # accumulated, printed at the end

prio_ix() { case "$1" in high) echo 0 ;; low) echo 2 ;; *) echo 1 ;; esac; }

in_list() { # <needle> <raw fm value: "a" or "[a, b, c]"> -> exact membership
  local needle="$1" v="$2" p
  [ -n "$v" ] || return 1
  v="${v#\[}"; v="${v%\]}"
  local IFS=','
  local -a parts
  read -ra parts <<<"$v"
  for p in "${parts[@]}"; do
    p="${p//[[:space:]]/}"
    [ "$p" = "$needle" ] && return 0
  done
  return 1
}

# --- collection ------------------------------------------------------------

# Field separator for issues_tsv/render_issues/render_repo. NOT a tab: bash's
# `read` treats tab (like space and newline) as "IFS whitespace" and collapses
# runs of it, silently swallowing empty fields (a record with no located-in or
# no claimed-by is the common case, not the exception). \x1f (ASCII unit
# separator) is a strict, single-character delimiter with no such collapsing.
IFS_TSV=$'\x1f'

issues_tsv() { # NNN-slug US kind US status US priority US located US claimedby US claimed US blockedby
  local d c
  git -C "$HQ" ls-tree --name-only "$REF:04-ISSUES" 2>/dev/null | grep -E '^[0-9]{3}-' | while read -r d; do
    c="$(show "04-ISSUES/$d/00-report.md")"; [ -n "$c" ] || continue
    printf "%s${IFS_TSV}%s${IFS_TSV}%s${IFS_TSV}%s${IFS_TSV}%s${IFS_TSV}%s${IFS_TSV}%s${IFS_TSV}%s\n" "$d" "$(fm "$c" kind)" "$(fm "$c" status)" \
      "$(fm "$c" priority)" "$(fm "$c" located-in)" "$(fm "$c" claimed-by)" "$(fm "$c" claimed)" "$(fm "$c" blocked-by)"
  done
}

# blocked carries its reason inline on the board, so the why never needs a
# second lookup: "blocked — waiting on vendor". Other statuses pass through.
status_disp() { # <status> <blocked-by> -> display form
  if [ "$1" = blocked ] && [ -n "$2" ]; then echo "blocked — $2"; else echo "$1"; fi
}

# --- views -------------------------------------------------------------

render_issues() {
  echo "## Issues — triage board"; echo
  echo "| # | Issue | Kind | Status | Priority | Located in | Claimed |"
  echo "|---|-------|------|--------|----------|------------|---------|"

  local d kind status prio located cby cdate bby claimed age
  local low=0 resolved=0 wontfix=0
  local -a lines=()
  # process substitution, not a pipe: the while loop stays in THIS shell, so
  # low/resolved/wontfix and flag()'s FLAGS survive past the loop. (This is
  # the subshell trap the reference implementation fell into.)
  while IFS="$IFS_TSV" read -r d kind status prio located cby cdate bby; do
    [ -n "$d" ] || continue
    kind="${kind:-bug}"; prio="${prio:-normal}"
    case "$status" in
      resolved) resolved=$((resolved+1)); [ -n "$cby" ] && flag "\`$d\` is terminal but still claimed by $cby — the closing edit drops the claim; \`claim.sh $d --release\` is the remedy"; continue ;;
      wontfix)  wontfix=$((wontfix+1));   [ -n "$cby" ] && flag "\`$d\` is terminal but still claimed by $cby — the closing edit drops the claim; \`claim.sh $d --release\` is the remedy"; continue ;;
    esac
    if [ "$prio" = low ]; then low=$((low+1)); continue; fi
    claimed="—"
    if [ -n "$cby" ]; then
      age="$(age_d "$cdate")"; claimed="$cby (${age}d)"
      [ "$age" != "?" ] && [ "$age" -gt 14 ] && flag "\`$d\` claimed by $cby ${age} days ago — stale? (--steal is the remedy)"
    fi
    lines+=("$(prio_ix "$prio")"$'\t'"${d%%-*}"$'\t'"| ${d%%-*} | $d | $kind | $(status_disp "$status" "$bby") | $prio | ${located:-—} | $claimed |")
  done < <(issues_tsv)

  if [ "${#lines[@]}" -gt 0 ]; then
    printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
  fi
  echo
  echo "_Collapsed: ${low} low-priority active, ${resolved} resolved, ${wontfix} wontfix._"
  echo
}

render_research() {
  echo "## Research"; echo
  echo "| Effort | Status | Became |"; echo "|--------|--------|--------|"
  local d c s b
  while read -r d; do
    c="$(show "01-RESEARCH/$d/00-overview.md")"; [ -n "$c" ] || continue
    s="$(fm "$c" status)"; b="$(fm "$c" became)"
    echo "| $d | ${s:-?} | ${b:-—} |"
    case "$s" in graduated|concluded-artifact|abandoned)
      [ -z "$b" ] && flag "\`01-RESEARCH/$d\` is terminal ($s) but has no \`became:\`" ;; esac
  done < <(git -C "$HQ" ls-tree --name-only "$REF:01-RESEARCH" 2>/dev/null | grep -E '^[0-9]{3}-' || true)
  echo
}

render_design() {
  echo "## Design"; echo
  echo "| Doc | Status | Code | Updated |"; echo "|-----|--------|------|---------|"
  local f c s code up
  while read -r f; do
    c="$(show "02-DESIGN/$f")"
    has_fm "$c" || continue   # aggregators carry no frontmatter: skip silently
    s="$(fm "$c" status)"; code="$(fm "$c" code)"; up="$(fm "$c" updated)"
    echo "| $f | ${s:-?} | ${code:-—} | ${up:-—} |"
    [ "$s" = implemented ] && [ -z "$code" ] && flag "\`02-DESIGN/$f\` is implemented but has no \`code:\`"
  done < <(git -C "$HQ" ls-tree -r --name-only "$REF:02-DESIGN" 2>/dev/null | grep '\.md$' || true)
  echo
}

render_repo() {
  echo "## Outstanding for $REPO"; echo
  echo "### Issues (located-in)"; echo
  local d kind status prio located cby cdate bby found=0
  while IFS="$IFS_TSV" read -r d kind status prio located cby cdate bby; do
    [ -n "$d" ] || continue
    case "$status" in resolved|wontfix) continue ;; esac
    if in_list "$REPO" "$located"; then
      echo "- \`$d\` (${kind:-bug}, $(status_disp "$status" "$bby"), ${prio:-normal})"
      found=1
    fi
  done < <(issues_tsv)
  [ "$found" = 1 ] || echo "_none_"
  echo

  echo "### Designs not implemented (code:)"; echo
  local f c s code any=0
  while read -r f; do
    c="$(show "02-DESIGN/$f")"
    has_fm "$c" || continue
    code="$(fm "$c" code)"; s="$(fm "$c" status)"
    if in_list "$REPO" "$code" && [ "$s" != implemented ]; then
      echo "- \`02-DESIGN/$f\` ($s)"
      any=1
    fi
  done < <(git -C "$HQ" ls-tree -r --name-only "$REF:02-DESIGN" 2>/dev/null | grep '\.md$' || true)
  [ "$any" = 1 ] || echo "_none_"
  echo
}

# --- features (06-FEATURES) --------------------------------------------------
#
# A feature doc carries no status; where a feature stands is read from the
# records that name it in `feature:` (research overviews, design docs, issue
# reports). The roadmap is the README's numbered list, order only.

feature_names() { # every feature doc in 06-FEATURES, by name (README excluded)
  git -C "$HQ" ls-tree --name-only "$REF:06-FEATURES" 2>/dev/null \
    | sed -nE 's/^([a-z0-9-]+)\.md$/\1/p' | grep -v '^README$' || true
}

feature_title() { # <name> -> the doc's H1, or the name when it has none
  local t
  t="$(show "06-FEATURES/$1.md" | sed -nE 's/^# +//p' | head -1)"
  echo "${t:-$1}"
}

roadmap_names() { # the README's numbered list, in order
  show 06-FEATURES/README.md | sed -nE 's/^[0-9]+\. +\[[^]]*\]\(([a-z0-9-]+)\.md\).*/\1/p'
}

# members_tsv: one line per record that may carry feature:, tagged or not.
#   research US dir  US status US feature
#   design   US path US status US feature
#   issue    US dir  US status US feature US kind US priority US located US claimed-by US claimed US blocked-by
members_tsv() {
  local d f c
  while read -r d; do
    c="$(show "01-RESEARCH/$d/00-overview.md")"; [ -n "$c" ] || continue
    printf "research${IFS_TSV}%s${IFS_TSV}%s\n" "$d" "$(fm_fields "$c" status feature)"
  done < <(git -C "$HQ" ls-tree --name-only "$REF:01-RESEARCH" 2>/dev/null | grep -E '^[0-9]{3}-' || true)
  while read -r f; do
    c="$(show "02-DESIGN/$f")"; has_fm "$c" || continue
    printf "design${IFS_TSV}%s${IFS_TSV}%s\n" "$f" "$(fm_fields "$c" status feature)"
  done < <(git -C "$HQ" ls-tree -r --name-only "$REF:02-DESIGN" 2>/dev/null | grep '\.md$' || true)
  while read -r d; do
    c="$(show "04-ISSUES/$d/00-report.md")"; [ -n "$c" ] || continue
    printf "issue${IFS_TSV}%s${IFS_TSV}%s\n" "$d" \
      "$(fm_fields "$c" status feature kind priority located-in claimed-by claimed blocked-by)"
  done < <(git -C "$HQ" ls-tree --name-only "$REF:04-ISSUES" 2>/dev/null | grep -E '^[0-9]{3}-' || true)
}

# The walk runs once per render, in the main shell: a cache filled from inside
# a `< <(members)` substitution would live in that subshell and be lost, and
# the roadmap would walk every record once per feature (it did: 316s).
MEMBERS_FILE=""
members_load() {
  [ -n "$MEMBERS_FILE" ] && return 0
  MEMBERS_FILE="$(mktemp "${TMPDIR:-/tmp}/hq-status-members.XXXXXX")"
  members_tsv > "$MEMBERS_FILE"
}
members() { cat "$MEMBERS_FILE"; }
members_done() { [ -n "$MEMBERS_FILE" ] && command rm -f -- "$MEMBERS_FILE"; MEMBERS_FILE=""; }

# rollup: the deterministic reading 06-FEATURES/README.md states. Open issues
# never demote a feature; they are counted beside the state.
rollup() { # <feature> -> "state · counts"
  local kind id status feat rest state parts=""
  local d_designed=0 d_prog=0 d_impl=0 r_active=0 i_open=0
  while IFS="$IFS_TSV" read -r kind id status feat rest; do
    [ "$feat" = "$1" ] || continue
    case "$kind" in
      research) [ "$status" = active ] && r_active=$((r_active+1)) ;;
      design) case "$status" in
                designed)    d_designed=$((d_designed+1)) ;;
                in-progress) d_prog=$((d_prog+1)) ;;
                implemented) d_impl=$((d_impl+1)) ;;
              esac ;;
      issue) case "$status" in resolved|wontfix) ;; *) i_open=$((i_open+1)) ;; esac ;;
    esac
  done < <(members)
  if   [ "$d_prog" -gt 0 ] || { [ "$d_impl" -gt 0 ] && [ "$d_designed" -gt 0 ]; }; then state=building
  elif [ "$d_impl" -gt 0 ];     then state=live
  elif [ "$d_designed" -gt 0 ]; then state=designing
  elif [ "$r_active" -gt 0 ];   then state=exploring
  else state="no open work"; fi
  local dparts=""
  [ "$d_designed" -gt 0 ] && dparts="${dparts:+$dparts, }$d_designed designed"
  [ "$d_prog" -gt 0 ]     && dparts="${dparts:+$dparts, }$d_prog in-progress"
  [ "$d_impl" -gt 0 ]     && dparts="${dparts:+$dparts, }$d_impl implemented"
  [ -n "$dparts" ]        && parts="designs: $dparts"
  [ "$r_active" -gt 0 ]   && parts="${parts:+$parts · }$r_active research active"
  [ "$i_open" -gt 0 ]     && parts="${parts:+$parts · }$i_open issue$([ "$i_open" = 1 ] || echo s) open"
  echo "$state${parts:+ · $parts}"
}

flag_unknown_features() { # a feature: value naming no doc in 06-FEATURES
  local kind id status feat rest known
  known=" $(feature_names | tr '\n' ' ') "
  while IFS="$IFS_TSV" read -r kind id status feat rest; do
    [ -n "$feat" ] || continue
    case "$known" in *" $feat "*) ;; *)
      case "$kind" in
        research) flag "\`01-RESEARCH/$id\` names feature \`$feat\`, which has no doc in 06-FEATURES" ;;
        design)   flag "\`02-DESIGN/$id\` names feature \`$feat\`, which has no doc in 06-FEATURES" ;;
        issue)    flag "\`$id\` names feature \`$feat\`, which has no doc in 06-FEATURES" ;;
      esac ;;
    esac
  done < <(members)
}

render_roadmap() {
  members_load
  echo "## Roadmap"; echo
  local n=0 name seen=" "
  while read -r name; do
    n=$((n+1))
    if [ -n "$(show "06-FEATURES/$name.md")" ]; then
      echo "$n. **$(feature_title "$name")** (\`$name\`) — $(rollup "$name")"
    else
      echo "$n. \`$name\` — no such feature doc"
      flag "06-FEATURES/README.md lists \`$name\`, which has no doc in 06-FEATURES"
    fi
    seen="$seen$name "
  done < <(roadmap_names)
  [ "$n" -gt 0 ] || echo "_06-FEATURES/README.md has no numbered list_"
  for name in $(feature_names); do
    case "$seen" in *" $name "*) ;; *) flag "\`06-FEATURES/$name.md\` is not on the roadmap list in 06-FEATURES/README.md" ;; esac
  done
  flag_unknown_features
  echo

  echo "### Unassigned"; echo
  echo "_Records with open work and no \`feature:\` — tag them, or leave them if they belong to no feature._"; echo
  local kind id status feat rest any=0
  while IFS="$IFS_TSV" read -r kind id status feat rest; do
    [ -z "$feat" ] || continue
    case "$kind" in
      research) [ "$status" = active ] || continue; echo "- \`01-RESEARCH/$id\` (research, $status)" ;;
      design)   [ "$status" = abandoned ] && continue; echo "- \`02-DESIGN/$id\` (design, ${status:-?})" ;;
      issue)    case "$status" in resolved|wontfix) continue ;; esac; echo "- \`$id\` (issue, ${status:-?})" ;;
    esac
    any=1
  done < <(members)
  [ "$any" = 1 ] || echo "_none_"
  echo
}

render_feature() { # $FEATURE
  if [ -z "$(show "06-FEATURES/$FEATURE.md")" ]; then
    echo "no feature named '$FEATURE' in 06-FEATURES (have: $(feature_names | tr '\n' ' '))" >&2; exit 2
  fi
  members_load
  echo "## $(feature_title "$FEATURE") (\`$FEATURE\`)"; echo
  echo "_$(rollup "$FEATURE")_"; echo

  local kind id status feat rest any code
  echo "### Research"; echo
  echo "| Effort | Status |"; echo "|--------|--------|"
  any=0
  while IFS="$IFS_TSV" read -r kind id status feat rest; do
    [ "$kind" = research ] && [ "$feat" = "$FEATURE" ] || continue
    echo "| $id | ${status:-?} |"; any=1
  done < <(members)
  [ "$any" = 1 ] || echo "| _none_ | |"
  echo

  echo "### Design"; echo
  echo "| Doc | Status | Code |"; echo "|-----|--------|------|"
  any=0
  while IFS="$IFS_TSV" read -r kind id status feat rest; do
    [ "$kind" = design ] && [ "$feat" = "$FEATURE" ] || continue
    code="$(fm "$(show "02-DESIGN/$id")" code)"
    echo "| $id | ${status:-?} | ${code:-—} |"; any=1
  done < <(members)
  [ "$any" = 1 ] || echo "| _none_ | | |"
  echo

  echo "### Issues"; echo
  echo "| # | Issue | Kind | Status | Priority | Located in | Claimed |"
  echo "|---|-------|------|--------|----------|------------|---------|"
  local ikind prio located cby cdate bby claimed age closed=0
  local -a lines=()
  while IFS="$IFS_TSV" read -r kind id status feat ikind prio located cby cdate bby; do
    [ "$kind" = issue ] && [ "$feat" = "$FEATURE" ] || continue
    case "$status" in resolved|wontfix) closed=$((closed+1)); continue ;; esac
    ikind="${ikind:-bug}"; prio="${prio:-normal}"; claimed="—"
    if [ -n "$cby" ]; then age="$(age_d "$cdate")"; claimed="$cby (${age}d)"; fi
    lines+=("$(prio_ix "$prio")"$'\t'"${id%%-*}"$'\t'"| ${id%%-*} | $id | $ikind | $(status_disp "$status" "$bby") | $prio | ${located:-—} | $claimed |")
  done < <(members)
  if [ "${#lines[@]}" -gt 0 ]; then
    printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
  else
    echo "| | _none open_ | | | | | |"
  fi
  echo
  echo "_Collapsed: ${closed} resolved or wontfix._"
  echo
}

# --- self-test -----------------------------------------------------------

st_self_test() {
  local T fixture pass=0 fail=0 out
  ok()  { echo "  PASS $1"; pass=$((pass+1)); }
  bad() { echo "  FAIL $1"; fail=$((fail+1)); }

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-status-test.XXXXXX")"
  fixture="$T/fixture"
  mkdir -p "$fixture"
  git -C "$fixture" init -q -b main

  mkdir -p "$fixture/04-ISSUES/001-open-bug"
  printf -- '---\nkind: bug\nstatus: open\npriority: high\nfeature: alpha\n---\n\n# Open bug\n\nsomething is broken.\n' \
    > "$fixture/04-ISSUES/001-open-bug/00-report.md"

  mkdir -p "$fixture/04-ISSUES/002-resolved-one"
  printf -- '---\nkind: bug\nstatus: resolved\npriority: normal\nclaimed-by: alice@test\nclaimed: 2026-01-01\n---\n\n# Resolved one\n\nfixed, claim never dropped.\n' \
    > "$fixture/04-ISSUES/002-resolved-one/00-report.md"

  mkdir -p "$fixture/04-ISSUES/003-claimed-old"
  printf -- '---\nkind: bug\nstatus: open\npriority: normal\nclaimed-by: alice@test\nclaimed: 2026-01-01\nfeature: nope\n---\n\n# Claimed old\n\nstale claim.\n' \
    > "$fixture/04-ISSUES/003-claimed-old/00-report.md"

  mkdir -p "$fixture/04-ISSUES/004-blocked-one"
  printf -- '---\nkind: bug\nstatus: blocked\npriority: normal\nblocked-by: waiting on vendor ticket 123\n---\n\n# Blocked one\n\nstuck.\n' \
    > "$fixture/04-ISSUES/004-blocked-one/00-report.md"

  mkdir -p "$fixture/01-RESEARCH/001-done"
  printf -- '---\nstatus: graduated\n---\n\n# Done\n\nconcluded.\n' \
    > "$fixture/01-RESEARCH/001-done/00-overview.md"

  mkdir -p "$fixture/02-DESIGN"
  printf -- '---\nstatus: implemented\nupdated: 2026-01-01\nfeature: alpha\n---\n\n# Thing\n\nimplemented, but code: is missing.\n' \
    > "$fixture/02-DESIGN/thing.md"
  printf -- '---\nstatus: designed\nupdated: 2026-01-01\nfeature: beta\n---\n\n# Beta thing\n\ndesigned, not built.\n' \
    > "$fixture/02-DESIGN/beta-thing.md"
  printf -- '# Design\n\nAn aggregator doc — no frontmatter, no contract.\n' \
    > "$fixture/02-DESIGN/README.md"

  # Features: alpha is live (thing.md + 001), beta is designed, gamma is a doc
  # the README forgot, and 003 names a feature that has no doc.
  mkdir -p "$fixture/06-FEATURES"
  printf '# 06-FEATURES\n\n## The roadmap\n\n1. [Alpha](alpha.md)\n2. [Beta](beta.md)\n' > "$fixture/06-FEATURES/README.md"
  printf '# Alpha\n\nlive feature.\n' > "$fixture/06-FEATURES/alpha.md"
  printf '# Beta\n\ndesigned feature.\n' > "$fixture/06-FEATURES/beta.md"
  printf '# Gamma\n\nnot on the roadmap.\n' > "$fixture/06-FEATURES/gamma.md"

  git -C "$fixture" add -A
  git -C "$fixture" -c user.email=fixture@test -c user.name=fixture commit -q -m "status.sh fixture"

  out="$(HQ_DIR="$fixture" HQ_REF=main "${BASH_SOURCE[0]}" --all --no-fetch)"

  printf '%s\n' "$out" | grep -qF '| 001 | 001-open-bug |' \
    && ok "001-open-bug is an active row" || bad "001-open-bug is an active row"

  printf '%s\n' "$out" | grep -qF '1 resolved' \
    && ok "resolved count is 1" || bad "resolved count is 1"

  printf '%s\n' "$out" | grep -qF '| 002 | 002-resolved-one |' \
    && bad "002-resolved-one does not appear as a row" || ok "002-resolved-one does not appear as a row"

  printf '%s\n' "$out" | grep -qF '`002-resolved-one` is terminal but still claimed by alice@test — the closing edit drops the claim; `claim.sh 002-resolved-one --release` is the remedy' \
    && ok "terminal-but-claimed flag names its remedy" || bad "terminal-but-claimed flag names its remedy"

  printf '%s\n' "$out" | grep -qF '`003-claimed-old` claimed by alice@test' \
    && ok "stale-claim flag for 003-claimed-old" || bad "stale-claim flag for 003-claimed-old"

  printf '%s\n' "$out" | grep -qF '| 004 | 004-blocked-one | bug | blocked — waiting on vendor ticket 123 |' \
    && ok "blocked row carries its reason inline" || bad "blocked row carries its reason inline"

  printf '%s\n' "$out" | grep -qF '`01-RESEARCH/001-done` is terminal (graduated) but has no `became:`' \
    && ok "missing became: flag" || bad "missing became: flag"

  printf '%s\n' "$out" | grep -qF '`02-DESIGN/thing.md` is implemented but has no `code:`' \
    && ok "missing code: flag" || bad "missing code: flag"

  printf '%s\n' "$out" | grep -qF '02-DESIGN/README.md' \
    && bad "aggregator README.md is skipped" || ok "aggregator README.md is skipped"

  printf '%s\n' "$out" | grep -qF '1. **Alpha** (`alpha`) — live · designs: 1 implemented · 1 issue open' \
    && ok "roadmap rolls alpha up as live with its counts" || bad "roadmap rolls alpha up as live with its counts"

  printf '%s\n' "$out" | grep -qF '2. **Beta** (`beta`) — designing · designs: 1 designed' \
    && ok "roadmap rolls beta up as designing" || bad "roadmap rolls beta up as designing"

  printf '%s\n' "$out" | grep -qF '`06-FEATURES/gamma.md` is not on the roadmap list' \
    && ok "feature doc missing from the roadmap is flagged" || bad "feature doc missing from the roadmap is flagged"

  printf '%s\n' "$out" | grep -qF '`003-claimed-old` names feature `nope`, which has no doc in 06-FEATURES' \
    && ok "unknown feature value is flagged" || bad "unknown feature value is flagged"

  printf '%s\n' "$out" | grep -qF -- '- `004-blocked-one` (issue, blocked)' \
    && ok "untagged open issue is listed as unassigned" || bad "untagged open issue is listed as unassigned"

  printf '%s\n' "$out" | grep -qF -- '- `001-open-bug`' \
    && bad "tagged issue is not listed as unassigned" || ok "tagged issue is not listed as unassigned"

  out="$(HQ_DIR="$fixture" HQ_REF=main "${BASH_SOURCE[0]}" --feature alpha --no-fetch)"

  printf '%s\n' "$out" | grep -qF '## Alpha (`alpha`)' \
    && printf '%s\n' "$out" | grep -qF '| 001 | 001-open-bug |' \
    && printf '%s\n' "$out" | grep -qF '| thing.md | implemented | — |' \
    && ok "--feature lists the feature's members" || bad "--feature lists the feature's members"

  printf '%s\n' "$out" | grep -qF '004-blocked-one' \
    && bad "--feature omits other features' records" || ok "--feature omits other features' records"

  HQ_DIR="$fixture" HQ_REF=main "${BASH_SOURCE[0]}" --feature nope --no-fetch >/dev/null 2>&1 \
    && bad "--feature refuses an unknown feature" || ok "--feature refuses an unknown feature"

  rm -rf "$T"
  echo "status self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

# --- args ------------------------------------------------------------------

VIEW="issues" REPO="" FEATURE="" FETCH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --research)  VIEW="research" ;;
    --design)    VIEW="design" ;;
    --repo)      VIEW="repo"; REPO="${2:?--repo needs a repo name}"; shift ;;
    --roadmap)   VIEW="roadmap" ;;
    --feature)   VIEW="feature"; FEATURE="${2:?--feature needs a feature name}"; shift ;;
    --all)       VIEW="all" ;;
    --no-fetch)  FETCH=0 ;;
    --self-test) st_self_test; exit ;;
    -h|--help)   awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done

HQ="${HQ_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REF="${HQ_REF:-origin/main}"
FLAGS=""

if [ "$FETCH" = 1 ]; then
  git -C "$HQ" fetch origin --quiet
else
  echo '> **--no-fetch:** rendered from the last fetch; may be stale.'; echo
fi

case "$VIEW" in
  issues)   render_issues ;;
  research) render_research ;;
  design)   render_design ;;
  repo)     render_repo ;;
  roadmap)  render_roadmap ;;
  feature)  render_feature ;;
  all)      render_roadmap; render_issues; render_research; render_design ;;
esac
members_done

if [ -n "$FLAGS" ]; then echo "## Flags"; echo; printf '%s' "$FLAGS"; echo; fi
echo "_View reflects frontmatter on \`$REF\`; run \`05-TOOLS/check-unclaimed.sh\` to verify it against the fleet's git history._"

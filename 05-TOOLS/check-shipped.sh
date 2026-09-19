#!/usr/bin/env bash
#
# 05-TOOLS/check-shipped.sh — a design whose build has started cannot keep reading `designed`.
#
# Issues have `fixed-by:`, which 05-TOOLS/check-claims.sh verifies against git.
# Designs have nothing equivalent: `status: implemented` is an unverifiable
# assertion and `status: designed` an unverifiable absence. So a design whose
# build landed on a code repo's main can read `designed` — which every
# generated view renders as "never handed off" — indefinitely.
#
# The strongest evidence a build started is the one the spec-kit flow already
# produces: playbook 04 step 3 requires the owning repo's spec to cite the
# hq design by path. This check reads that citation. It scans every
# sibling's `specs/*/spec.md` at origin/main for `02-DESIGN/….md` paths — bare,
# hq-repo-prefixed, or inside a forge blob URL — and flags any cited design
# whose status is still `designed`: playbook 04 step 5 (set `in-progress` at
# handoff) or step 7 (set `implemented` when the contract runs on main) was
# skipped.
#
# Usage:
#   ./05-TOOLS/check-shipped.sh             # local: expects sibling clones beside this repo
#   NO_FETCH=1 ./05-TOOLS/check-shipped.sh  # local, offline: use origin/main as last fetched
#   CI=true ./05-TOOLS/check-shipped.sh     # CI: clones the repos it needs (shallow — no history needed)
#   ./05-TOOLS/check-shipped.sh --self-test # exercise every tier and both scopes on a throwaway fleet
#
# CI credential: HQ_FLEET_TOKEN (GitHub) or HQ_FLEET_USER + HQ_FLEET_TOKEN
# (GitLab), as documented in 05-TOOLS/check-refs.sh.
#
# Tiers
# -----
# GAP        (fails)   — a cited design reads `designed`, or carries a status
#                        that is none of the four the design README defines.
# ABANDONED  (reports) — a cited design reads `abandoned`. A spec may cite one
#                        to say why it does NOT build it; a human reads the
#                        citation.
# UNRESOLVED (reports) — the cited path does not exist in the hq repo. That is
#                        a broken reference, 05-TOOLS/check-refs.sh's business,
#                        not a status question; counted here so it is not
#                        mistaken for "fine".
# Cited designs reading `in-progress` or `implemented` are verified; a cited
# document with no frontmatter is an aggregate (a README or an overview that
# is framing and reading order — AGENTS.md says those carry none) and is not a
# contract with a status to check.
#
# Not in scope, on purpose: whether an `implemented` design is CORRECT — that
# is a review, not a check — and the reverse direction, a design marked
# `implemented` whose build never landed.
#
# Scope. HQ_CHECK_SCOPE=merge-request — set by CI on a merge-request
# pipeline — narrows what FAILS, never what is reported: a GAP on a design
# this branch edited fails, a GAP on any other design is deferred to the main
# and scheduled runs, which use the default fleet scope and fail on
# everything. The same reasoning as check-unclaimed's: a merge request should
# verify the merge request, and the status flip belongs to whoever is handing
# that design off.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

HQ_ROOT="${HQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HQ_REPO="${HQ_REPO:-$(basename "$HQ_ROOT")}"
# Siblings sit beside the *clone*. In a git worktree that is not the parent of
# HQ_ROOT, so ask git where the real repository is.
SIBLING_ROOT="${HQ_SIBLING_ROOT:-$(dirname "$(dirname "$(git -C "$HQ_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$HQ_ROOT/.git")")")}"
SCOPE="${HQ_CHECK_SCOPE:-fleet}"
GAPS=0; DEFERRED=0; ABANDONED=0; UNRESOLVED=0; VERIFIED=0; AGGREGATE=0; UNREADABLE=0

# ---------------------------------------------------------------------------
# --self-test: a throwaway hq repo (a clone with origin/main, so merge-request
# scope has something to diff against) holding one design per status plus an
# aggregate README, and one sibling whose specs cite them in every shape the
# fleet uses — bare path, hq-repo prefix, blob URL — plus a path that does
# not exist. Run in fleet scope, then in merge-request scope with the gapped
# design untouched and again with it edited on the branch.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  set -e
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  mkdir -p "$T/fleet"
  git init -q --bare "$T/fleet/hq.origin.git"
  git clone -q "$T/fleet/hq.origin.git" "$T/hq" 2>/dev/null
  git -C "$T/hq" checkout -q -b main
  mkdir -p "$T/hq/00-META" "$T/hq/02-DESIGN/01-foundation" "$T/hq/02-DESIGN/02-services/09-thing"
  printf '| Repository | Owns |\n|---|---|\n| `hq` | this repo |\n| `widget` | the sibling (project `thing`) |\n' > "$T/hq/00-META/repos.md"
  design() { printf -- '---\nstatus: %s\nupdated: 2026-01-01\n---\n# %s\n' "$2" "$1" > "$T/hq/02-DESIGN/$1"; }
  design 01-foundation/01-shipped.md designed
  design 01-foundation/02-building.md in-progress
  design 01-foundation/03-done.md implemented
  design 01-foundation/04-dropped.md abandoned
  design 02-services/09-thing/00-odd.md someday
  printf '# 09-thing\n\nReading order.\n' > "$T/hq/02-DESIGN/02-services/09-thing/README.md"
  git -C "$T/hq" add -A && git -C "$T/hq" commit -q -m "designs" && git -C "$T/hq" push -q origin main

  git init -q --bare "$T/fleet/thing.origin.git"
  git clone -q "$T/fleet/thing.origin.git" "$T/fleet/thing" 2>/dev/null
  git -C "$T/fleet/thing" checkout -q -b main
  mkdir -p "$T/fleet/thing/specs/001-first" "$T/fleet/thing/specs/002-second" "$T/fleet/thing/specs/003-third"
  cat > "$T/fleet/thing/specs/001-first/spec.md" <<'SPEC'
**Design source**: `hq/02-DESIGN/01-foundation/01-shipped.md` @ hq `abc1234`
See also 02-DESIGN/01-foundation/02-building.md and ../../hq/02-DESIGN/01-foundation/03-done.md.
SPEC
  cat > "$T/fleet/thing/specs/002-second/spec.md" <<'SPEC'
Why not: [the dropped design](https://forge.example.com/my-org/hq/blob/main/02-DESIGN/01-foundation/04-dropped.md).
Odd one: 02-DESIGN/02-services/09-thing/00-odd.md; aggregate: 02-DESIGN/02-services/09-thing/README.md.
SPEC
  cat > "$T/fleet/thing/specs/003-third/spec.md" <<'SPEC'
Cites 02-DESIGN/01-foundation/01-shipped.md again, and a path that moved: 02-DESIGN/01-foundation/99-gone.md.
SPEC
  printf 'plan-only citation of 02-DESIGN/01-foundation/04-dropped.md must not count\n' > "$T/fleet/thing/specs/001-first/plan.md"
  git -C "$T/fleet/thing" add -A && git -C "$T/fleet/thing" commit -q -m "specs" && git -C "$T/fleet/thing" push -q origin main

  run() { CI=false HQ_ROOT="$T/hq" HQ_SIBLING_ROOT="$T/fleet" NO_FETCH=1 HQ_CHECK_SCOPE="$1" bash "$SELF" 2>&1; }
  fails=0
  check() { # check <name> <expected exit> <expected line pattern> <output> <exit>
    if [ "$5" = "$2" ] && printf '%s\n' "$4" | grep -qE "$3"; then echo "PASS $1"
    else echo "FAIL $1 (exit $5, wanted $2; wanted /$3/)"; printf '%s\n' "$4" | sed 's/^/      /'; fails=$((fails+1)); fi
  }
  rc=0; out="$(run fleet)" || rc=$?
  check "a cited design still 'designed' is a GAP (fleet)"          1 "^GAP +02-DESIGN/01-foundation/01-shipped.md is 'designed'" "$out" $rc
  check "the GAP names the citing spec"                             1 'widget specs/001-first/spec.md' "$out" $rc
  n="$(printf '%s\n' "$out" | grep -cE "^GAP +02-DESIGN/01-foundation/01-shipped.md" || true)"
  if [ "$n" = 1 ]; then echo "PASS two specs citing one design is one GAP"; else echo "FAIL two specs citing one design is one GAP (saw $n)"; fails=$((fails+1)); fi
  check "an unknown status value is a GAP too"                      1 "^GAP +02-DESIGN/02-services/09-thing/00-odd.md is 'someday'" "$out" $rc
  check "an abandoned design is reported, not a gap"                1 "^ABANDONED +02-DESIGN/01-foundation/04-dropped.md" "$out" $rc
  check "a path that does not exist is UNRESOLVED (check-refs)"     1 '^UNRESOLVED +02-DESIGN/01-foundation/99-gone.md' "$out" $rc
  check "in-progress and implemented verify; the README is aggregate" 1 '2 verified, 1 aggregate' "$out" $rc
  check "the summary counts every tier"                             1 '^[0-9]+ cited design\(s\): 2 verified, 1 aggregate, 2 gap\(s\), 0 deferred, 1 abandoned, 1 unresolved$' "$out" $rc
  git -C "$T/hq" checkout -q -b branch
  echo tweak >> "$T/hq/02-DESIGN/01-foundation/03-done.md" && git -C "$T/hq" commit -qam "touch another design"
  rc=0; out="$(run merge-request)" || rc=$?
  check "untouched gaps are deferred (merge-request)"               0 "^GAP \(deferred\) +02-DESIGN/01-foundation/01-shipped.md" "$out" $rc
  echo tweak >> "$T/hq/02-DESIGN/01-foundation/01-shipped.md" && git -C "$T/hq" commit -qam "touch the gapped design"
  rc=0; out="$(run merge-request)" || rc=$?
  check "a gap on a design this branch edited still fails (merge-request)" 1 "^GAP +02-DESIGN/01-foundation/01-shipped.md is 'designed'" "$out" $rc
  [ "$fails" = 0 ] || { echo "SELF-TEST FAIL"; exit 1; }
  echo "SELF-TEST OK"
  exit 0
fi

if [ "${CI:-}" = "true" ]; then
  hq_require_group || exit 1
  hq_require_fleet_auth
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
fi

# Merge-request scope compares against origin/main, which a CI checkout of the
# source branch does not carry by default. Fetch it, and fail loud if that is
# impossible: guessing would defer a real gap.
TOUCHED=""
if [ "$SCOPE" = "merge-request" ]; then
  git -C "$HQ_ROOT" fetch --quiet origin main \
    || { echo "merge-request scope needs origin/main and could not fetch it"; exit 1; }
  TOUCHED="$(git -C "$HQ_ROOT" diff --name-only origin/main...HEAD -- 02-DESIGN/ | sort -u)"
fi
touched() { printf '%s\n' "$TOUCHED" | grep -qx -- "$1"; }

# "<logical> <slug>" per sibling, from repos.md (as 05-TOOLS/check-refs.sh reads it).
siblings() {
  awk -F'|' -v hq="$HQ_REPO" '
    /^\| `/ {
      name = $2; gsub(/[` ]/, "", name)
      if (name == hq) next
      slug = name
      if (match($3, /project `[a-z0-9-]+`/)) {
        slug = substr($3, RSTART, RLENGTH)
        sub(/.*project `/, "", slug); sub(/`$/, "", slug)
      }
      print name, slug
    }' "$HQ_ROOT/00-META/repos.md"
}

# Where to read a sibling from. Local: the clone beside this repo, already
# fetched by prefetch_siblings. CI: a shallow clone — only the tree at main is
# read, never history.
checkout_of() {
  local name="$1" slug="$2"
  if [ "${CI:-}" = "true" ]; then
    local dest="$WORKDIR/$slug"
    [ -d "$dest" ] && { printf '%s' "$dest"; return 0; }
    git clone --quiet --depth 1 --branch main \
      "$(hq_clone_url "$slug")" \
      "$dest" && printf '%s' "$dest"
  else
    local d
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    done
  fi
}

# Fetch every sibling concurrently before reading any (the check-claims
# argument: serial fetches turn a check nobody waits for into one nobody runs).
# Each fetch is bounded: twenty concurrent ssh sessions to one host is enough
# for one of them to stall, and one stalled fetch held the whole check for
# five minutes on its first run. A fetch that times out is reported and the
# run continues against origin/main as last fetched, like a fetch that fails.
FETCH_TIMEOUT=60
prefetch_siblings() {
  [ "${CI:-}" = "true" ] && return 0
  [ "${NO_FETCH:-}" = "1" ] && return 0
  local name slug d started=0
  while read -r name slug; do
    [ -n "$name" ] || continue
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] || continue
      timeout "$FETCH_TIMEOUT" git -C "$d" fetch --quiet origin main 2>/dev/null \
        || echo "  (could not fetch $name; using origin/main as last fetched)" &
      started=$((started + 1))
      break
    done
  done < <(siblings)
  [ "$started" -gt 0 ] && wait
}

# status_of <design path>: the frontmatter status, or "" when the document
# carries no frontmatter (an aggregate).
status_of() {
  awk 'NR==1 && !/^---$/ { exit } NR>1 && /^---$/ { exit } /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }' "$HQ_ROOT/$1"
}

echo "Checking that every design a sibling spec cites has moved past 'designed'..."
prefetch_siblings

# "<design path>\t<repo> <spec path>" per citation, from every sibling's
# specs/*/spec.md at origin/main. `git grep <ref>` reads the committed tree, so
# a stale or dirty working copy cannot affect the result.
citations=""
while read -r repo slug; do
  [ -n "$repo" ] || continue
  dir="$(checkout_of "$repo" "$slug")"
  if [ -z "$dir" ]; then
    echo "UNREADABLE $repo (project: $slug) — could not obtain a checkout"
    UNREADABLE=$((UNREADABLE + 1)); continue
  fi
  found="$(git -C "$dir" grep -oE '02-DESIGN/[A-Za-z0-9_./-]+\.md' origin/main -- 'specs/*/spec.md' 2>/dev/null \
             | sed "s|^origin/main:\([^:]*\):\(.*\)$|\2\t$repo \1|")"
  [ -n "$found" ] && citations="${citations}${found}"$'\n'
done < <(siblings)

designs="$(printf '%s' "$citations" | cut -f1 | grep . | sort -u)"
for design in $designs; do
  citers="$(printf '%s' "$citations" | awk -F'\t' -v d="$design" '$1 == d { print $2 }' | sort -u)"
  if [ ! -f "$HQ_ROOT/$design" ]; then
    echo "UNRESOLVED $design does not exist here — a broken reference (check-refs), cited by:"
    printf '%s\n' "$citers" | head -3 | sed 's/^/             /'
    UNRESOLVED=$((UNRESOLVED + 1)); continue
  fi
  status="$(status_of "$design")"
  case "$status" in
    "")                       AGGREGATE=$((AGGREGATE + 1)); continue ;;
    in-progress|implemented)  VERIFIED=$((VERIFIED + 1)); continue ;;
    abandoned)
      echo "ABANDONED  $design is 'abandoned' — cited by (a reason to not build it, or a spec that still does?):"
      printf '%s\n' "$citers" | head -3 | sed 's/^/             /'
      ABANDONED=$((ABANDONED + 1)); continue ;;
  esac
  if [ "$SCOPE" = "merge-request" ] && ! touched "$design"; then
    echo "GAP (deferred) $design is '$status' — its build has a spec; not a design this branch edited:"
    DEFERRED=$((DEFERRED + 1))
  else
    echo "GAP        $design is '$status' — its build has a spec on a code repo's main:"
    GAPS=$((GAPS + 1))
  fi
  printf '%s\n' "$citers" | head -3 | sed 's/^/             /'
done

total=$((VERIFIED + AGGREGATE + GAPS + DEFERRED + ABANDONED + UNRESOLVED))
echo "----"
echo "$total cited design(s): $VERIFIED verified, $AGGREGATE aggregate, $GAPS gap(s), $DEFERRED deferred, $ABANDONED abandoned, $UNRESOLVED unresolved"
if [ "$DEFERRED" -gt 0 ]; then
  echo "deferred gaps belong to designs this branch did not edit; the main and scheduled runs fail on them"
fi
if [ "$GAPS" -gt 0 ]; then
  echo
  echo "A gap means a code repo's spec cites a design that this repo still shows as"
  echo "never handed off. Move it (playbook 04): set code: to the owning repo(s) and"
  echo "status: in-progress at handoff (step 5), or status: implemented once the"
  echo "contract runs on the owning repo's main (step 7), with updated: today."
fi
if [ "$GAPS" -gt 0 ] || [ "$UNREADABLE" -gt 0 ]; then
  echo "FAIL"; exit 1
fi
echo "OK"

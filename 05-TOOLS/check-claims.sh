#!/usr/bin/env bash
#
# 05-TOOLS/check-claims.sh — an hq document that says work is done must be able
# to prove it.
#
# Issue reports carry `fixed-by:` and `lands:`; design docs carry `lands:`.
# Those fields are what close an issue and flip a design to implemented, and
# nothing verifies them. GitLab stamps every merge commit with
#
#     See merge request <group>/<repo>!<n>
#
# so "did !33 actually merge?" is a `git log --grep` on that repo's main. No
# API and no `api` scope are needed — the read-only deploy token already used
# by 05-TOOLS/check-refs.sh is enough.
#
# Usage:
#   ./05-TOOLS/check-claims.sh             # local: expects sibling clones beside this repo
#   ./05-TOOLS/check-claims.sh --only 054  # one issue (number or id): reads that record
#                                          # only and fetches only the repos it names
#   NO_FETCH=1 ./05-TOOLS/check-claims.sh  # local, offline: use origin/main as last fetched
#   CI=true ./05-TOOLS/check-claims.sh     # CI: clones the repos it needs
#
# --only is what 05-TOOLS/set-issue.sh runs before it lets a close land on
# main: seconds against the record's own repos, not the fleet-wide fetch.
#
# CI variables: HQ_FLEET_USER / HQ_FLEET_TOKEN, as for 05-TOOLS/check-refs.sh.
#
# Siblings are read at origin/main and **fetched first**, concurrently, as
# 05-TOOLS/check-refs.sh does serially.
# Reading origin/main is not on its own enough: an unfetched clone's
# origin/main is whatever it was when someone last pulled, so a reference that
# merged this morning reads as a FALSE CLAIM on a machine that has not fetched
# since. That is the failure mode this whole file exists to avoid — a checker
# that cries wolf gets ignored, and then the real false claim goes through.
#
# What it can and cannot prove
# ----------------------------
# A merge commit proves an MR merged. Nothing here can distinguish "not merged
# yet, legitimately" from "never merged", so the rule is one-directional:
#
#   * A document claiming completion (issue `status: resolved`, design
#     `status: implemented`) must have every reference it names be present on
#     that repo's main. A reference that is not is a FALSE CLAIM and fails.
#   * Any other status: references are informational. An open MR is expected.
#
# Reference kinds, each verifiable against git:
#   mr: "!N"        a merge commit carrying GitLab's "See merge request …!N"
#   commit: <sha>   an ancestor of origin/main (used where a merge carries no
#                   MR trailer)
#   tag: vX.Y.Z     a tag resolving to a commit on main
#   action: <kind>  deliberately OUT OF SCOPE — an operational act such as a
#                   deploy reconcile. It happened outside git, so no git check
#                   can attest to it. Reported separately, never counted as a
#                   gap, because a permanently nonzero gap trains people to
#                   ignore the number.

set -uo pipefail

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:?--only needs an issue}"; shift ;;
    -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

HQ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Siblings sit beside the *clone*. In a git worktree that is not the parent of
# HQ_ROOT, so ask git where the real repository is.
SIBLING_ROOT="$(dirname "$(dirname "$(git -C "$HQ_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$HQ_ROOT/.git")")")"
GROUP_PATH="${HQ_GROUP_PATH}"
GROUP_URL="https://${HQ_FORGE_HOST}/${GROUP_PATH}"
FALSE=0
UNREADABLE=0
OUTOFSCOPE=0
VERIFIED=0

if [ "${CI:-}" = "true" ]; then
  hq_require_group || exit 1
  : "${HQ_FLEET_USER:?HQ_FLEET_USER must be set in CI}"
  : "${HQ_FLEET_TOKEN:?HQ_FLEET_TOKEN must be set in CI}"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
fi

# Logical name -> gitlab slug, from the note repos.md carries.
slug_of() {
  awk -F'|' -v want="$1" '
    /^\| `/ {
      name = $2; gsub(/[` ]/, "", name)
      if (name != want) next
      slug = name
      if (match($3, /gitlab project `[a-z0-9-]+`/)) {
        slug = substr($3, RSTART, RLENGTH)
        sub(/gitlab project `/, "", slug); sub(/`$/, "", slug)
      }
      print slug; exit
    }' "$HQ_ROOT/00-META/repos.md"
}

# A checkout with history — `git log` needs it, so no --depth 1 here.
checkout_of() {
  local name="$1" slug
  slug="$(slug_of "$name")"
  [ -n "$slug" ] || return 1
  if [ "${CI:-}" = "true" ]; then
    local dest="$WORKDIR/$slug"
    [ -d "$dest" ] && { printf '%s' "$dest"; return 0; }
    git clone --quiet --branch main \
      "https://${HQ_FLEET_USER}:${HQ_FLEET_TOKEN}@${GROUP_URL#https://}/${slug}.git" \
      "$dest" && printf '%s' "$dest"
  else
    local d
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] || continue
      if [ "${NO_FETCH:-}" != "1" ] && [ "${PREFETCHED:-}" != "1" ]; then
        git -C "$d" fetch --quiet origin main 2>/dev/null \
          || echo "  (could not fetch $name; using origin/main as last fetched)"
      fi
      printf '%s' "$d"; return 0
    done
  fi
}

# Fetch every sibling the run will read, concurrently, before reading any of
# them. Fetching lazily inside checkout_of is correct but serial, and these
# fetches are network-bound and independent: ~20 repos took 91s that way against
# 3s with NO_FETCH=1, and a check nobody waits for is a check nobody runs.
#
# Sets PREFETCHED so checkout_of does not fetch a second time. A repo that fails
# here still reports through the same path it always did — the fetch is
# best-effort and the run continues against origin/main as last fetched.
prefetch_siblings() {
  [ "${CI:-}" = "true" ] && return 0        # CI clones fresh; there is nothing to fetch
  [ "${NO_FETCH:-}" = "1" ] && return 0

  local docs="$1" name slug d started=0
  [ -n "$docs" ] || return 0                # nothing claims completion; grep would read stdin
  # Over-fetching costs a little time; under-fetching costs correctness. Take
  # every repo: named anywhere in a claiming doc and let slug_of drop what is
  # not a real repo.
  local names
  # $docs is a newline-separated path list and must split into arguments here,
  # exactly as the `for doc in $docs` below relies on. No hq path contains
  # a space.
  # shellcheck disable=SC2086
  names="$(grep -hoE 'repo:[[:space:]]*[a-z0-9-]+' $docs 2>/dev/null \
             | sed 's/repo:[[:space:]]*//' | sort -u)"

  for name in $names; do
    slug="$(slug_of "$name")"
    [ -n "$slug" ] || continue
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] || continue
      git -C "$d" fetch --quiet origin main 2>/dev/null \
        || echo "  (could not fetch $name; using origin/main as last fetched)" &
      started=$((started + 1))
      break
    done
  done

  [ "$started" -gt 0 ] && wait
  PREFETCHED=1
}

# Does <repo>!<n> have a merge commit on main? The trailer names the project
# PATH at the time of the merge, so a renamed project's older merges carry its
# former name: a repos.md row that keeps that former name (its note pointing
# the gitlab project at the new slug) is matched on either.
merged() {
  local dir="$1" slug="$2" num="$3" name="${4:-$2}"
  git -C "$dir" log origin/main --merges \
      --grep="See merge request ${GROUP_PATH}/${slug}!${num}\$" \
      --grep="See merge request ${GROUP_PATH}/${name}!${num}\$" \
      --format=%h -1 2>/dev/null | grep -q .
}

echo "Checking completion claims in hq documents that say work is done..."

# Every doc whose frontmatter claims completion — or, with --only, just that
# issue's report (a record that does not claim completion checks as empty).
if [ -n "$ONLY" ]; then
  case "$ONLY" in
    ''|*[!0-9]*) only_dir="$(cd "$HQ_ROOT/04-ISSUES" && ls -d "$ONLY"/ 2>/dev/null | sed 's#/$##')" ;;
    *) only_dir="$(cd "$HQ_ROOT/04-ISSUES" && ls -d "$(printf '%03d' "$((10#$ONLY))")"-*/ 2>/dev/null | head -1 | sed 's#/$##')" ;;
  esac
  [ -n "$only_dir" ] || { echo "no issue matching '$ONLY' under 04-ISSUES" >&2; exit 2; }
  docs="$(grep -lE '^status: (resolved|implemented)$' "$HQ_ROOT/04-ISSUES/$only_dir/00-report.md" 2>/dev/null)"
else
  docs="$(grep -rlE '^status: (resolved|implemented)$' \
            --include='*.md' "$HQ_ROOT/04-ISSUES" "$HQ_ROOT/02-DESIGN" 2>/dev/null)"
fi

prefetch_siblings "$docs"

for doc in $docs; do
  rel="${doc#$HQ_ROOT/}"
  # Emit "<repo> <kind> <value>" per reference, from the frontmatter only.
  # Handles both shapes:
  #   - { repo: x, mr: "!n", after: [] }        (lands:, inline)
  #   - repo: x / mr: "!n" / note: "..."        (fixed-by:, block)
  refs="$(awk '
    NR==1 && /^---$/ { fm=1; next }
    fm && /^---$/    { exit }
    !fm              { next }
    /^(fixed-by|lands):/ { inblock=1; repo=""; next }
    /^[a-z][a-z-]*:/     { inblock=0; repo="" }
    !inblock { next }
    {
      line=$0
      if (match(line, /repo:[[:space:]]*[a-z0-9-]+/)) {
        r=substr(line, RSTART, RLENGTH); sub(/repo:[[:space:]]*/, "", r); repo=r
      }
      if (repo == "") next
      if (match(line, /mr:[[:space:]]*"?!?[0-9]+/)) {
        v=substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", v)
        if (v != "") print repo, "mr", v
      }
      else if (match(line, /commit:[[:space:]]*[0-9a-f]{7,40}/)) {
        v=substr(line, RSTART, RLENGTH); sub(/commit:[[:space:]]*/, "", v)
        print repo, "commit", v
      }
      else if (match(line, /tag:[[:space:]]*[A-Za-z0-9._-]+/)) {
        v=substr(line, RSTART, RLENGTH); sub(/tag:[[:space:]]*/, "", v)
        print repo, "tag", v
      }
      else if (match(line, /action:[[:space:]]*[a-z-]+/)) {
        v=substr(line, RSTART, RLENGTH); sub(/action:[[:space:]]*/, "", v)
        print repo, "action", v
      }
    }' "$doc" | sort -u)"
  [ -n "$refs" ] || continue

  while read -r repo kind value; do
    [ -n "$repo" ] || continue
    if [ "$kind" = "action" ]; then
      OUTOFSCOPE=$((OUTOFSCOPE + 1)); continue
    fi
    slug="$(slug_of "$repo")"
    if [ -z "$slug" ]; then
      echo "FALSE CLAIM   $rel — '$repo' is not in repos.md"
      FALSE=$((FALSE + 1)); continue
    fi
    dir="$(checkout_of "$repo")"
    if [ -z "$dir" ]; then
      echo "UNREADABLE    $rel — cannot read $repo ($slug) to verify $kind $value"
      UNREADABLE=$((UNREADABLE + 1)); continue
    fi
    ok=1
    case "$kind" in
      mr)
        # The trailer names the project PATH at merge time; a renamed project's
        # older merges carry its former name, kept as its own repos.md row.
        git -C "$dir" log origin/main --merges \
            --grep="See merge request ${GROUP_PATH}/${slug}!${value}\$" \
            --grep="See merge request ${GROUP_PATH}/${repo}!${value}\$" \
            --format=%h -1 2>/dev/null | grep -q . || ok=0 ;;
      commit)
        git -C "$dir" merge-base --is-ancestor "$value" origin/main 2>/dev/null || ok=0 ;;
      tag)
        sha="$(git -C "$dir" rev-parse -q --verify "${value}^{commit}" 2>/dev/null)"
        [ -n "$sha" ] && git -C "$dir" merge-base --is-ancestor "$sha" origin/main 2>/dev/null || ok=0 ;;
    esac
    if [ "$ok" = 1 ]; then
      VERIFIED=$((VERIFIED + 1))
    else
      echo "FALSE CLAIM   $rel — claims $repo $kind $value, not present on $slug main"
      FALSE=$((FALSE + 1))
    fi
  done <<< "$refs"
done

echo "----"
echo "verified $VERIFIED reference(s); $FALSE false, $UNREADABLE unreadable, $OUTOFSCOPE out-of-scope (operational)"

if [ "$FALSE" -gt 0 ] || [ "$UNREADABLE" -gt 0 ]; then
  echo "FAIL"
  exit 1
fi
echo "OK"

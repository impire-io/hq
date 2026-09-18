#!/usr/bin/env bash
#
# 05-TOOLS/check-refs.sh — verify every cross-repo reference into the hq repo
# still resolves.
#
# Sibling repos link hq documents by relative path (../<hq-repo>/<path>).
# Those links break silently whenever the hq repo moves a file. Nothing in a
# sibling's own CI can catch it — in CI the sibling is cloned alone and
# ../<hq-repo>/ does not exist. The break is caused by an hq rename, so the
# check belongs here.
#
# Usage:
#   ./05-TOOLS/check-refs.sh              # local: expects sibling clones beside this repo
#   NO_FETCH=1 ./05-TOOLS/check-refs.sh   # local, offline: use origin/main as last fetched
#   CI=true ./05-TOOLS/check-refs.sh      # CI: clones siblings from origin
#
# Siblings are read at **origin/main**, never from their working tree. A local
# clone is routinely some commits behind, and grepping its checked-out files
# reports breakage that does not exist on main — which is how a checker earns
# the right to be ignored. The hq repo itself is read from the working tree,
# because the question is whether it *as it stands here* orphans a reference
# that exists on sibling main.
#
# In CI, set (Settings -> CI/CD -> Variables):
#   HQ_FLEET_USER    the deploy token's username
#   HQ_FLEET_TOKEN   the deploy token secret (Masked, Protected)
#
# Use a *group deploy token* on the fleet's GitLab group with the
# `read_repository` scope — not a group access token. A deploy token has no
# `api` scope at all, so it cannot read issues, merge requests, or anything
# beyond repository contents, which is exactly this script's need. It also
# authenticates as its own username rather than `oauth2`.
#
# Exits non-zero on a broken reference OR on a sibling it could not read.
# An unreadable sibling is a failure, never a skip: silence must not look
# like success — that is the exact failure mode this script exists to end.
#
# Scope. HQ_CHECK_SCOPE=merge-request — set by CI on a merge-request
# pipeline — narrows what FAILS, never what is reported: a reference whose
# target is missing here but present on origin/main was broken by this branch
# and fails; one missing on origin/main too is fleet drift that predates the
# branch, reported as DRIFT and left to the main and scheduled runs, which use
# the default fleet scope and fail on everything.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

HQ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HQ_REPO="${HQ_REPO:-$(basename "$HQ_ROOT")}"
# Siblings sit beside the *clone*. In a git worktree that is not the parent of
# HQ_ROOT, so ask git where the real repository is.
SIBLING_ROOT="$(dirname "$(dirname "$(git -C "$HQ_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$HQ_ROOT/.git")")")"
GROUP_URL="https://${HQ_FORGE_HOST}/${HQ_GROUP_PATH}"
BROKEN=0
DRIFT=0
UNREADABLE=0
CHECKED=0
SCOPE="${HQ_CHECK_SCOPE:-fleet}"

# Merge-request scope compares against origin/main, which a CI checkout of the
# source branch does not carry by default. Fetch it, and fail loud if that is
# impossible: guessing would turn a real break into "drift".
if [ "$SCOPE" = "merge-request" ]; then
  git -C "$HQ_ROOT" fetch --quiet origin main \
    || { echo "merge-request scope needs origin/main and could not fetch it"; exit 1; }
fi

# missing_on_main <path>: true when this repo's origin/main has no such file
# either, i.e. this branch did not remove it.
missing_on_main() {
  ! git -C "$HQ_ROOT" cat-file -e "origin/main:$1" 2>/dev/null
}

# The repo map is the source of truth for which siblings exist. Its first
# column is the *logical* name, which is not always the GitLab project slug —
# repos.md records the difference as "(gitlab project `x`)". Emits
# "<logical> <slug>" per line.
siblings() {
  awk -F'|' -v hq="$HQ_REPO" '
    /^\| `/ {
      name = $2; gsub(/[` ]/, "", name)
      if (name == hq) next
      slug = name
      if (match($3, /gitlab project `[a-z0-9-]+`/)) {
        slug = substr($3, RSTART, RLENGTH)
        sub(/gitlab project `/, "", slug); sub(/`$/, "", slug)
      }
      print name, slug
    }' "$HQ_ROOT/00-META/repos.md"
}

# Where to read a sibling from. Local: the clone beside this repo. CI: a shallow
# clone into $WORKDIR. Prints the path, or nothing if unavailable.
checkout_of() {
  local name="$1" slug="$2"
  if [ "${CI:-}" = "true" ]; then
    local dest="$WORKDIR/$slug"
    [ -d "$dest" ] && { printf '%s' "$dest"; return 0; }
    git clone --quiet --depth 1 --branch main \
      "https://${HQ_FLEET_USER}:${HQ_FLEET_TOKEN}@${GROUP_URL#https://}/${slug}.git" \
      "$dest" && printf '%s' "$dest"
  else
    # A local clone may be named after either the logical name or the slug.
    # -e not -d: in a git worktree, .git is a file, not a directory.
    local d
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] || continue
      if [ "${NO_FETCH:-}" != "1" ]; then
        git -C "$d" fetch --quiet origin main 2>/dev/null \
          || echo "  (could not fetch $name; using origin/main as last fetched)"
      fi
      printf '%s' "$d"; return 0
    done
  fi
}

if [ "${CI:-}" = "true" ]; then
  hq_require_group || exit 1
  : "${HQ_FLEET_USER:?HQ_FLEET_USER must be set in CI (see header)}"
  : "${HQ_FLEET_TOKEN:?HQ_FLEET_TOKEN must be set in CI (see header)}"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
fi

echo "Checking cross-repo references into $HQ_REPO..."

while read -r repo slug; do
  [ -n "$repo" ] || continue
  dir="$(checkout_of "$repo" "$slug")"
  if [ -z "$dir" ]; then
    echo "UNREADABLE  $repo (gitlab: $slug) — could not obtain a checkout"
    UNREADABLE=$((UNREADABLE + 1))
    continue
  fi

  # Relative markdown links only.
  #  - Bare prose mentions are records of what was said, not navigable links;
  #    rewriting them would alter the record.
  #  - Full https:// URLs into the hq repo are deliberately out of scope: they are
  #    resolved by GitLab, not by the filesystem, and a path-based check
  #    reports every one of them as broken (36 false positives when tried).
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    target="${hit##*"$HQ_REPO"/}"
    target="${target%%)*}"
    CHECKED=$((CHECKED + 1))
    if [ ! -e "$HQ_ROOT/$target" ]; then
      if [ "$SCOPE" = "merge-request" ] && missing_on_main "$target"; then
        echo "DRIFT       $repo  $file:$line  -> $HQ_REPO/$target   (missing on main too — not this branch's doing)"
        DRIFT=$((DRIFT + 1))
      else
        echo "BROKEN      $repo  $file:$line  -> $HQ_REPO/$target"
        BROKEN=$((BROKEN + 1))
      fi
    fi
  # `git grep <ref>` reads the committed tree, so no checkout is involved and a
  # stale or dirty working copy cannot affect the result. It also makes nested
  # worktrees a non-issue: they are not part of the ref.
  done < <(git -C "$dir" grep -noE \
             -e '\]\((\.\./)+'"$HQ_REPO"'/[A-Za-z0-9/._-]*\.md\)' \
             origin/main -- '*.md' \
           | sed 's|^origin/main:||')
done < <(siblings)

echo "----"
echo "checked $CHECKED reference(s); $BROKEN broken, $DRIFT drift, $UNREADABLE unreadable sibling(s)"
if [ "$DRIFT" -gt 0 ]; then
  echo "drift predates this branch: the main and scheduled runs fail on it, this merge request does not"
fi

if [ "$BROKEN" -gt 0 ] || [ "$UNREADABLE" -gt 0 ]; then
  echo "FAIL"
  exit 1
fi
echo "OK"

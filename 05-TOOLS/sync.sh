#!/usr/bin/env bash
#
# 05-TOOLS/sync.sh — bring the fleet up to date: clone what is missing,
# fast-forward what is clean, leave everything else alone.
#
# Run it whenever you want the fleet current. Setting up a machine is simply the
# case where everything is missing — there is no separate first-run mode and no
# state kept between runs, so there is never a wrong moment to run it.
#
# Discovers the repositories from the GitLab group (HQ_GROUP_PATH on
# HQ_FORGE_HOST, from 05-TOOLS/config.sh) rather than from a list kept in this
# file, so a repo added to the group is picked up on the next run with no edit
# here. Existing clones are matched on their `origin` URL rather than on their
# directory name, so a locally renamed clone is recognised instead of cloned a
# second time.
#
# Subgroups are included, and the subgroup path is mirrored on disk:
# `<group>/<subgroup>/<repo>` clones to `<root>/<subgroup>/<repo>`. Mirroring
# rather than flattening is not a matter of taste — a project slug is unique
# only within its own group, so a flat root cannot hold two projects that
# share a slug across subgroups.
#
# It only ever fast-forwards, and only a clean clone sitting on its default
# branch. A dirty tree or a work branch is fetched and then left exactly as it
# was: this script must be safe to run in a fleet where other people's — and
# other agents' — work is in progress. It never resets, checks out, or stashes,
# and it never installs anything on your machine.
#
# Usage:
#   ./05-TOOLS/sync.sh [--root <dir>] [--dry-run]
#
#   --root     the directory holding the clones. Defaults to the parent of this
#              hq clone, which is the layout playbook 07 assumes.
#   --dry-run  print what would happen, touch nothing.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
GROUP="${HQ_GROUP_PATH}"
HOST="${HQ_FORGE_HOST}"

ROOT=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:-}"; [ -n "$ROOT" ] || { echo "--root needs a directory" >&2; exit 2; }; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)         echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

hq_require_group || exit 1

# Derived from git rather than from this script's own path, because the script
# may be run from inside a worktree (`.work/<id>/<hq-repo>`), where walking up
# one level lands in the workspace instead of the fleet root. --git-common-dir
# points at the main clone's .git from any worktree of it.
if [ -z "$ROOT" ]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  COMMON_GIT="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -z "$COMMON_GIT" ]; then
    echo "cannot locate the hq clone from $HERE; pass --root explicitly" >&2
    exit 2
  fi
  ROOT="$(cd "$(dirname "$COMMON_GIT")/.." && pwd)"
fi

# Reports read the same in both modes bar the tense, so a dry run says what a
# real run would do rather than claiming it already did it.
if [ "$DRY_RUN" -eq 1 ]; then
  V_CLONE="would clone"; V_FF="would fast-forward"
else
  V_CLONE="cloning"; V_FF="fast-forwarded"
fi

run() {
  [ "$DRY_RUN" -eq 1 ] || "$@"
}

# ---------------------------------------------------------------- preflight --
#
# Reports what is missing and how to fix it. Installs nothing: what lands on a
# developer's machine is their call, not this script's.

missing=0
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  ! $1 not found — $2" >&2
  missing=1
}

echo "checking prerequisites"
need git  "install Xcode command line tools, or: brew install git"
need glab "brew install glab"
need jq   "brew install jq"

if [ "$missing" -eq 0 ]; then
  if ! glab auth status >/dev/null 2>&1; then
    echo "  ! glab is not authenticated — glab auth login --hostname $HOST" >&2
    missing=1
  fi

  # GitLab answers a successful key with "Welcome to GitLab, @user!". BatchMode
  # keeps a missing key from hanging on a password prompt.
  ssh_out="$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 "git@$HOST" 2>&1 || true)"
  case "$ssh_out" in
    *"Welcome to GitLab"*) ;;
    *)
      echo "  ! no SSH access to $HOST — add your public key to GitLab:" >&2
      echo "      https://$HOST/-/user_settings/ssh_keys" >&2
      echo "    ssh said: ${ssh_out%%$'\n'*}" >&2
      missing=1
      ;;
  esac
fi

if [ "$missing" -ne 0 ]; then
  echo "prerequisites missing; nothing was changed" >&2
  exit 1
fi

# ----------------------------------------------------------------- discover --

echo "discovering repositories in $GROUP"

# --include-subgroups, because without it the API returns only projects sitting
# directly in the group and every repo under a subgroup is silently absent — the
# report then reads like a complete fleet.
#
# --member, because glab's default listing is repos the caller OWNS: for
# every engineer who is a member (not owner) of the group, discovery came
# back empty and the sync refused to continue.
#
# The name is the path *relative to the group* (`<subgroup>/<repo>`),
# not the bare project slug: the slug alone is ambiguous across subgroups, and
# this relative path is exactly the directory layout under the root.
DISCOVERED="$(glab repo list --group "$GROUP" --include-subgroups --per-page 100 --archived=false --output json --member \
  | jq -r --arg g "$GROUP/" '.[] | [(.path_with_namespace | ltrimstr($g)), .ssh_url_to_repo] | @tsv' | sort)"

if [ -z "$DISCOVERED" ]; then
  echo "the group returned no repositories; refusing to continue" >&2
  exit 1
fi
echo "  $(printf '%s\n' "$DISCOVERED" | wc -l | tr -d ' ') repositories"

# Every ancestor directory implied by a discovered path — `<subgroup>` for
# `<subgroup>/<repo>`. These are the only directories under the
# root the local scan is allowed to descend into.
SUBGROUP_DIRS="$(printf '%s\n' "$DISCOVERED" | cut -f1 \
  | awk -F/ '{ p = ""; for (i = 1; i < NF; i++) { p = (p == "" ? $i : p "/" $i); print p } }' | sort -u)"

# ------------------------------------------------------------------- index ---
#
# Match on remote identity, not on directory name. Both URL forms reduce to
# `host/group/subgroup/repo`, so an ssh clone and an https clone of the same
# project compare equal.

normalize() {
  printf '%s' "$1" \
    | sed -e 's#^ssh://##' -e 's#^git+ssh://##' -e 's#^https\{0,1\}://##' \
          -e 's#^[^@/]*@##' -e 's#:#/#' -e 's#\.git$##' -e 's#/$##' \
    | tr '[:upper:]' '[:lower:]'
}

# Indexed by path relative to the root, so a clone inside a mirrored subgroup
# directory is found rather than cloned a second time at the top level.
LOCAL_INDEX=""

index_dir() {
  local base="$1" rel="$2"
  local path dir child url

  for path in "$base"/*/; do
    [ -d "$path" ] || continue
    dir="$(basename "$path")"
    child="${rel:+$rel/}$dir"
    [ "$child" = ".work" ] && continue

    url="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ]; then
      LOCAL_INDEX="${LOCAL_INDEX}$(normalize "$url")	${child}
"
      continue
    fi

    # Not a clone. Descend only where the group says a subgroup lives; anything
    # else under the root is someone's own directory and is not ours to walk.
    if printf '%s\n' "$SUBGROUP_DIRS" | grep -qx -- "$child"; then
      index_dir "${path%/}" "$child"
    fi
  done
}

index_dir "$ROOT" ""

lookup() {
  [ -n "$LOCAL_INDEX" ] || return 0
  printf '%s' "$LOCAL_INDEX" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'
}

# -------------------------------------------------------------------- work ---

cloned=0; updated=0; current=0; skipped=0; failed=0
matched_dirs=""

# A subgroup path is far longer than a bare slug, so the name column is sized to
# the run rather than pinned to a constant that a nested repo overflows.
WIDTH=20
for s in $(printf '%s\n' "$DISCOVERED" | cut -f1; printf '%s' "$LOCAL_INDEX" | cut -f2); do
  [ ${#s} -gt "$WIDTH" ] && WIDTH=${#s}
done

echo
echo "root: $ROOT"

while IFS=$'\t' read -r name url; do
  [ -n "$name" ] || continue
  dir="$(lookup "$(normalize "$url")")"

  if [ -z "$dir" ]; then
    printf '  %-*s %s\n' "$WIDTH" "$name" "$V_CLONE"
    if run git clone --quiet "$url" "$ROOT/$name"; then
      run git -C "$ROOT/$name" remote set-head origin -a >/dev/null 2>&1 || true
      cloned=$((cloned + 1))
    else
      printf '  %-*s ! clone failed\n' "$WIDTH" "$name" >&2
      failed=$((failed + 1))
    fi
    continue
  fi

  matched_dirs="${matched_dirs}${dir}
"
  repo="$ROOT/$dir"
  label="$name"
  [ "$dir" = "$name" ] || label="$name -> $dir"

  if ! git -C "$repo" fetch --quiet --prune origin 2>/dev/null; then
    printf '  %-*s ! fetch failed\n' "$WIDTH" "$label" >&2
    failed=$((failed + 1))
    continue
  fi

  # A repository with no commits — created upstream, never pushed to. It reaches
  # this loop like any other, and the plumbing below does not survive an unborn
  # HEAD: `rev-parse --abbrev-ref HEAD` prints `HEAD` *and* exits non-zero, so
  # the `|| echo HEAD` fallback yields two lines and breaks the report, and the
  # unguarded `rev-parse HEAD` further down aborts the whole run under `set -e`.
  # Reported and skipped instead.
  if ! git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    printf '  %-*s fetched; no commits upstream yet, left alone\n' "$WIDTH" "$label"
    skipped=$((skipped + 1))
    continue
  fi

  # The default branch is whatever origin says it is; do not assume `main`.
  head_ref="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -z "$head_ref" ]; then
    git -C "$repo" remote set-head origin -a >/dev/null 2>&1 || true
    head_ref="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  fi
  default="${head_ref##*/origin/}"
  [ -n "$default" ] || default="main"

  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  if [ "$branch" != "$default" ]; then
    printf '  %-*s fetched; on branch %s, left alone\n' "$WIDTH" "$label" "$branch"
    skipped=$((skipped + 1))
    continue
  fi

  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    printf '  %-*s fetched; local changes, left alone\n' "$WIDTH" "$label"
    skipped=$((skipped + 1))
    continue
  fi

  local_sha="$(git -C "$repo" rev-parse HEAD)"
  remote_sha="$(git -C "$repo" rev-parse "origin/$default" 2>/dev/null || echo "$local_sha")"
  if [ "$local_sha" = "$remote_sha" ]; then
    printf '  %-*s up to date\n' "$WIDTH" "$label"
    current=$((current + 1))
  elif run git -C "$repo" merge --quiet --ff-only "origin/$default"; then
    printf '  %-*s %s %s\n' "$WIDTH" "$label" "$V_FF" "$default"
    updated=$((updated + 1))
  else
    printf '  %-*s ! cannot fast-forward %s, left alone\n' "$WIDTH" "$label" "$default" >&2
    failed=$((failed + 1))
  fi
done <<< "$DISCOVERED"

# Directories under the root that carry an origin nobody in the group claims —
# a fork, an archived project, something personal. Reported, never touched.
while IFS=$'\t' read -r _ dir; do
  [ -n "$dir" ] || continue
  printf '%s' "$matched_dirs" | grep -qx -- "$dir" && continue
  printf '  %-*s unknown remote, ignored\n' "$WIDTH" "$dir"
done <<< "$LOCAL_INDEX"

# ----------------------------------------------------------------- summary ---

echo
echo "cloned $cloned, fast-forwarded $updated, up to date $current, left alone $skipped, failed $failed"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run: nothing was changed"
fi

[ "$failed" -eq 0 ] || exit 1

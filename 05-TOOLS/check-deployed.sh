#!/usr/bin/env bash
#
# 05-TOOLS/check-deployed.sh — what the install runs, against what has been released.
#
# The four checks beside this one — check-refs, check-numbers, check-claims,
# check-unclaimed — all reason about git. None reasons about what is DEPLOYED,
# so an install can fall arbitrarily far behind main with every check green.
# 05-TOOLS/check-claims.sh is explicit that this is outside its reach: an
# `action:` reference "happened outside git, so no git check can attest to it".
# Right — but the install's pins are in git. The deploy repo names the
# image tag every service runs, and every repo's release is a tag on its main.
# Comparing the two is this check.
#
# This check is OPTIONAL and Helm-shaped: it assumes a deploy repo carrying a
# values file with per-service `image: { tag: … }` pins and, optionally, an
# umbrella chart repo. A project with that shape configures it through the
# HQ_DEPLOY_* variables below (put them in 05-TOOLS/config.sh); one without
# it leaves them empty, and the check reports "not configured" and exits 0.
#
# Usage:
#   ./05-TOOLS/check-deployed.sh             # local: expects sibling clones beside this repo
#   NO_FETCH=1 ./05-TOOLS/check-deployed.sh  # local, offline: origin/main and tags as last fetched
#   CI=true ./05-TOOLS/check-deployed.sh     # CI: clones the repos it needs
#   ./05-TOOLS/check-deployed.sh --self-test # exercise every tier against a throwaway fleet
#
# CI variables: HQ_FLEET_USER / HQ_FLEET_TOKEN, as for 05-TOOLS/check-refs.sh.
#
# What it reads
# -------------
# The deploy repo (HQ_DEPLOY_REPO) at origin/main: every top-level values key
# carrying an `image: { tag: … }` in the values file (HQ_DEPLOY_VALUES), and
# the umbrella chart version in HQ_DEPLOY_VERSIONS. A values key maps to a
# repo by name; an instance key (`mcp-adapter-docs`) maps by the longest
# prefix that is a repo in 00-META/repos.md. Each repo is read at origin/main
# WITH ITS TAGS — a `fetch origin main` alone auto-follows only the tags it
# happens to reach, and a pin that reads UNKNOWN because the clone never saw
# the tag is exactly the false alarm that gets a check ignored.
#
# Two failures, reported per service, because they need different fixes
# ---------------------------------------------------------------------
# BEHIND      — the pinned tag is older than the newest release tag. Released
#               but not deployed: bump the pin.
# UNRELEASED  — the repo's origin/main is past its newest tag. Merged but not
#               released: there is no image to deploy even if someone tried.
#               Reported alongside whatever the pin's own tier is.
# UNKNOWN     — the pin names a tag the repo does not have: the ImagePullBackOff
#               case the values file already warns about in prose.
# CURRENT     — the pin is the newest release. Main may still be UNRELEASED.
#
# A release is a tag of the form v1.2.3 or 1.2.3; pre-release tags
# (v0.1.0-rc1) never count as the newest release, because `sort -V` orders
# them AFTER the release they precede.
#
# It reports and does not fail. An install is allowed to lag deliberately — a
# staged subchart, a release held back for a sequenced rollout — and a check
# that fails on every intentional lag teaches people to ignore it, the same
# reasoning 05-TOOLS/check-claims.sh applies to its operational count. The exit
# code is nonzero only when the check could not do its job: a repo it could
# not read, or a values key it could not map to a repo (repos.md is this
# repo's own record, so that one IS this repo's to fix).

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

HQ_ROOT="${HQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Siblings sit beside the *clone*. In a git worktree that is not the parent of
# HQ_ROOT, so ask git where the real repository is.
SIBLING_ROOT="${HQ_SIBLING_ROOT:-$(dirname "$(dirname "$(git -C "$HQ_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$HQ_ROOT/.git")")")}"
GROUP_PATH="${HQ_GROUP_PATH}"
GROUP_URL="https://${HQ_FORGE_HOST}/${GROUP_PATH}"

# Empty by default: a project that deploys this way sets them in config.sh.
DEPLOY_REPO="${HQ_DEPLOY_REPO:-}"
VALUES_FILE="${HQ_DEPLOY_VALUES:-}"
VERSIONS_FILE="${HQ_DEPLOY_VERSIONS:-}"
UMBRELLA_REPO="${HQ_UMBRELLA_REPO:-}"
UMBRELLA_CHART="${HQ_UMBRELLA_CHART:-}"

CURRENT=0; BEHIND=0; UNRELEASED=0; UNKNOWN=0; UNMAPPED=0; UNREADABLE=0

# ---------------------------------------------------------------------------
# --self-test: a throwaway fleet — a deploy repo, an umbrella repo and four
# service repos, each a clone with an origin so origin/main exists — that hits
# every tier once: current, behind, unreleased, unknown, unmapped, an instance
# key mapped by prefix to a repo whose gitlab slug differs from its name, a
# repo that tags without the v prefix, and a pre-release tag that must not
# count as the newest release.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  set -e
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  mkdir -p "$T/hq/00-META" "$T/fleet"
  cat > "$T/hq/00-META/repos.md" <<'REPOS'
| Repository | Owns |
|---|---|
| `hq` | this repo |
| `thing` | current |
| `other` | behind and unreleased |
| `plain` | tags without the v prefix |
| `mcp-adapter` | instance keys (gitlab project `mcp`) |
| `helm` | the umbrella |
| `services-deploy` | the install |
REPOS
  # repo <name> <dir> — a clone with origin/main, on branch main.
  repo() {
    git init -q --bare "$T/fleet/$2.origin.git"
    git clone -q "$T/fleet/$2.origin.git" "$T/fleet/$2" 2>/dev/null
    git -C "$T/fleet/$2" checkout -q -b main
    echo "$1" > "$T/fleet/$2/README.md"
    git -C "$T/fleet/$2" add -A && git -C "$T/fleet/$2" commit -q -m "init $1"
    git -C "$T/fleet/$2" push -q origin main
  }
  # advance <dir> <msg> [tag]
  advance() {
    echo "$2" >> "$T/fleet/$1/README.md"
    git -C "$T/fleet/$1" commit -q -am "$2"
    [ -n "${3:-}" ] && git -C "$T/fleet/$1" tag "$3"
    git -C "$T/fleet/$1" push -q origin main --tags
  }
  repo thing thing;   advance thing "release 1" v0.1.0; advance thing "release 2" v0.2.0
  repo other other;   advance other "release 1" v0.1.0; advance other "release 2" v0.2.0
                      advance other "candidate" v0.2.1-rc1
  repo plain plain;   advance plain "release" 0.1.0
  repo mcp-adapter mcp; advance mcp "release" v0.3.0
  repo helm helm
  mkdir -p "$T/fleet/helm/charts/platform"
  printf 'name: platform\nversion: 0.4.0\n' > "$T/fleet/helm/charts/platform/Chart.yaml"
  git -C "$T/fleet/helm" add -A && git -C "$T/fleet/helm" commit -q -m "chart 0.4.0" && git -C "$T/fleet/helm" tag v0.4.0
  printf 'name: platform\nversion: 0.5.0\n' > "$T/fleet/helm/charts/platform/Chart.yaml"
  git -C "$T/fleet/helm" commit -q -am "chart 0.5.0" && git -C "$T/fleet/helm" tag v0.5.0
  printf 'name: platform\nversion: 0.6.0\n' > "$T/fleet/helm/charts/platform/Chart.yaml"
  git -C "$T/fleet/helm" commit -q -am "chart 0.6.0, not yet tagged"
  git -C "$T/fleet/helm" push -q origin main --tags
  repo services-deploy services-deploy
  mkdir -p "$T/fleet/services-deploy/nonprod" "$T/fleet/services-deploy/scripts"
  cat > "$T/fleet/services-deploy/nonprod/nonprod-values.yaml" <<'VALUES'
global:
  # image:
  #   registry: example
thing:
  image: { tag: "v0.2.0" } # current
other:
  enabled: false
  image: { tag: "v0.1.0" } # behind, and main is past v0.2.0
plain:
  image:
    tag: "0.1.0"
mcp-adapter-one:
  image: { tag: "v0.3.0" }
mcp-adapter-two:
  enabled: true
  image: { tag: "v9.9.9" } # no such tag
nowhere:
  image: { tag: "v1.0.0" } # not a repo
VALUES
  printf 'export const platformVersion  = "0.4.0";\n' > "$T/fleet/services-deploy/scripts/versions.mjs"
  git -C "$T/fleet/services-deploy" add -A && git -C "$T/fleet/services-deploy" commit -q -m "pins" && git -C "$T/fleet/services-deploy" push -q origin main

  # CI=false explicitly: the CI runner exports CI=true, and in CI mode the
  # check clones the real fleet — the self-test must read the throwaway one.
  # An unconfigured run must exit 0 saying so; the configured run hits every tier.
  out0="$(CI=false HQ_ROOT="$T/hq" HQ_SIBLING_ROOT="$T/fleet" NO_FETCH=1 bash "$SELF" 2>&1)" \
    && printf '%s\n' "$out0" | grep -q 'not configured' \
    && echo "PASS unconfigured run reports and exits 0" \
    || { echo "FAIL unconfigured run reports and exits 0"; printf '%s\n' "$out0" | sed 's/^/      /'; exit 1; }
  rc=0; out="$(CI=false HQ_ROOT="$T/hq" HQ_SIBLING_ROOT="$T/fleet" NO_FETCH=1 \
    HQ_DEPLOY_REPO=services-deploy HQ_DEPLOY_VALUES=nonprod/nonprod-values.yaml \
    HQ_DEPLOY_VERSIONS=scripts/versions.mjs HQ_UMBRELLA_REPO=helm \
    HQ_UMBRELLA_CHART=charts/platform/Chart.yaml bash "$SELF" 2>&1)" || rc=$?
  fails=0
  check() { # check <name> <expected line pattern>
    if printf '%s\n' "$out" | grep -qE "$2"; then echo "PASS $1"
    else echo "FAIL $1 (wanted /$2/)"; fails=$((fails+1)); fi
  }
  check "a pin at the newest release is CURRENT"                        '^CURRENT +thing +v0\.2\.0'
  check "an older pin is BEHIND the newest release"                     '^BEHIND +other +v0\.1\.0 .*newest v0\.2\.0'
  check "a pre-release tag is not the newest release"                   '^BEHIND +other .*newest v0\.2\.0'
  check "main past the newest tag is reported UNRELEASED"               '^BEHIND +other .*unreleased: main is 1 commit\(s\) past v0\.2\.0'
  check "a disabled entry says so"                                      '^BEHIND +other .*\(disabled\)'
  check "a tag without the v prefix compares as a release"              '^CURRENT +plain +0\.1\.0'
  check "an instance key maps by prefix to a repo with another slug"    '^CURRENT +mcp-adapter-one +v0\.3\.0 .*mcp-adapter'
  check "a pin naming no tag is UNKNOWN"                                '^UNKNOWN +mcp-adapter-two +v9\.9\.9'
  check "a key that is no repo is UNMAPPED"                             '^UNMAPPED +nowhere'
  check "the umbrella pin is compared like a service"                   '^BEHIND +umbrella +0\.4\.0 .*newest v0\.5\.0'
  check "an untagged chart version on main is UNRELEASED"               '^BEHIND +umbrella .*unreleased: main is 1 commit\(s\) past v0\.5\.0'
  check "the summary counts every tier"                                 '^[0-9]+ pin\(s\): 3 current, 2 behind, 2 unreleased, 1 unknown, 1 unmapped, 0 unreadable$'
  if [ "$rc" = 1 ]; then echo "PASS an unmapped key is the one thing that fails"; else echo "FAIL exit was $rc, wanted 1"; fails=$((fails+1)); fi
  out2="$(printf '%s\n' "$out" | grep -c '^UNREADABLE' || true)"
  [ "$out2" = 0 ] && echo "PASS nothing was unreadable" || { echo "FAIL $out2 unreadable"; fails=$((fails+1)); }
  [ "$fails" = 0 ] || { echo; printf '%s\n' "$out" | sed 's/^/      /'; echo "SELF-TEST FAIL"; exit 1; }
  echo "SELF-TEST OK"
  exit 0
fi

if [ -z "$DEPLOY_REPO" ] || [ -z "$VALUES_FILE" ]; then
  echo "check-deployed: not configured — this check is optional and Helm-shaped."
  echo "Set HQ_DEPLOY_REPO and HQ_DEPLOY_VALUES (and optionally HQ_DEPLOY_VERSIONS,"
  echo "HQ_UMBRELLA_REPO, HQ_UMBRELLA_CHART) in 05-TOOLS/config.sh to enable it."
  exit 0
fi

if [ "${CI:-}" = "true" ]; then
  hq_require_group || exit 1
  : "${HQ_FLEET_USER:?HQ_FLEET_USER must be set in CI}"
  : "${HQ_FLEET_TOKEN:?HQ_FLEET_TOKEN must be set in CI}"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
fi

# Logical name -> gitlab slug, from the note repos.md carries (as
# 05-TOOLS/check-claims.sh reads it).
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

# A checkout with history AND tags: `rev-list` needs the one, the release
# comparison the other.
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
        git -C "$d" fetch --quiet --tags origin main 2>/dev/null \
          || echo "  (could not fetch $name; using origin/main and tags as last fetched)"
      fi
      printf '%s' "$d"; return 0
    done
  fi
}

# Fetch every sibling the run will read, concurrently, before reading any of
# them — the 05-TOOLS/check-claims.sh argument: serial fetches made a check
# nobody waits for into a check nobody runs. --tags, because a release is a
# tag and `fetch origin main` alone only auto-follows the tags it reaches.
prefetch_siblings() {
  [ "${CI:-}" = "true" ] && return 0
  [ "${NO_FETCH:-}" = "1" ] && return 0
  local name slug d started=0
  for name in "$@"; do
    slug="$(slug_of "$name")"
    [ -n "$slug" ] || continue
    for d in "$SIBLING_ROOT/$name" "$SIBLING_ROOT/$slug"; do
      [ -e "$d/.git" ] || continue
      git -C "$d" fetch --quiet --tags origin main 2>/dev/null \
        || echo "  (could not fetch $name; using origin/main and tags as last fetched)" &
      started=$((started + 1))
      break
    done
  done
  [ "$started" -gt 0 ] && wait
  PREFETCHED=1
}

# The longest prefix of a values key that names a repo: `mcp-adapter-docs`
# -> `mcp-adapter`. Instance keys are one chart deployed several times.
repo_of_key() {
  local key="$1"
  while [ -n "$key" ]; do
    [ -n "$(slug_of "$key")" ] && { printf '%s' "$key"; return 0; }
    case "$key" in *-*) key="${key%-*}" ;; *) return 1 ;; esac
  done
  return 1
}

# The newest release tag: v1.2.3 or 1.2.3, never a pre-release.
newest_release() {
  git -C "$1" tag --list 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

# The tag a pin names, tolerating the v prefix either way; empty if none.
tag_for_pin() {
  local dir="$1" pin="$2" candidate
  for candidate in "$pin" "v$pin" "${pin#v}"; do
    git -C "$dir" rev-parse -q --verify "refs/tags/${candidate}^{commit}" >/dev/null 2>&1 \
      && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

# compare <pin> <newest> -> current | behind | ahead, on the numeric part.
compare() {
  local a="${1#v}" b="${2#v}"
  [ "$a" = "$b" ] && { echo current; return; }
  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$b" ] && echo behind || echo ahead
}

# report <key> <repo-name> <dir> <pin> <suffix>
report() {
  local key="$1" name="$2" dir="$3" pin="$4" suffix="$5" tag newest tier note ahead
  newest="$(newest_release "$dir")"
  tag="$(tag_for_pin "$dir" "$pin" || true)"
  if [ -z "$tag" ]; then
    tier=UNKNOWN; UNKNOWN=$((UNKNOWN + 1))
    note="is not a tag on $name (newest ${newest:-none})"
  else
    case "$(compare "$tag" "$newest")" in
      current) tier=CURRENT; CURRENT=$((CURRENT + 1)); note="is the newest release" ;;
      behind)  tier=BEHIND;  BEHIND=$((BEHIND + 1));   note="pinned; newest $newest" ;;
      ahead)   tier=CURRENT; CURRENT=$((CURRENT + 1)); note="is a pre-release past newest $newest" ;;
    esac
  fi
  if [ -n "$newest" ]; then
    ahead="$(git -C "$dir" rev-list --count "${newest}..origin/main" 2>/dev/null || echo 0)"
    if [ "$ahead" -gt 0 ]; then
      UNRELEASED=$((UNRELEASED + 1))
      note="$note; unreleased: main is ${ahead} commit(s) past $newest"
    fi
  fi
  [ "$key" = "$name" ] || note="$note [$name]"
  printf '%-11s %-28s %-10s %s%s\n' "$tier" "$key" "$pin" "$note" "$suffix"
}

echo "Comparing ${DEPLOY_REPO}'s pins at origin/main against each repo's releases..."

deploy="$(checkout_of "$DEPLOY_REPO")"
if [ -z "$deploy" ]; then
  echo "UNREADABLE    cannot read $DEPLOY_REPO"
  echo "----"; echo "FAIL"; exit 1
fi

# key<TAB>pin<TAB>enabled, in file order, from the values file at origin/main.
pins="$(git -C "$deploy" show "origin/main:${VALUES_FILE}" 2>/dev/null | awk '
  function flush() { if (key != "" && tag != "") printf "%s\t%s\t%s\n", key, tag, enabled }
  /^[a-z][a-z0-9-]*:/ { flush(); key=$1; sub(/:$/, "", key); tag=""; enabled=""; inimage=0; next }
  /^  enabled:[[:space:]]*false/ { enabled="disabled"; next }
  /^  image:/ {
    if (match($0, /tag:[[:space:]]*"?[A-Za-z0-9._-]+/)) { t=substr($0, RSTART, RLENGTH); sub(/tag:[[:space:]]*"?/, "", t); tag=t; inimage=0 }
    else inimage=1
    next
  }
  inimage && /^    tag:/ { t=$2; gsub(/"/, "", t); tag=t; inimage=0; next }
  /^  [a-z]/ { inimage=0 }
  END { flush() }')"
if [ -z "$pins" ]; then
  echo "UNREADABLE    no image tags found in $DEPLOY_REPO:$VALUES_FILE at origin/main"
  echo "----"; echo "FAIL"; exit 1
fi

# Map every key first, so the fetch can run once for all of them.
names="$UMBRELLA_REPO"
while IFS=$'\t' read -r key pin enabled; do
  name="$(repo_of_key "$key" || true)"
  [ -n "$name" ] && names="$names $name"
done <<< "$pins"
# shellcheck disable=SC2086
prefetch_siblings $(printf '%s\n' $names | sort -u)

while IFS=$'\t' read -r key pin enabled; do
  suffix=""; [ "$enabled" = disabled ] && suffix=" (disabled)"
  name="$(repo_of_key "$key" || true)"
  if [ -z "$name" ]; then
    printf '%-11s %-28s %-10s %s%s\n' UNMAPPED "$key" "$pin" "no repo in 00-META/repos.md matches this key or a prefix of it" "$suffix"
    UNMAPPED=$((UNMAPPED + 1)); continue
  fi
  dir="$(checkout_of "$name")"
  if [ -z "$dir" ]; then
    printf '%-11s %-28s %-10s %s\n' UNREADABLE "$key" "$pin" "cannot read $name"
    UNREADABLE=$((UNREADABLE + 1)); continue
  fi
  report "$key" "$name" "$dir" "$pin" "$suffix"
done <<< "$pins"

# The umbrella chart, one layer up: the version the install templates against
# vs the newest umbrella-repo release tag (which is what publishes the OCI
# artifact — the registry itself is beyond a read_repository token) and the
# chart version sitting on the umbrella repo's main.
umbrella=""
if [ -n "$VERSIONS_FILE" ] && [ -n "$UMBRELLA_REPO" ]; then
  umbrella="$(git -C "$deploy" show "origin/main:${VERSIONS_FILE}" 2>/dev/null \
                | sed -n 's/^export const platformVersion[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
if [ -n "$umbrella" ]; then
  helm="$(checkout_of "$UMBRELLA_REPO")"
  if [ -z "$helm" ]; then
    printf '%-11s %-28s %-10s %s\n' UNREADABLE "umbrella" "$umbrella" "cannot read $UMBRELLA_REPO"
    UNREADABLE=$((UNREADABLE + 1))
  else
    chart="$(git -C "$helm" show "origin/main:${UMBRELLA_CHART}" 2>/dev/null | sed -n 's/^version:[[:space:]]*//p' | head -1)"
    report "umbrella" "$UMBRELLA_REPO" "$helm" "$umbrella" "${chart:+ (chart on main: $chart)}"
  fi
fi

total=$((CURRENT + BEHIND + UNKNOWN + UNMAPPED + UNREADABLE))
echo "----"
echo "$total pin(s): $CURRENT current, $BEHIND behind, $UNRELEASED unreleased, $UNKNOWN unknown, $UNMAPPED unmapped, $UNREADABLE unreadable"
if [ "$UNREADABLE" -gt 0 ] || [ "$UNMAPPED" -gt 0 ]; then
  echo "FAIL"
  exit 1
fi
echo "OK"

#!/usr/bin/env bash
#
# 05-TOOLS/check-unclaimed.sh — find work that landed without anyone saying so.
#
# 05-TOOLS/check-claims.sh verifies the references a document already makes, and its
# header is explicit that the rule is one-directional:
#
#     A document claiming completion must have every reference it names be
#     present on that repo's main. Any other status: references are
#     informational.
#
# So a `status: resolved` issue naming an MR that never merged fails the build,
# while an issue sitting `open` whose fix merged a week ago is invisible to every
# check in this repo. That is the direction the hq repo actually rots in: the
# last act of a piece of work happens in a code repo, the hq repo's own MR
# merged days earlier (it is `after: []` in almost every `lands:` block), and
# the status update has no home in the landing order.
#
# This script is the missing direction.
#
# Usage:
#   ./05-TOOLS/check-unclaimed.sh              # local: expects sibling clones beside this repo
#   NO_FETCH=1 ./05-TOOLS/check-unclaimed.sh   # local, offline: use origin/main as last fetched
#   CI=true ./05-TOOLS/check-unclaimed.sh      # CI: clones the repos it needs
#
# CI variables: HQ_FLEET_USER / HQ_FLEET_TOKEN, as for 05-TOOLS/check-refs.sh.
#
# Two tiers, because the evidence is not equally good
# ---------------------------------------------------
# GAP (fails) — a commit on the repo's main says it RESOLVES the issue: a
#   resolve/fix/close word ahead of the reference, the way a closing commit is
#   written ("closes <hq-repo> issue 046", "fixes issue 025"). A human wrote
#   that deliberately; it is not a coincidence.
#
# CITED (reports, does not fail) — a commit merely NAMES the issue ("<hq-repo>
#   issue 046" in a sibling, "issue 025" in the hq repo itself) without a
#   resolving word. This used to be the strong tier, and it misfired: people
#   cite an issue to say WHY a change is what it is far more often than to say
#   it is done. A citation is a lead for the record's owner, never proof the
#   record is stale.
#
#   In the hq repo itself, commits confined to the issue's own 04-ISSUES folder
#   are excluded: the commit that files issue NNN says "issue NNN" because that
#   is what it is, not because work landed. See filter_own_record below.
#
# LIKELY (reports, does not fail) — main carries a merged branch whose name
#   begins with the issue number, i.e. a playbook-07 work ID (`046-…`). Often
#   right, but per-repo spec numbers share the number space with hq issue
#   numbers, so a sibling's own spec 014 has nothing to do with hq issue 014.
#   A check cannot tell them apart from the name, so this tier informs and
#   never blocks.
#
# The tiers exist for the reason 05-TOOLS/check-claims.sh states about
# out-of-scope references: a permanently nonzero gap trains people to ignore the
# number. GAP is kept at zero-or-real so that a nonzero GAP means something.
#
# Scope
# -----
# HQ_CHECK_SCOPE=merge-request — set by CI on a merge-request pipeline —
# narrows what FAILS, never what is reported. A GAP on a record this branch
# edited fails: the branch is touching that record and can close or exempt it.
# A GAP on any other record is reported as deferred and does not fail: it
# belongs to whoever holds that record, and the main and scheduled runs, which
# use the default fleet scope, still fail on it.
#
# --self-test builds a throwaway repository and exercises every tier and both
# scopes, so the classifier cannot silently regress — a tool nobody exercises
# is indistinguishable from a broken one.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

HQ_ROOT="${HQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HQ_REPO="${HQ_REPO:-$(basename "$HQ_ROOT")}"
# Siblings sit beside the *clone*. In a git worktree that is not the parent of
# HQ_ROOT, so ask git where the real repository is.
SIBLING_ROOT="$(dirname "$(dirname "$(git -C "$HQ_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$HQ_ROOT/.git")")")"
GROUP_PATH="${HQ_GROUP_PATH}"
GROUP_URL="https://${HQ_FORGE_HOST}/${GROUP_PATH}"
GAPS=0
DEFERRED=0
CITED=0
LIKELY=0
CHECKED=0
SCOPE="${HQ_CHECK_SCOPE:-fleet}"

# ---------------------------------------------------------------------------
# --self-test: a throwaway repository with one open, hq-located issue and
# four commits — its filing commit (own record, ignored), a citation, a
# resolution, and a branch-only edit — run through both scopes.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  set -e
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$T/hq" 2>/dev/null
  cd "$T/hq"
  git checkout -q -b main
  mkdir -p 00-META 04-ISSUES/042-the-thing-is-broken
  printf '| `hq` | this repo |\n' > 00-META/repos.md
  printf -- '---\nkind: bug\nstatus: open\nlocated-in: [hq]\n---\n# 042\n' > 04-ISSUES/042-the-thing-is-broken/00-report.md
  git add -A && git commit -q -m "issue 042: file it"
  echo a > README.md && git add -A && git commit -q -m "docs: see issue 042 for why this reads this way"
  git push -q origin main
  run() { HQ_ROOT="$T/hq" NO_FETCH=1 HQ_CHECK_SCOPE="$1" bash "$SELF" 2>&1; }
  fails=0
  check() { # check <name> <expected exit> <expected line pattern> <output> <exit>
    if [ "$5" = "$2" ] && printf '%s\n' "$4" | grep -qE "$3"; then echo "PASS $1"
    else echo "FAIL $1 (exit $5, wanted $2; wanted /$3/)"; printf '%s\n' "$4" | sed 's/^/      /'; fails=$((fails+1)); fi
  }
  rc=0; out="$(run fleet)" || rc=$?
  check "a citation is CITED, not a gap (fleet)"        0 '^CITED .*042' "$out" $rc
  echo b > README.md && git add -A && git commit -q -m "fix the thing; closes issue 042" && git push -q origin main
  rc=0; out="$(run fleet)" || rc=$?
  check "a resolving commit is a GAP (fleet)"            1 '^GAP .*042.*resolves' "$out" $rc
  git checkout -q -b unrelated && echo c > OTHER.md && git add -A && git commit -q -m "unrelated work"
  rc=0; out="$(run merge-request)" || rc=$?
  check "untouched record is deferred (merge-request)"   0 '^GAP \(deferred\) .*042' "$out" $rc
  echo note >> 04-ISSUES/042-the-thing-is-broken/00-report.md && git add -A && git commit -q -m "042: note"
  rc=0; out="$(run merge-request)" || rc=$?
  check "touched record still fails (merge-request)"     1 '^GAP .*042.*resolves' "$out" $rc
  [ $fails -eq 0 ] && { echo "self-test OK"; exit 0; } || { echo "self-test FAIL ($fails)"; exit 1; }
fi

if [ "${CI:-}" = "true" ]; then
  hq_require_group || exit 1
  : "${HQ_FLEET_USER:?HQ_FLEET_USER must be set in CI}"
  : "${HQ_FLEET_TOKEN:?HQ_FLEET_TOKEN must be set in CI}"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
fi

# In merge-request scope the records this branch edited are the ones it answers
# for. origin/main is fetched explicitly: a CI checkout of the source branch does
# not carry it, and guessing would defer a real gap.
TOUCHED=""
if [ "$SCOPE" = "merge-request" ]; then
  git -C "$HQ_ROOT" fetch --quiet origin main \
    || { echo "merge-request scope needs origin/main and could not fetch it"; exit 1; }
  TOUCHED="$(git -C "$HQ_ROOT" diff --name-only origin/main...HEAD -- 04-ISSUES/ \
             | sed 's|^04-ISSUES/||; s|/.*$||' | sort -u)"
fi

# touched <folder>: true when this branch edited something under that record.
touched() {
  printf '%s\n' "$TOUCHED" | grep -qx -- "$1"
}

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
      if [ "${NO_FETCH:-}" != "1" ]; then
        git -C "$d" fetch --quiet origin main 2>/dev/null \
          || echo "  (could not fetch $name; using origin/main as last fetched)"
      fi
      printf '%s' "$d"; return 0
    done
  fi
}

# An issue's own record names its own number — the commit that FILES issue 069
# is "issue 069: ...", and so is every later edit to the report. In the hq
# repo, where the record lives, that is not evidence of work resolving the
# issue; it is the issue existing. Reading it as a gap makes filing any
# hq-located issue break main on the next merge, which is how this was found.
#
# The discriminator is what the commit TOUCHED, not what it said. A commit
# confined to the issue's own folder is bookkeeping. One that names the issue
# and also changes something outside it is a fix, and stays a gap while the
# issue is open — which is the case this check exists for.
#
# Only the hq repo can hit this: no sibling repo contains 04-ISSUES at all.
filter_own_record() {
  _dir="$1"; _repo="$2"; _folder="$3"
  if [ "$_repo" != "$HQ_REPO" ]; then cat; return; fi
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _sha="${_line%% *}"
    # Every path this commit touched, minus those inside the issue's folder.
    # Anything left means the commit did something beyond its own record.
    _outside="$(git -C "$_dir" diff-tree --no-commit-id --name-only -r "$_sha" 2>/dev/null \
                | grep -v "^04-ISSUES/$_folder/" | head -1)"
    [ -n "$_outside" ] && printf '%s\n' "$_line"
  done
}

# A commit can NAME an issue without resolving it — a fix that mentions the
# case it came from, a note that cites a neighbour. The failure message has
# always offered the way out ("or say in the report why the merged work does
# not resolve it") and nothing implemented it, so the only actual escapes were
# to close the issue falsely or to rewrite history. Prose in the report did
# nothing.
#
# Now it does, and narrowly: a commit is exempted BY NAME, in the report's own
# frontmatter, with the reason beside it. There is no blanket mute — an
# exemption names one commit and says why, so it reads as a decision rather
# than a silenced check.
#
#   unclaimed-exempt:
#     - commit: e50e1f9
#       why: names 069 as the case that broke this check; does not resolve it
#
exempt_shas() {
  printf '%s\n' "$1" | awk '
    /^unclaimed-exempt:/         { inblk = 1; next }
    inblk && /^[^[:space:]]/     { inblk = 0 }
    inblk && /commit:/           { sub(/.*commit:[[:space:]]*/, "")
                                   sub(/[[:space:],].*/, "")
                                   gsub(/["\x27]/, "")
                                   if (length($0)) print }
  '
}

filter_exempt() {
  _ex="$1"
  [ -n "$_ex" ] || { cat; return; }
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _sha="${_line%% *}"
    _hit=0
    # Either may be the abbreviation: the report may carry a shorter or longer
    # sha than git chose to print here.
    for _e in $_ex; do
      case "$_sha" in "$_e"*) _hit=1 ;; esac
      case "$_e" in "$_sha"*) _hit=1 ;; esac
    done
    [ "$_hit" = 0 ] && printf '%s\n' "$_line"
  done
}

echo "Looking for work that merged while its hq issue stayed open..."

for report in "$HQ_ROOT"/04-ISSUES/*/00-report.md; do
  [ -e "$report" ] || continue
  folder="$(basename "$(dirname "$report")")"
  num="${folder%%-*}"
  rel="04-ISSUES/$folder/00-report.md"

  fm="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$report")"
  status="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
  case "$status" in
    resolved|wontfix) continue ;;          # terminal: 05-TOOLS/check-claims.sh owns these
    open|diagnosing|located|blocked) ;;    # blocked is active — merged work naming it is still a gap
    *) continue ;;
  esac

  # located-in: [a, b] — a bug that has not been localized yet names no repo,
  # and there is nowhere to look. That is not a gap, it is a diagnosis.
  repos="$(printf '%s\n' "$fm" | sed -n 's/^located-in:[[:space:]]*//p' | head -1 \
           | tr -d '[]' | tr ',' ' ')"
  [ -n "$repos" ] || continue
  CHECKED=$((CHECKED + 1))
  # One line per issue, not per repo: cross-repo work merges the same work ID
  # into every repo it touches, and reporting 027 four times says nothing the
  # first line did not.
  said_likely=0
  exempt="$(exempt_shas "$fm")"

  for repo in $repos; do
    repo="$(printf '%s' "$repo" | tr -d ' ')"
    [ -n "$repo" ] || continue

    if [ "$repo" = "$HQ_REPO" ]; then
      dir="$HQ_ROOT"
      # Inside the hq repo nobody writes the hq-repo qualifier — "issue 025:".
      cite="issue[s]?[^0-9]*[^0-9]${num}([^0-9]|$)"
    else
      dir="$(checkout_of "$repo")" || dir=""
      [ -n "$dir" ] || continue
      # A sibling always qualifies the number, because its own spec numbers
      # share the number space: "<hq-repo> issue 046", "(<hq-repo> 046)".
      cite="${HQ_REPO}[^0-9]*[^0-9]${num}([^0-9]|$)"
    fi
    # A resolving commit says so ahead of the reference: "closes <hq-repo>
    # issue 046", "resolves issue 025". The window between the
    # word and the number is short on purpose — a "fixes" three paragraphs
    # above a citation is not a claim about that citation.
    resolve="(resolv|fix|clos)[a-z]*[^0-9]{0,40}${cite}"

    all_hits="$(git -C "$dir" log origin/main --no-merges --format='%h %s' \
                 -E --grep="$cite" 2>/dev/null \
               | filter_own_record "$dir" "$repo" "$folder" \
               | filter_exempt "$exempt")"
    hits="$(git -C "$dir" log origin/main --no-merges --format='%h %s' \
              -E --grep="$resolve" 2>/dev/null \
            | filter_own_record "$dir" "$repo" "$folder" \
            | filter_exempt "$exempt" | head -3)"
    if [ -n "$hits" ]; then
      if [ "$SCOPE" = "merge-request" ] && ! touched "$folder"; then
        echo "GAP (deferred) $rel is '$status' — $repo main resolves it; not a record this branch edited:"
        DEFERRED=$((DEFERRED + 1))
      else
        echo "GAP           $rel is '$status' — $repo main resolves it:"
        GAPS=$((GAPS + 1))
      fi
      printf '%s\n' "$hits" | sed 's/^/                  /'
      continue                      # a GAP already says it; do not also report the rest
    fi
    if [ -n "$all_hits" ] && [ "$said_likely" = 0 ]; then
      echo "CITED         $rel is '$status' — $repo main names it (no resolving word; a lead, not a gap):"
      printf '%s\n' "$all_hits" | head -3 | sed 's/^/                  /'
      CITED=$((CITED + 1))
      said_likely=1
      continue
    fi

    # Weaker: a merged work-ID branch beginning with this number.
    [ "$said_likely" = 1 ] && continue
    hits="$(git -C "$dir" log origin/main --merges --format='%h %s' \
              -E --grep="Merge branch '${num}-" --grep="Merge branch '[0-9]{3}-${num}-" 2>/dev/null | head -2)"
    if [ -n "$hits" ]; then
      echo "LIKELY        $rel is '$status' — $repo main merged a work ID starting $num:"
      printf '%s\n' "$hits" | sed 's/^/                  /'
      LIKELY=$((LIKELY + 1))
      said_likely=1
    fi
  done
done

echo "----"
echo "checked $CHECKED localized non-terminal issue(s); $GAPS gap(s), $DEFERRED deferred, $CITED cited, $LIKELY likely"
if [ "$DEFERRED" -gt 0 ]; then
  echo "deferred gaps belong to records this branch did not edit; the main and scheduled runs fail on them"
fi

if [ "$GAPS" -gt 0 ]; then
  echo
  echo "A gap means a repo's main deliberately names an issue that this repo still"
  echo "shows as open. Either close the issue with a verifiable fixed-by ref,"
  echo "or — when the commit names the issue without resolving it —"
  echo "exempt that one commit in the report's frontmatter, with the reason:"
  echo
  echo "  unclaimed-exempt:"
  echo "    - commit: <sha>"
  echo "      why: <why this does not resolve the issue>"
  echo "FAIL"
  exit 1
fi
echo "OK"

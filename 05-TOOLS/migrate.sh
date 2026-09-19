#!/usr/bin/env bash
#
# 05-TOOLS/migrate.sh — pull template updates into this hq instance.
#
# A project created from the hq template owns its CONTENT — mission, research,
# designs, decisions, issues, features, repos.md, config.sh — and borrows its
# MACHINERY: the tools in 05-TOOLS/, the skills in .claude/, the playbooks,
# the section READMEs, the CI files. The template keeps improving after a
# project is created; this command carries those improvements over without
# touching what the project owns.
#
# It is diff-driven, not overwrite-driven. It fetches the template, takes the
# diff between the template commit this instance last migrated from (recorded
# in 05-TOOLS/template-commit) and the template's current main, and applies it
# file by file with a three-way merge:
#
#   - a file only the template changed        -> updated
#   - a file only this project changed        -> left alone (no diff hunk)
#   - both changed, different lines           -> merged
#   - both changed, the same lines            -> conflict markers, reported
#   - a machinery file this project deleted   -> stays deleted, reported
#     (deleting playbooks 05/06 or the unused CI file is deliberate — the
#     hq-setup skill's trim step)
#
# Usage:
#   ./05-TOOLS/migrate.sh [--from <url|path>] [--base <sha>] [--dry-run]
#   ./05-TOOLS/migrate.sh --self-test
#
#   --from     the template repo; defaults to HQ_TEMPLATE_REPO in config.sh.
#   --base     the template commit to diff from; defaults to the sha in
#              05-TOOLS/template-commit (hq-setup writes it, this script
#              advances it). Needed once when the marker is missing — the
#              template commit the instance was created from.
#   --dry-run  report what would change, touch nothing.
#
# Run it in a workspace (playbook 07) on a clean tree, review the result —
# `git diff`, then the self-tests of whatever tools changed — and land it by
# MR like any other change. On success the marker advances to the template
# commit just applied. Conflicts are left in the tree with markers and the
# run exits nonzero until a human settles them; the marker still advances,
# because it records what was merged in, not whether the merge was clean.

set -uo pipefail

# This script may update ITSELF when the template changed it. bash reads a
# script lazily, so rewriting the file mid-run corrupts the run — instead the
# first thing every invocation does is re-exec a temp copy of itself, with
# the real location kept in HQ_MIGRATE_SELF.
if [ -z "${HQ_MIGRATE_SELF:-}" ]; then
  HQ_MIGRATE_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HQ_MIGRATE_SELF
  _self_copy="$(mktemp "${TMPDIR:-/tmp}/hq-migrate.XXXXXX")"
  cp "${BASH_SOURCE[0]}" "$_self_copy"
  exec /usr/bin/env bash "$_self_copy" "$@"
fi
TOOLS_DIR="$HQ_MIGRATE_SELF"
# The temp copy is this very script; remove it when the run ends.
case "${BASH_SOURCE[0]}" in */hq-migrate.??????) trap 'rm -f "${BASH_SOURCE[0]}"' EXIT ;; esac

. "$TOOLS_DIR/config.sh"
ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
MARKER="$TOOLS_DIR/template-commit"

# What the template owns in an instance. Everything else is the project's —
# in particular 05-TOOLS/config.sh, 00-META/repos.md, the filled-in 00-META
# content docs, and every record in the numbered content folders.
MACHINERY=(
  README.md AGENTS.md CLAUDE.md .gitignore
  .gitlab-ci.yml .github
  .claude
  00-META/README.md 00-META/process
  01-RESEARCH/README.md 02-DESIGN/README.md 03-DECISIONS/README.md
  04-ISSUES/README.md 06-FEATURES/README.md 99-ARTIFACTS/README.md
  05-TOOLS
)
skip_path() { # project-owned files living inside a machinery directory
  case "$1" in
    05-TOOLS/config.sh|05-TOOLS/template-commit) return 0 ;;
    *) return 1 ;;
  esac
}

die() { echo "$*" >&2; exit 2; }

# --- self-test -------------------------------------------------------------

self_test() {
  local T pass=0 fail=0 base new out rc
  ok()  { echo "  PASS $1"; pass=$((pass+1)); }
  bad() { echo "  FAIL $1"; fail=$((fail+1)); }
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  T="$(mktemp -d "${TMPDIR:-/tmp}/hq-migrate-test.XXXXXX")"
  trap 'rm -rf "$T"' RETURN

  # The template, v1: a tool, a playbook, a skill, a CI file, a README, and
  # content docs that must never be touched.
  git init -q -b main "$T/template"
  mkdir -p "$T/template/05-TOOLS" "$T/template/00-META/process" "$T/template/.claude/skills/hq-x"
  printf '#!/usr/bin/env bash\necho tool v1\n' > "$T/template/05-TOOLS/tool.sh"
  printf 'HQ_REPO=""\n' > "$T/template/05-TOOLS/config.sh"
  printf '# Playbook\n\nstep one\nstep two\nstep three\n' > "$T/template/00-META/process/07-x.md"
  printf 'skill v1\n' > "$T/template/.claude/skills/hq-x/SKILL.md"
  printf 'gitlab ci v1\n' > "$T/template/.gitlab-ci.yml"
  printf '# HQ\n\ntemplate prose\n' > "$T/template/README.md"
  printf '# Mission skeleton\n' > "$T/template/00-META/mission.md"
  git -C "$T/template" add -A && git -C "$T/template" commit -qm v1
  base="$(git -C "$T/template" rev-parse HEAD)"

  # The instance: created from v1, then customized — its own config and
  # mission, a project H1 in the README, an edit to the playbook, the
  # GitLab CI file trimmed away.
  git clone -q "$T/template" "$T/inst" 2>/dev/null
  cp "$TOOLS_DIR/migrate.sh" "$T/inst/05-TOOLS/migrate.sh"
  printf 'HQ_REPO="inst"\n' > "$T/inst/05-TOOLS/config.sh"
  printf '# Atlas Mission\n\nreal content\n' > "$T/inst/00-META/mission.md"
  sed -i.bak 's/^# HQ$/# Atlas HQ/' "$T/inst/README.md" && rm -f "$T/inst/README.md.bak"
  sed -i.bak 's/^step two$/step two, locally amended/' "$T/inst/00-META/process/07-x.md" && rm -f "$T/inst/00-META/process/07-x.md.bak"
  rm "$T/inst/.gitlab-ci.yml"
  printf '%s\n' "$base" > "$T/inst/05-TOOLS/template-commit"
  git -C "$T/inst" add -A && git -C "$T/inst" commit -qm customized

  # The template, v2: the tool changes, a skill is added, the trimmed CI file
  # changes, the README prose changes (away from the H1), the playbook's
  # amended line changes too (the conflict case), and the skeleton mission
  # changes (outside the machinery — must not reach the instance).
  printf '#!/usr/bin/env bash\necho tool v2\n' > "$T/template/05-TOOLS/tool.sh"
  mkdir -p "$T/template/.claude/skills/hq-y"
  printf 'skill y, new\n' > "$T/template/.claude/skills/hq-y/SKILL.md"
  printf 'gitlab ci v2\n' > "$T/template/.gitlab-ci.yml"
  printf '# HQ\n\ntemplate prose, improved\n' > "$T/template/README.md"
  printf '# Playbook\n\nstep one\nstep two, template reworded\nstep three\n' > "$T/template/00-META/process/07-x.md"
  printf '# Mission skeleton, reworded\n' > "$T/template/00-META/mission.md"
  git -C "$T/template" add -A && git -C "$T/template" commit -qm v2
  new="$(git -C "$T/template" rev-parse HEAD)"

  # Dry run first: reports, changes nothing.
  out="$(cd / && HQ_MIGRATE_SELF= bash "$T/inst/05-TOOLS/migrate.sh" --from "$T/template" --dry-run 2>&1)"; rc=$?
  grep -q 'echo tool v1' "$T/inst/05-TOOLS/tool.sh" \
    && [ "$(cat "$T/inst/05-TOOLS/template-commit")" = "$base" ] \
    && ok "dry run changes nothing" || bad "dry run changes nothing"
  printf '%s\n' "$out" | grep -q 'would update *05-TOOLS/tool.sh' \
    && ok "dry run says what it would do" || bad "dry run says what it would do"

  # The real run.
  out="$(cd / && HQ_MIGRATE_SELF= bash "$T/inst/05-TOOLS/migrate.sh" --from "$T/template" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && ok "conflicts make the run exit 1" || bad "conflicts make the run exit 1 (got $rc)"
  grep -q 'echo tool v2' "$T/inst/05-TOOLS/tool.sh" \
    && ok "a tool only the template changed is updated" || bad "a tool only the template changed is updated"
  [ -f "$T/inst/.claude/skills/hq-y/SKILL.md" ] \
    && ok "a new template file is added" || bad "a new template file is added"
  [ ! -e "$T/inst/.gitlab-ci.yml" ] \
    && printf '%s\n' "$out" | grep -q 'locally deleted' \
    && ok "a locally deleted file stays deleted, reported" || bad "a locally deleted file stays deleted, reported"
  grep -q '^# Atlas HQ$' "$T/inst/README.md" && grep -q 'template prose, improved' "$T/inst/README.md" \
    && ok "template and local README edits merge" || bad "template and local README edits merge"
  grep -q '^<<<<<<<' "$T/inst/00-META/process/07-x.md" \
    && printf '%s\n' "$out" | grep -q 'CONFLICT.*07-x.md' \
    && ok "same-line edits leave conflict markers, reported" || bad "same-line edits leave conflict markers, reported"
  [ "$(head -1 "$T/inst/05-TOOLS/config.sh")" = 'HQ_REPO="inst"' ] \
    && ok "config.sh is untouched" || bad "config.sh is untouched"
  grep -q 'real content' "$T/inst/00-META/mission.md" \
    && ok "project content is untouched" || bad "project content is untouched"
  [ "$(cat "$T/inst/05-TOOLS/template-commit")" = "$new" ] \
    && ok "the marker advances to the applied commit" || bad "the marker advances to the applied commit"

  # A second run from the advanced marker: nothing to do.
  out="$(cd / && HQ_MIGRATE_SELF= bash "$T/inst/05-TOOLS/migrate.sh" --from "$T/template" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'already current' \
    && ok "a second run is already current" || bad "a second run is already current"

  # No marker and no --base: refuse with guidance.
  rm "$T/inst/05-TOOLS/template-commit"
  out="$(cd / && HQ_MIGRATE_SELF= bash "$T/inst/05-TOOLS/migrate.sh" --from "$T/template" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q -- '--base' \
    && ok "missing marker asks for --base" || bad "missing marker asks for --base"

  echo "migrate self-test: $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

# --- args --------------------------------------------------------------------

FROM="" BASE="" DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)      FROM="${2:?--from needs a url or path}"; shift ;;
    --base)      BASE="${2:?--base needs a template commit sha}"; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --self-test) self_test; exit ;;
    -h|--help)   awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "$TOOLS_DIR/migrate.sh"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done

# --- main ----------------------------------------------------------------------

FROM="${FROM:-${HQ_TEMPLATE_REPO:-}}"
[ -n "$FROM" ] || die "no template repo: set HQ_TEMPLATE_REPO in 05-TOOLS/config.sh (the hq-setup skill asks for it) or pass --from <url|path>"

if [ -z "$BASE" ]; then
  if [ -f "$MARKER" ]; then
    BASE="$(head -1 "$MARKER")"
  else
    die "no $MARKER and no --base: pass --base <sha>, the template commit this instance was created from (the template's main at creation time); the marker is written from then on"
  fi
fi

if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  echo "note: the working tree is not clean — the migration will mix with local edits; a clean tree reviews better" >&2
fi

echo "fetching the template: $FROM"
git -C "$ROOT" fetch --quiet "$FROM" main \
  || die "could not fetch main from $FROM"
NEW="$(git -C "$ROOT" rev-parse FETCH_HEAD)"
git -C "$ROOT" cat-file -e "${BASE}^{commit}" 2>/dev/null \
  || die "base $BASE is not a commit here even after fetching the template — is it really a template commit?"

if [ "$NEW" = "$BASE" ] || git -C "$ROOT" diff --quiet "$BASE" "$NEW" -- "${MACHINERY[@]}"; then
  echo "already current: the template's machinery is unchanged since ${BASE:0:9}"
  [ "$DRY_RUN" = 1 ] || printf '%s\n' "$NEW" > "$MARKER"
  exit 0
fi

echo "applying template changes ${BASE:0:9} -> ${NEW:0:9}"
UPDATED=0; ADDED=0; DELETED=0; SKIPPED=0; CONFLICTS=0; FAILED=0

while IFS=$'\t' read -r status path; do
  [ -n "$path" ] || continue
  skip_path "$path" && continue

  if [ "$DRY_RUN" = 1 ]; then
    case "$status" in
      A) echo "  would add    $path" ;;
      D) echo "  would delete $path" ;;
      *) echo "  would update $path" ;;
    esac
    continue
  fi

  # A machinery file this project deleted on purpose stays deleted; the
  # template's edit to it is reported, never resurrected.
  if [ "$status" != "A" ] && [ ! -e "$ROOT/$path" ]; then
    if [ "$status" = "D" ]; then
      echo "  already gone $path (deleted here and in the template)"
    else
      echo "  locally deleted, left deleted: $path (the template changed it — re-create it by hand if you want it back)"
      SKIPPED=$((SKIPPED+1))
    fi
    continue
  fi

  err="$(git -C "$ROOT" diff --no-renames "$BASE" "$NEW" -- "$path" \
           | git -C "$ROOT" apply --3way 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    case "$status" in
      A) echo "  added        $path"; ADDED=$((ADDED+1)) ;;
      D) echo "  deleted      $path"; DELETED=$((DELETED+1)) ;;
      *) echo "  updated      $path"; UPDATED=$((UPDATED+1)) ;;
    esac
  elif printf '%s\n' "$err" | grep -qi 'with conflicts'; then
    echo "  CONFLICT     $path — both sides changed the same lines; markers left in the file"
    CONFLICTS=$((CONFLICTS+1))
  else
    echo "  FAILED       $path — could not apply:"
    printf '%s\n' "$err" | sed 's/^/                 /'
    FAILED=$((FAILED+1))
  fi
done < <(git -C "$ROOT" diff --no-renames --name-status "$BASE" "$NEW" -- "${MACHINERY[@]}")

if [ "$DRY_RUN" = 1 ]; then
  echo "dry run: nothing was changed"
  exit 0
fi

printf '%s\n' "$NEW" > "$MARKER"

echo "----"
echo "updated $UPDATED, added $ADDED, deleted $DELETED, left deleted $SKIPPED, conflicts $CONFLICTS, failed $FAILED"
echo "marker advanced to ${NEW:0:9}; review with git status and git diff HEAD (a three-way apply stages what it merges), then run the self-tests of whatever tools changed"
if [ "$CONFLICTS" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
  echo "settle the conflicts/failures by hand before landing this by MR"
  exit 1
fi
echo "OK"

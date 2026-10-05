#!/usr/bin/env bash
# 05-TOOLS/config.sh — the one place this project names itself.
#
# Sourced by every tool in this tree. Fill it in by running the hq-setup
# skill, or by hand. Every value can be overridden by the environment: an
# HQ_* variable that is already set wins over what is written here.
#
#   HQ_REPO        the name of this hq repository (the hub). Leave empty to
#                  derive it from the clone directory's basename, which is
#                  correct in every clone and worktree that keeps the repo's
#                  name.
#   HQ_FORGE       github | gitlab. Which forge hosts the fleet — it decides
#                  the CLI the tools reach for (gh / glab), the authenticated
#                  clone URL shape, and how an mr: reference is verified.
#                  Leave empty to infer it from HQ_FORGE_HOST (a host
#                  containing "github" means github; anything else gitlab).
#   HQ_FORGE_HOST  the forge host, e.g. github.com or gitlab.example.com
#   HQ_GROUP_PATH  the org (GitHub) or group (GitLab, subgroups allowed)
#                  holding the fleet, e.g. my-org or my-org/my-platform
#   HQ_TEMPLATE_REPO  the hq template this instance was created from — a git
#                  URL or local path. 05-TOOLS/migrate.sh pulls the template's
#                  machinery improvements from it; leave empty if this project
#                  never migrates.
#   HQ_MERGE_POLICY  who merges a ready MR — the project's call, not the
#                  template's (05-TOOLS/merge-policy.sh reads it):
#                    agents  whoever did the work merges once the MR is ready,
#                            in lands: order, never past a failing check and
#                            never around branch protection;
#                    humans  the agent marks the MR ready and stops; a human
#                            merges;
#                    empty   undecided: the agent marks the MR ready, asks the
#                            human which policy the project wants, and does
#                            not merge. The hq-setup skill asks.

: "${HQ_REPO:=}"
: "${HQ_FORGE:=}"
: "${HQ_FORGE_HOST:=}"
: "${HQ_GROUP_PATH:=}"
: "${HQ_TEMPLATE_REPO:=}"
: "${HQ_MERGE_POLICY:=}"

# hq_repo — print the hub repo's name, deriving it from the working tree's
# root directory when HQ_REPO is unset. Call from inside the hq repo.
hq_repo() {
  if [ -n "${HQ_REPO:-}" ]; then
    printf '%s\n' "$HQ_REPO"
    return 0
  fi
  basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# hq_forge — print github or gitlab: the explicit HQ_FORGE, or inferred from
# the host name.
hq_forge() {
  if [ -n "${HQ_FORGE:-}" ]; then
    printf '%s\n' "$HQ_FORGE"
    return 0
  fi
  case "${HQ_FORGE_HOST:-}" in
    *github*) echo github ;;
    *)        echo gitlab ;;
  esac
}

# hq_require_group — fail with guidance when the forge group is unset.
# Tools that talk to the forge call this first so an unconfigured template
# explains itself instead of hitting a dead URL.
hq_require_group() {
  if [ -z "${HQ_FORGE_HOST:-}" ] || [ -z "${HQ_GROUP_PATH:-}" ]; then
    echo "not configured: this tool needs the forge group." >&2
    echo "Set HQ_FORGE_HOST and HQ_GROUP_PATH in 05-TOOLS/config.sh — the hq-setup skill fills them in." >&2
    return 1
  fi
}

# hq_require_fleet_auth — fail when the CI read credential is missing.
# GitHub needs only HQ_FLEET_TOKEN (a fine-grained PAT or app token with
# read access to the fleet's repositories); GitLab also needs HQ_FLEET_USER,
# the deploy token's username. See 05-TOOLS/check-refs.sh --help.
hq_require_fleet_auth() {
  : "${HQ_FLEET_TOKEN:?HQ_FLEET_TOKEN must be set in CI (see 05-TOOLS/check-refs.sh --help)}"
  if [ "$(hq_forge)" = gitlab ]; then
    : "${HQ_FLEET_USER:?HQ_FLEET_USER must be set in CI (the GitLab deploy token username)}"
  fi
}

# hq_clone_url <slug> — the authenticated https clone URL the CI checkers
# use to read a fleet repo. GitHub tokens authenticate as x-access-token
# unless HQ_FLEET_USER says otherwise.
hq_clone_url() {
  local user="${HQ_FLEET_USER:-}"
  if [ -z "$user" ] && [ "$(hq_forge)" = github ]; then
    user="x-access-token"
  fi
  printf 'https://%s:%s@%s/%s/%s.git' "$user" "${HQ_FLEET_TOKEN:-}" "$HQ_FORGE_HOST" "$HQ_GROUP_PATH" "$1"
}

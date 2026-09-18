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
#   HQ_FORGE_HOST  the GitLab host, e.g. gitlab.example.com
#   HQ_GROUP_PATH  the GitLab group holding the fleet, e.g. my-org/my-platform

: "${HQ_REPO:=}"
: "${HQ_FORGE_HOST:=}"
: "${HQ_GROUP_PATH:=}"

# hq_repo — print the hub repo's name, deriving it from the working tree's
# root directory when HQ_REPO is unset. Call from inside the hq repo.
hq_repo() {
  if [ -n "${HQ_REPO:-}" ]; then
    printf '%s\n' "$HQ_REPO"
    return 0
  fi
  basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

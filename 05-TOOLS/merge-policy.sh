#!/usr/bin/env bash
#
# 05-TOOLS/merge-policy.sh — who merges a ready MR in this project.
#
# The template does not decide this: a project does, in HQ_MERGE_POLICY in
# 05-TOOLS/config.sh (the hq-setup skill asks). This prints the answer as one
# word, so an agent runs a command instead of interpreting prose:
#
#   agents     whoever did the work merges once the MR is ready, in lands:
#              order, never past a failing check, never around branch
#              protection
#   humans     the agent marks the MR ready and stops; a human merges
#   undecided  the setting is empty: the agent marks the MR ready, asks the
#              human which policy the project wants, and does not merge
#
# Any other value is a configuration error: it exits 2 naming the setting,
# rather than letting a typo read as either answer.
#
# Usage:
#   ./05-TOOLS/merge-policy.sh               # print the policy
#   ./05-TOOLS/merge-policy.sh --self-test   # check the mapping

set -euo pipefail

policy_of() {
  case "$1" in
    agents|humans) printf '%s\n' "$1" ;;
    "")            printf 'undecided\n' ;;
    *)
      echo "HQ_MERGE_POLICY='$1' is not a policy: set it to agents or humans in 05-TOOLS/config.sh, or leave it empty (undecided)" >&2
      return 2
      ;;
  esac
}

self_test() {
  local fail=0 got
  for pair in "agents:agents" "humans:humans" ":undecided"; do
    got="$(policy_of "${pair%%:*}")" || got="error"
    if [ "$got" != "${pair#*:}" ]; then
      echo "FAIL: '${pair%%:*}' -> '$got', want '${pair#*:}'" >&2
      fail=1
    fi
  done
  if policy_of "Agents" >/dev/null 2>&1; then
    echo "FAIL: 'Agents' accepted; a value outside the two must be refused" >&2
    fail=1
  fi
  [ "$fail" = 0 ] && echo "merge-policy self-test: ok"
  return "$fail"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi
if [ $# -gt 0 ]; then
  echo "usage: $0 [--self-test]" >&2
  exit 2
fi

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
policy_of "${HQ_MERGE_POLICY:-}"   # an instance whose config.sh predates the setting reads as undecided

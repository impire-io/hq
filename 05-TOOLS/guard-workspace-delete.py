#!/usr/bin/env python3
"""Refuse a delete that reaches beyond one work item.

`.work/` is shared. Every agent and engineer on the machine keeps their
worktrees under `.work/<work-id>/`, so a delete aimed at `.work` itself, or
globbed across `.work/*`, destroys other people's in-flight work. That has
happened: a teardown ran `rm -rf .work` and took out an unrelated work item's
worktree.

Playbook 07 step 8 already says to remove `.work/<work-id>/` and nothing wider.
This is the part that does not depend on remembering.

Wired as a PreToolUse hook on Bash (`.claude/settings.json`). Reads the hook
payload on stdin; prints a deny decision when a command is destructive AND names
`.work` too broadly. Everything else passes untouched, because a guard that
interferes with ordinary work gets switched off.

Self-test:  ./05-TOOLS/guard-workspace-delete.py --self-test
By hand:    echo '{"tool_input":{"command":"rm -rf .work"}}' | ./05-TOOLS/guard-workspace-delete.py
"""

import json
import re
import sys

# Only destructive verbs are considered. Reading, listing or grepping inside
# .work is ordinary and must not be interfered with.
DESTRUCTIVE = re.compile(
    r"(^|[;&|(]|\s)(rm|rmdir|trash|shred)\s"
    r"|git\s+(-C\s+\S+\s+)?worktree\s+remove"
    r"|find\b[^;&|]*-delete"
)

WORK_PATH = re.compile(r"(^|/)\.work($|/)")

GLOB_CHARS = set("*?[]{}")


def overreach(token):
    """Why this token reaches past one work item, or None if it is fine."""
    t = token.strip("\"'").rstrip("/")
    if not WORK_PATH.search(t):
        return None

    tail = t.split(".work", 1)[1].lstrip("/")
    if tail == "":
        return "it names the shared .work directory itself"

    work_id = tail.split("/", 1)[0]
    if any(c in GLOB_CHARS for c in work_id):
        return "the work-id segment is a glob ({}), so it spans every work item".format(
            work_id
        )
    if work_id in (".", ".."):
        return "the work-id segment is a relative traversal ({})".format(work_id)
    return None


def refusal(token, reason):
    return (
        "Refused: this deletes {} and {}.\n\n"
        ".work/ is shared with every other agent and engineer on this machine, "
        "and their in-flight worktrees sit beside yours. A delete that is not "
        "scoped to one work id destroys their work, including anything they "
        "have not committed.\n\n"
        "Scope it to your own work item:\n"
        "    ./05-TOOLS/teardown-workspace.sh <work-id>\n"
        "or, by hand, name the single directory:\n"
        "    rm -rf .work/<work-id>/\n\n"
        "See 00-META/process/07-parallel-work.md, step 8."
    ).format(token, reason)


# Where one command ends and the next begins. A pipe is deliberately NOT a
# separator: `ls .work | xargs rm -rf` is one flow of data into a delete, and the
# path belongs to the delete as much as to the `ls`.
SEPARATOR = re.compile(r"&&|\|\||[;\n]")

# A loop header names what the body will delete (`for d in .work/*/; do rm …`),
# and an assignment names it earlier still (`W=.work; rm -rf "$W"`). Neither is
# destructive on its own, so both are read only once the line is known to delete.
CARRIER = re.compile(r"^\s*(for|while|until)\s|^\s*[A-Za-z_][A-Za-z_0-9]*=")


def decide(command):
    """Return a refusal reason for command, or None to allow it.

    Segment by segment, so a path is only ever judged against the command it
    belongs to. Reading `.work` beside an unrelated delete is ordinary work, and
    judging the whole line at once refused it — each refusal teaching the
    workaround of splitting the line and re-running the delete alone, which is
    the habit that lets the next real one through.
    """
    if not command or not DESTRUCTIVE.search(command):
        return None

    segments = SEPARATOR.split(command)
    deletes = [s for s in segments if DESTRUCTIVE.search(s)]
    if not deletes:
        return None

    # The deletes themselves, then whatever named their target for them.
    for segment in deletes + [s for s in segments if CARRIER.match(s)]:
        # `=` splits too, so an assignment's value is a token of its own:
        # `W=.work` has to read as `.work`, not as one opaque word.
        for token in re.split(r"[\s;|&()=]+", segment):
            reason = overreach(token)
            if reason is not None:
                return refusal(token, reason)
    return None


BLOCK = [
    "rm -rf .work",
    "rm -rf .work/",
    "rm -rf /Users/x/Work/fleet/.work",
    "rm -rf .work/*",
    "rm -rf .work/*/hq",
    'for d in .work/*/; do rm -rf "$d"; done',
    "cd /tmp && rm -rf ~/Work/fleet/.work",
    "git -C hq worktree remove --force .work/../elsewhere",
    "rm -rf '.work'",
    "rmdir .work",
    # The target is named somewhere other than the delete's own words: a loop
    # header, an assignment, or the left side of a pipe feeding it.
    'W=.work; rm -rf "$W"',
    "ls .work | xargs rm -rf",
    'for d in .work/*/; do echo "$d"; rm -rf "$d"; done',
]

ALLOW = [
    "rm -rf .work/my-work-id",
    "rm -rf .work/my-work-id/",
    "rm -rf .work/002-vault-client/hq",
    "git -C hq worktree remove .work/my-work-id/hq",
    "ls .work",
    "ls .work/*",
    "grep -r foo .work/",
    "find .work -name '*.md'",
    "rm -rf dist",
    "rm -rf node_modules",
    "echo 'rm -rf .work is what not to do'",
    # A read of .work beside a delete of something else. The token belongs to
    # the ls, not to the rm — refusing these teaches the workaround habit.
    "ls .work && rm -rf /tmp/scratch",
    "ls /Users/x/Work/fleet/.work; rm -rf /tmp/scratch/ows",
    "./05-TOOLS/teardown-workspace.sh probe && ls .work && rm -rf /tmp/probe",
    "rmdir .work/my-work-id/hq && ls -a .work",
    "rm /Users/x/Work/fleet/002-vault-client && ls /Users/x/Work/fleet/.work",
    "find .work -name '*.md' | head -3; rm -rf build",
]


def self_test():
    failures = []
    for c in BLOCK:
        if decide(c) is None:
            failures.append("should BLOCK but allowed: {}".format(c))
    for c in ALLOW:
        if decide(c) is not None:
            failures.append("should ALLOW but blocked: {}".format(c))
    for f in failures:
        print(f)
    print(
        "{}/{} cases correct".format(
            len(BLOCK) + len(ALLOW) - len(failures), len(BLOCK) + len(ALLOW)
        )
    )
    return 1 if failures else 0


def main():
    if "--self-test" in sys.argv:
        return self_test()

    try:
        payload = json.load(sys.stdin)
    except Exception:
        # A payload we cannot read is not evidence of a dangerous command.
        # Allow, rather than blocking every Bash call the moment a format shifts.
        return 0

    command = (payload.get("tool_input") or {}).get("command") or ""
    reason = decide(command)
    if reason is None:
        return 0

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Refuse a write to a clone. Work happens in `.work/<work-id>/`, never in the clone.

The clones under the fleet root are shared by every agent and engineer on the
machine. They are the refresh point and the thing worktrees are cut from, so
reading them is ordinary and constant — which is exactly why drifting into
*writing* them has never had a boundary to cross. Playbook 07 says "do not
work in the clone"; without a rail, the disk says otherwise.

Legal in a clone, and untouched here: reading anything, `git fetch`, a
fast-forward of main, `git worktree add|list|remove`, `05-TOOLS/sync.sh`,
`05-TOOLS/teardown-workspace.sh` — the operations the clone exists for.

Refused: editing a file, committing, switching branches, pushing, deleting.

This is a rail, not a sandbox. It does not parse shell redirects, `sed -i` or
`tee`, and a determined process gets past it. What it prevents is drift.

Wired as a PreToolUse hook on Edit/Write/NotebookEdit and on Bash
(`.claude/settings.json`). Reads the hook payload on stdin; prints a deny
decision when a write lands inside a clone. Everything else passes untouched,
because a guard that interferes with ordinary work gets switched off.

Self-test:  ./05-TOOLS/guard-readonly-clone.py --self-test
By hand:    echo '{"tool_name":"Bash","cwd":"/r/hq","tool_input":{"command":"git commit -m x"}}' \
              | ./05-TOOLS/guard-readonly-clone.py
"""

import json
import os
import posixpath
import re
import shlex
import subprocess
import sys

# git subcommands that change a repository or its working tree. A deny-list
# rather than an allow-list: an unrecognised read-only command must pass, since
# the cost of a false refusal is that someone switches the guard off, while the
# cost of a missed mutator is drift the MR still catches.
MUTATING_GIT = {
    "commit", "add", "rm", "mv", "checkout", "switch", "restore", "merge",
    "rebase", "reset", "revert", "push", "stash", "cherry-pick", "am", "apply",
    "clean", "pull", "filter-branch",
}

# Deleting or moving a file in a clone is a write, whatever runs it.
FILE_MUTATORS = {"rm", "rmdir", "mv", "trash", "shred"}

# `git branch` and `git tag` are listings until one of these appears.
BRANCH_MUTATORS = {"-d", "-D", "-m", "-M", "-f", "--force", "--set-upstream-to", "-u", "--unset-upstream"}

WRITE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
PATH_KEYS = ("file_path", "notebook_path", "path")


def fleet_root(start):
    """The directory holding the clones, or None.

    Derived from git rather than from this file's path, because the hook may be
    installed from a worktree (`.work/<id>/<hq-repo>`), where walking up one
    level lands in the workspace instead of the fleet root.
    """
    try:
        out = subprocess.run(
            ["git", "-C", start, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return os.path.dirname(os.path.dirname(out.stdout.strip()))


def clone_of(path, root, is_clone):
    """The clone `path` is inside, or None if it is anywhere else.

    `.work/` is where work belongs, so anything under it is fine. So is anything
    outside the fleet root, and anything under a directory that is not a clone.
    """
    if not root:
        return None
    path = posixpath.normpath(path)
    root = posixpath.normpath(root)
    if path == root or not path.startswith(root + "/"):
        return None
    first = path[len(root) + 1:].split("/", 1)[0]
    if first == ".work" or first == "":
        return None
    return first if is_clone(root, first) else None


def is_clone_on_disk(root, name):
    return os.path.exists(os.path.join(root, name, ".git"))


def resolve(token, cwd):
    token = os.path.expanduser(token.strip("\"'"))
    if not os.path.isabs(token):
        token = posixpath.join(cwd, token)
    return posixpath.normpath(token)


def segments(command):
    """Split a command line on the separators that start a new command."""
    return [s for s in re.split(r"&&|\|\||[;|\n]", command) if s.strip()]


def words(segment):
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def git_target(argv, cwd):
    """(subcommand, args, directory it runs in) for a git invocation."""
    i, target = 1, cwd
    while i < len(argv):
        if argv[i] == "-C" and i + 1 < len(argv):
            target = resolve(argv[i + 1], target)
            i += 2
        elif argv[i].startswith("-"):
            i += 2 if argv[i] in ("-c", "--git-dir", "--work-tree") else 1
        else:
            return argv[i], argv[i + 1:], target
    return None, [], target


def bash_offence(command, cwd, root, is_clone):
    """(clone, what was attempted) for the first write into a clone, or None.

    Walks segments in order so a `cd` earlier in the line moves the directory the
    later segments run in, and so a token is only ever judged against the command
    it actually belongs to — an `ls` of a clone sitting beside an unrelated `rm`
    is not a delete of that clone.
    """
    for segment in segments(command):
        argv = words(segment)
        if not argv:
            continue

        if argv[0] == "cd" and len(argv) > 1:
            cwd = resolve(argv[1], cwd)
            continue

        if argv[0] == "git" or argv[0].endswith("/git"):
            sub, rest, target = git_target(argv, cwd)
            if sub is None:
                continue
            if sub in ("branch", "tag"):
                if not any(a in BRANCH_MUTATORS for a in rest):
                    continue
            elif sub == "pull":
                # A fast-forward of main is the refresh the clone exists for.
                if "--ff-only" in rest:
                    continue
            elif sub not in MUTATING_GIT:
                continue
            clone = clone_of(target, root, is_clone)
            if clone:
                return clone, "git {}".format(sub)
            continue

        if os.path.basename(argv[0]) in FILE_MUTATORS:
            for token in argv[1:]:
                if token.startswith("-"):
                    continue
                clone = clone_of(resolve(token, cwd), root, is_clone)
                if clone:
                    return clone, argv[0]
    return None


def refusal(clone, what, path=None):
    where = path or "this"
    return (
        "Refused: {} is inside the {} clone, and the clones are read-only.\n\n"
        "'{}' writes there. Every agent and engineer on this machine shares that "
        "clone — it is the refresh point and what worktrees are cut from, never a "
        "workspace. Work goes in .work/<work-id>/, one worktree per repo.\n\n"
        "Open or extend your workspace:\n"
        "    ./05-TOOLS/open-workspace.sh <work-id> {}\n"
        "then work in .work/<work-id>/{}/\n\n"
        "Reading the clone, git fetch, worktree add/list/remove, ./05-TOOLS/sync.sh "
        "and ./05-TOOLS/teardown-workspace.sh stay available.\n\n"
        "See 00-META/process/07-parallel-work.md, step 2."
    ).format(where, clone, what, clone, clone)


def decide(payload, root=None, is_clone=is_clone_on_disk):
    """Return a refusal reason for this tool call, or None to allow it."""
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()
    if root is None:
        root = fleet_root(cwd) or fleet_root(os.environ.get("CLAUDE_PROJECT_DIR", "."))

    if tool in WRITE_TOOLS:
        for key in PATH_KEYS:
            target = tool_input.get(key)
            if not target:
                continue
            clone = clone_of(resolve(target, cwd), root, is_clone)
            if clone:
                return refusal(clone, tool, target)
        return None

    if tool == "Bash":
        found = bash_offence(tool_input.get("command") or "", cwd, root, is_clone)
        if found:
            return refusal(found[0], found[1])
    return None


ROOT = "/r"
WORK = ROOT + "/.work/018-x"


def fake_clone(root, name):
    return name in {"hq", "gateway", "ops"}


# (tool, cwd, tool_input)
BLOCK = [
    ("Write", ROOT + "/hq", {"file_path": ROOT + "/hq/AGENTS.md"}),
    ("Edit", WORK + "/hq", {"file_path": ROOT + "/gateway/main.go"}),
    ("Edit", ROOT + "/hq", {"file_path": "04-ISSUES/066-x/00-report.md"}),
    ("NotebookEdit", ROOT + "/hq", {"notebook_path": ROOT + "/ops/x.ipynb"}),
    ("Bash", ROOT + "/hq", {"command": "git commit -m 'x'"}),
    ("Bash", ROOT + "/hq", {"command": "git add -A && git commit -m x"}),
    ("Bash", WORK + "/hq", {"command": "git -C " + ROOT + "/ops checkout -b foo"}),
    ("Bash", "/tmp", {"command": "cd " + ROOT + "/hq && git push origin main"}),
    ("Bash", ROOT + "/hq", {"command": "git switch main"}),
    ("Bash", ROOT + "/hq", {"command": "git stash"}),
    ("Bash", ROOT + "/hq", {"command": "git branch -D old-thing"}),
    ("Bash", ROOT + "/hq", {"command": "git pull"}),
    ("Bash", WORK + "/hq", {"command": "rm -rf " + ROOT + "/gateway/cmd"}),
    ("Bash", ROOT + "/hq", {"command": "mv AGENTS.md AGENTS.old.md"}),
    ("Bash", ROOT + "/hq", {"command": "git reset --hard origin/main"}),
]

ALLOW = [
    # The workspace: every write belongs here.
    ("Write", WORK + "/hq", {"file_path": WORK + "/hq/AGENTS.md"}),
    ("Edit", WORK + "/gateway", {"file_path": "main.go"}),
    ("Bash", WORK + "/hq", {"command": "git commit -m 'x' && git push"}),
    ("Bash", WORK + "/hq", {"command": "rm -rf " + ROOT + "/.work/018-x/ops"}),
    # What the clone is for.
    ("Bash", ROOT + "/hq", {"command": "git fetch origin"}),
    ("Bash", ROOT + "/hq", {"command": "git status -sb"}),
    ("Bash", ROOT + "/hq", {"command": "git log --oneline -5"}),
    ("Bash", ROOT + "/hq", {"command": "git ls-tree --name-only origin/main 04-ISSUES/"}),
    ("Bash", ROOT + "/hq", {"command": "git branch --list 018-x"}),
    ("Bash", ROOT + "/hq", {"command": "git pull --ff-only"}),
    ("Bash", ROOT + "/hq", {"command": "./05-TOOLS/sync.sh"}),
    ("Bash", ROOT + "/hq", {"command": "./05-TOOLS/open-workspace.sh 018-x ops"}),
    ("Bash", ROOT + "/hq", {"command": "./05-TOOLS/teardown-workspace.sh 018-x"}),
    ("Bash", ROOT + "/hq", {"command": "git worktree add -b 018-x " + WORK + "/hq origin/main"}),
    ("Bash", ROOT + "/hq", {"command": "git -C " + ROOT + "/ops worktree remove " + WORK + "/ops"}),
    ("Bash", ROOT + "/hq", {"command": "grep -r foo 04-ISSUES/"}),
    # A read of a clone beside an unrelated delete: the token belongs to the ls.
    ("Bash", ROOT + "/hq", {"command": "ls " + ROOT + "/gateway; rm -rf /tmp/scratch"}),
    # Outside the fleet root entirely.
    ("Write", "/tmp", {"file_path": "/tmp/scratch/notes.md"}),
    ("Bash", "/tmp/scratch", {"command": "rm -rf build && git commit -m x"}),
    # The fleet root itself is not a clone.
    ("Write", ROOT, {"file_path": ROOT + "/notes.md"}),
    ("Bash", ROOT, {"command": "echo 'never edit the shared hq clone directly'"}),
]


def self_test():
    failures = []
    for tool, cwd, tool_input in BLOCK:
        payload = {"tool_name": tool, "cwd": cwd, "tool_input": tool_input}
        if decide(payload, root=ROOT, is_clone=fake_clone) is None:
            failures.append("should BLOCK but allowed: {} {}".format(tool, tool_input))
    for tool, cwd, tool_input in ALLOW:
        payload = {"tool_name": tool, "cwd": cwd, "tool_input": tool_input}
        if decide(payload, root=ROOT, is_clone=fake_clone) is not None:
            failures.append("should ALLOW but blocked: {} {}".format(tool, tool_input))
    for f in failures:
        print(f)
    total = len(BLOCK) + len(ALLOW)
    print("{}/{} cases correct".format(total - len(failures), total))
    return 1 if failures else 0


def main():
    if "--self-test" in sys.argv:
        return self_test()

    try:
        payload = json.load(sys.stdin)
    except Exception:
        # A payload we cannot read is not evidence of a write to a clone. Allow,
        # rather than blocking every tool call the moment a format shifts.
        return 0

    try:
        reason = decide(payload)
    except Exception:
        return 0
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

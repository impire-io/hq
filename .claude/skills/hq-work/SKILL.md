---
name: hq-work
description: Use when starting, pushing, or landing any piece of work in this project — to open an isolated workspace, open the draft MR that claims it, declare cross-repo landing order, or tear the workspace down. Triggers on "start work on X", "set up a worktree", "open the MR", "mark the MR ready", "which repos does this land in", "what is everyone working on".
---

# hq-work

Keeps parallel work — several agents on one machine, several engineers on one fleet — isolated on disk and visible from the first push. **Authoritative playbook:** [`00-META/process/07-parallel-work.md`](../../../00-META/process/07-parallel-work.md); posture in [`00-META/how-we-build.md`](../../../00-META/how-we-build.md).

The forge group/org below (`<group>`) is the one configured in [`05-TOOLS/config.sh`](../../../05-TOOLS/config.sh), which also names the forge (GitHub or GitLab — MR below means merge request; read PR on GitHub); `<clone-root>` is the directory holding the shared clones, and `<hq-repo>` this repo's clone directory.

## The clones are read-only

`<clone-root>/<repo>` is shared with everyone on the machine: the refresh point, and what worktrees are cut from. Reading it, `git fetch`, a `--ff-only` fast-forward, `worktree add|list|remove`, `05-TOOLS/sync.sh` and `05-TOOLS/teardown-workspace.sh` are all fine there. Editing a file, committing, switching branches, pushing or deleting is **refused** by [`05-TOOLS/guard-readonly-clone.py`](../../../05-TOOLS/guard-readonly-clone.py). If you meet that refusal, you are in a clone: open a workspace, do not work around it.

## The work ID

One string is the branch name in **every** repo the work touches, the workspace directory name, and the MR label. **Take it only from a record that already exists** — never from one the work will produce:

- rooted in an hq design or issue → that record's number and slug (`018-cache-rework`)
- rooted in a code repo's spec-kit feature → that number and slug (`019-whoami-context`)
- anything else → a bare descriptive slug, no number (`check-refs-stale-trees`)

A slug is a first-class ID, not a fallback. An ADR or issue the work *produces* is numbered when written; the branch never renames. No `spec/`, `fix/`, or `feat/` prefix.

**Work spanning repos must be rooted in the hq repo** — per-repo spec-kit numbers differ, so unrooted cross-repo work has no single ID. If cross-repo work has no design or issue behind it, open an issue first (`hq-new-issue`); that number is the work ID.

## Starting work

1. **Check what is in flight:** `glab mr list --group <group>` (GitLab) / `gh search prs --owner <group> --state open` (GitHub). Under this playbook every started piece of work has an open MR, so this is the duplicate-work check. If it is already claimed, join it.
2. **Open the workspace with one command**, naming only the code repos the work touches:

   ```
   <clone-root>/<hq-repo>/05-TOOLS/open-workspace.sh <work-id> <repo> [repo...]
   ```

   One worktree per repo under `.work/<work-id>/`, all on branch `<work-id>`. **The hq repo is always included**, named or not — it holds the work item, the `lands:` block and the closing edit. **Needing another repo later is the same command run again**; repos already open are left alone. Where the branch exists on `origin`, the worktree is cut from it and tracks it, so you join that work rather than fork it.

   Do not hand-compose `worktree add` instead. The script derives the path, forces the branch name to equal the work id, and unsets the upstream that `worktree add` leaves pointing at main — the three things that drifted when this was a recipe.

3. **If the work spans repos**, add the ordered `lands:` block to the hq work item's frontmatter (`mr:` empty until each MR exists). Single-repo work gets no block.
4. **On the first push, open the draft MR** — it is the claim, not the finish line:

   ```
   # GitLab
   glab mr create --draft --push --yes --label "work/<work-id>" \
     --title "<work-id>: <what it does>" \
     --description "<hq-repo>: <path/to/work-item.md>
   Blocked by: <predecessor MR url, or none>"

   # GitHub
   git push -u origin <work-id>
   gh pr create --draft --label "work/<work-id>" \
     --title "<work-id>: <what it does>" \
     --body "<hq-repo>: <path/to/work-item.md>
   Blocked by: <predecessor MR url, or none>"
   ```

   Fill the MR number back into `lands:`.

## While working

Commit at every green checkpoint and push every commit. Refresh from `origin/main` daily; `--force-with-lease` after a rebase on a work branch, never on main.

## Landing work

5. **Mark the MR ready yourself** (`glab mr update --ready` / `gh pr ready`) the moment the quality gate is green — `make fmt && make test && make lint` — **and** every predecessor in `after:` has merged. Never earlier, and never left undone: a finished MR sitting in draft makes the human re-derive readiness; ready means they just read and merge.
6. **A human merges**, in `lands:` order where one exists.
7. **Tear down** once every MR of the item has merged: `<clone-root>/<hq-repo>/05-TOOLS/teardown-workspace.sh <work-id>`. It scopes every step to that one item.

## Do not

- Do not work in `<clone-root>/<repo>` directly — that clone is shared with every other agent on the machine, and a write to it is refused, not merely discouraged.
- **Do not delete anything wider than `.work/<work-id>/`.** `.work/` holds every other agent's in-flight worktrees, so `rm -rf .work`, `rm -rf .work/*`, or a loop over `.work/*/` destroys their work, including what they have not committed. This has happened. A PreToolUse hook now refuses those forms; use `05-TOOLS/teardown-workspace.sh` rather than composing an `rm` by hand.
- Do not hold a branch back from being pushed because it is unfinished. Push it as a draft.
- Do not flip to ready with an unmerged predecessor, and **never merge as an agent**.
- Do not leave a finished MR in draft — marking it ready is the agent's own closing move, not the reviewer's chore.
- Do not record cross-repo ordering as prose in a report — it goes in `lands:`.

---
name: hq-defer
description: Use when you notice a follow-up while doing something else and want to capture it without derailing — a task to do later, often in a different repo. Triggers on "defer this", "note this for later", "add a todo", "remember to X in repo Y", "capture this follow-up".
---

# hq-defer

Files a deferred **follow-up** as a `kind: task` record at the project's front door, in one step, so it isn't lost. **Authoritative playbook:** [`00-META/process/03-issues.md`](../../../00-META/process/03-issues.md). This removes the *ceremony* of filing (numbering, folders, frontmatter) — not the *judgment* of whether to file.

## Curate first — this is the whole point

**If it is polish or trivia, do not file it.** A backlog is only useful if being in it means something; filing every minor buries the few that matter. "Deferred, not filed" is the right outcome for most small things — leave them in the trail (the review, the diagnosis, the commit; git already holds them). Only reach for this skill once you have judged an item worth a future reader's attention when they next work in that repo.

Triaging a **batch** of deferrals (e.g. after a build review)? File the vital few, drop the rest into the trail, and — only if the dropped batch is large enough to be worth a pointer — file **one** rollup task ("~N minors triaged as polish; in the review history at `<ref>`"), never one record per item.

## Route by kind

- **A follow-up / maintenance task** (sync docs, rename, chase a dependency, hand a design off to build) → file it here, steps below.
- **A defect** ("something's wrong") → this is a `kind: bug`; use [`hq-new-issue`](../hq-new-issue/SKILL.md).
- **A question worth investigating** → this is research; use [`hq-new-research`](../hq-new-research/SKILL.md).
- **A design already decided but unbuilt** → usually needs no record; it is visible via its `status:`/`code:`. File a task only if it is genuinely at risk of being forgotten.

## Steps

1. **Check for a duplicate.** `grep` across `04-ISSUES/` — resolved included — for the follow-up; if it already exists, add to it rather than opening a second.
2. Mint it in one line: `05-TOOLS/allocate-issue.sh <short-name> --kind task --located-in <repo> --symptom "<what to do and why it was deferred>"` (optionally `--feature <name>` for the `06-FEATURES/` doc it belongs to, and `--discovered-while "<path, issue NNN, or MR>"`). Committed straight to `origin/main`, next number taken atomically — mid-flow capture no longer even needs a branch.

## Next

It now shows up in `hq-status` — in the triage board and under its repo in the **outstanding by repo** view, which is where you pick it up when you next work in that repo. Resolve it through step 4 of playbook 03 (`05-TOOLS/set-issue.sh <NNN> status=resolved`, or by MR when it needs `fixed-by:` entries); a task skips diagnosis. Re-triage it the same way — `set-issue.sh <NNN> priority=low` is one commit to main, not an MR.

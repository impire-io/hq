---
name: hq-diagnose
description: Use when investigating an open hq issue to reproduce it, localize the owning repo, and record the trail. Triggers on "diagnose issue NNN", "where does this bug live", "which repo owns this symptom".
---

# hq-diagnose

Reproduces and localizes a reported issue. **Authoritative playbook:** [`00-META/process/03-issues.md`](../../../00-META/process/03-issues.md). The hq repo is the one place that sees the whole system, so diagnosis starts here; the fix lands in the owning code repo.

## Steps

1. **Diagnose.** Use [`00-META/repos.md`](../../../00-META/repos.md) and the design docs' `code:` fields to see the system's shape. Reproduce and localize. Record the trail — hypotheses, evidence, dead ends — in `04-ISSUES/NNN-short-name/01-diagnosis.md`.
2. **Track status** with [`05-TOOLS/set-issue.sh`](../../../05-TOOLS/set-issue.sh), which commits the frontmatter change straight to main: `set-issue.sh <NNN> status=diagnosing` while working; `set-issue.sh <NNN> status=located located-in=repo,repo` once the owner is known; `set-issue.sh <NNN> status=blocked blocked-by="<an issue/MR ref or plain prose>"` when the issue cannot move — setting the prior status again clears `blocked-by:` when the blocker lifts. Never edit these fields by hand in the workspace; only `01-diagnosis.md` and the report body land by MR.
3. **Resolve:**
   - Implementation bug → hand the fix to the owning repo's spec-kit bugfix flow; record `fixed-by:` (PR/spec links) on the report.
   - Design gap or ambiguity → amend the design **first** with the **`hq-amend-design`** skill, record `amended-design:` (the design doc path); the code fix then follows via the **`hq-handoff`** skill.
4. **Close.** `set-issue.sh <NNN> status=resolved` (or `status=wontfix`, with the reasoning already in the report) stamps `resolved:`, drops `claimed-by:` and `claimed:`, and refuses if a `fixed-by:` ref does not verify — a terminal record carries no claim. A close that still needs `fixed-by:` entries written goes by MR instead. Closed issues are **kept forever** — they are the project's symptom→component memory.

## Do not

- Do not fix a design gap by quietly diverging in the code repo — the design in the hq repo leads, the code follows.
- Do not delete a closed issue.

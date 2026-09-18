---
name: hq-new-issue
description: Use when something in the project is wrong and needs reporting — even, especially, when the repo that owns the problem is unknown. Triggers on "file a bug", "something's broken", "report an issue", "X isn't working".
---

# hq-new-issue

Opens an issue at the project's single front door. **Authoritative playbook:** [`00-META/process/03-issues.md`](../../../00-META/process/03-issues.md). Reporting requires **no** localization — several repos are often suspects at once, and diagnosis happens later where the whole system is visible.

## Steps

1. **Check for a duplicate first.** `grep` across `04-ISSUES/` — resolved issues included — for the symptom. The kept-forever corpus is the project's symptom→component memory; if this was seen before, link that prior issue in the new report, and if it is the same still-open problem, add to it instead of opening a second.
2. Mint the record: `05-TOOLS/allocate-issue.sh <short-name> --symptom "<the symptom in plain terms and how it was observed>"` (add `--priority high|low` when triage warrants, `--feature <name>` when the feature it belongs to is clear — a doc in `06-FEATURES/` — and `--claim` when you will work it yourself). It commits a minimal real report straight to `origin/main`, taking the next number atomically — no number to find, no collision to renumber. The printed ID is the work ID. Expand the report (how it was observed, links to the duplicate check) by MR from the workspace when there is more to say.

   This skill is the front door for a **defect**. For a **known follow-up** deferred while doing something else (`kind: task`), use [`hq-defer`](../hq-defer/SKILL.md) instead — it files the same kind of record in one line with the repo already set.

## Do not

- Do not try to guess the owning repo in the report — that is the diagnosis step. Leave `located-in` out until then.
- Do not add `fixed-by` or `amended-design` yet.

## Next

Localize and resolve it with the **`hq-diagnose`** skill.

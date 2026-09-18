---
name: hq-amend-design
description: Use when an hq design doc must change — driven by a research outcome, an issue diagnosis, or a direct decision rooted in 00-META. Triggers on "amend the design", "update the design doc", "the design is wrong/incomplete".
---

# hq-amend-design

Changes an authoritative design doc. **Authoritative playbook:** [`00-META/process/02-graduation.md`](../../../00-META/process/02-graduation.md) (the "Amending a design" section).

## Steps

1. **Record the decision first** if the change settles something significant: next-numbered `03-DECISIONS/NNNN-short-name.md`. Decision records are **immutable** — supersede, never rewrite.
2. **Edit the design doc(s).** Prose and diagrams only, no code. If the amendment **retracts** a design entirely, set `status: abandoned` and add a banner line at the top — the doc stays, never deleted.
3. **`updated:` changes only on implementation-status flips**, not for text edits. Amending wording alone does not touch `updated:`.
4. **If code already implements the old design**, the amendment leads and the code follows: route the fix through the **`hq-handoff`** skill in the owning repo.
5. Run the **`hq-sync-docs`** skill (playbook 05) — if the project keeps a derived docs site.

## Do not

- Do not edit a decision record's meaning. A changed decision is a new record.
- Do not bump `updated:` just because you edited prose.
- Do not let the code repo diverge from the design — the hq repo is the source of truth; the amendment happens here first.

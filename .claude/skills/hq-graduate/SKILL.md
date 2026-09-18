---
name: hq-graduate
description: Use when an hq research effort concludes and its outcome must become design, land as an artifact, or be abandoned. Triggers on "graduate the research", "this research is done", "close effort NNN", "turn the research into design".
---

# hq-graduate

Closes a research effort and records where it went. **Authoritative playbook:** [`00-META/process/02-graduation.md`](../../../00-META/process/02-graduation.md) — read it; this skill is the mechanical checklist.

An effort ends in exactly one of three ways. Pick the one that happened.

## Graduating research → design

1. **Check alignment** against `00-META` (`mission.md`, `how-we-build.md`). If the conclusion does not align, it does not graduate — reconsider or abandon.
2. **Record the decision** as the next-numbered record in `03-DECISIONS/NNNN-short-name.md` (4-digit, next free number, never reuse). Capture context, decision, alternatives rejected, consequences. **Records are immutable once made** — a later change is a new record, never an edit.
3. **Write the design** in `02-DESIGN/` (new doc or amendment). Prose and diagrams only, **no code**. A new doc starts with frontmatter `status: designed` and **no** `code:` field.
4. **Close the effort:** set the research `00-overview.md` frontmatter to `status: graduated` with `became:` pointing at the design doc.
5. Run the **`hq-sync-docs`** skill (playbook 05) — if the project keeps a derived docs site.

## Concluding research → artifact

Same as above, but the outcome is a document in `99-ARTIFACTS/`, and the effort closes `status: concluded-artifact` with `became:` pointing there. A decision record is needed only if something project-relevant was settled.

## Abandoning research

Set `status: abandoned`, state why in the overview, and point `became:` at whatever superseded it (if anything). **Keep everything** — abandoned research is the record of why we did not proceed.

## Do not

- Do not edit an existing decision record to change its meaning. Supersede with a new one.
- Do not put code in `02-DESIGN`.
- Do not delete the research folder. It stays forever.

# Playbook 02 — graduation & design change

**Trigger:** a research effort has concluded, or a design must change — from research, from an issue diagnosis ([playbook 03](03-issues.md)), or from a direct decision.
**Who:** an engineer decides; engineer or agent executes.

## Graduating research into design

1. Check the conclusion against `00-META` (mission, how-we-build). If it does not align, it does not graduate.
2. Record the decision as the next-numbered record in `03-DECISIONS/`: context, decision, alternatives rejected, consequences. Records are immutable once made.
3. Write the design in `02-DESIGN` — new docs or amendments to existing ones. Prose and diagrams only, no code. New docs start with frontmatter `status: designed` and no `code:` field.
4. Close the research effort: set its `00-overview.md` frontmatter to `status: graduated` with `became:` pointing at the design.
5. Run [playbook 05](05-external-sync.md).

## Concluding research into an artifact

As above, but the conclusion lands as a document in `99-ARTIFACTS` and the effort closes `concluded-artifact` with `became:` pointing there. A decision record is only needed if something project-relevant was settled.

## Abandoning research

Set `status: abandoned`, state why in the overview, and point `became:` at whatever superseded it, if anything. Keep everything.

## Amending a design

1. If the change settles something significant, record it in `03-DECISIONS` first.
2. Edit the design doc(s). If the amendment retracts a design entirely, set `status: abandoned` and put a banner line at the top of the doc; the doc stays.
3. `updated:` in frontmatter changes only on implementation-status flips — not for text edits.
4. If code already implements the old design, the amendment leads and the code follows: route the fix through [playbook 04](04-build-handoff.md) in the owning repo.
5. Run [playbook 05](05-external-sync.md).

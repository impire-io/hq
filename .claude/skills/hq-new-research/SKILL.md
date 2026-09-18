---
name: hq-new-research
description: Use when starting a new research effort in the hq repo — an idea, technology, or approach worth investigating before it is committed to design. Triggers on "research X", "investigate X", "spike X", "should we use X".
---

# hq-new-research

Scaffolds a new research effort. **Authoritative playbook:** [`00-META/process/01-research.md`](../../../00-META/process/01-research.md) — read it; this skill only does the mechanical setup.

## Steps

1. Find the next free number: list `01-RESEARCH/NNN-*` folders, take the highest `NNN` + 1, zero-padded to 3 digits.
2. Create `01-RESEARCH/NNN-descriptive-name/` (kebab-case name from the topic).
3. Create `00-overview.md` in it with exactly this frontmatter, then a short prose summary of **what** is being investigated, **why**, and **what it touches**:

   ```yaml
   ---
   status: active
   ---
   ```

4. Do the actual research in additional docs in the same folder (notes, surveys, option analyses, draft designs — anything goes). Keep the overview's summary current as the effort changes shape.

## Do not

- Do not add `became:` yet — that field is set only when the effort closes, via the `hq-graduate` skill.
- Do not skip a sequence number. Use the next available one.
- Do not create a status file. Status lives only in the overview's frontmatter.

## Closing

An effort never just stops — it closes through the `hq-graduate` skill (playbook 02) as `graduated`, `concluded-artifact`, or `abandoned`, always with `became:` pointing at what it turned into. Nothing is deleted.

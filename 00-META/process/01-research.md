# Playbook 01 — research

**Trigger:** an idea, technology, or approach worth investigating before committing it to design.
**Who:** an engineer starts it; engineer or agent works it.

## Steps

1. Take the next free number `NNN` in `01-RESEARCH/` and create `NNN-descriptive-name/`.
2. Create `00-overview.md`: a short summary of what is being investigated, why, and what it touches, with frontmatter:

   ```yaml
   ---
   status: active
   ---
   ```

3. Work the research in additional documents in the folder. Anything goes here: notes, surveys, option analyses, draft designs.
4. Keep the overview's summary current as the effort changes shape.
5. Close the effort through [playbook 02](02-graduation.md). It ends `graduated`, `concluded-artifact`, or `abandoned` — always with `became:` pointing at what it turned into. Nothing is deleted; closed research is the record of why we did or didn't proceed.

## Output

A self-contained effort folder whose `00-overview.md` frontmatter always states where the effort stands.

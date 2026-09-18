# 01-RESEARCH

This folder contains all research efforts — active investigations and historical ones — for topics that have not yet been solidified into design.

## Purpose

- Explore ideas, technologies, and approaches relevant to the project.
- Analyse options before committing them to the authoritative design.
- Provide a clear record of what was investigated, why, and what came of it.

## Structure

Each research effort lives in its own subfolder. Folder names follow this convention:

```
NNN-descriptive-name/
```

Where `NNN` is a zero-padded sequence number (e.g. `001`, `002`, `042`).

Example: `001-storage-engine-eval/`

## Required Files per Effort

Every research folder **must** contain a `00-overview.md`: a short summary of the effort (what is being investigated, why, what it touches), with status in YAML frontmatter:

```yaml
---
status: active | graduated | concluded-artifact | abandoned
became:            # required when status is terminal — what the effort turned into
feature:           # optional — the 06-FEATURES doc this effort belongs to (file name without .md)
---
```

## Lifecycle

| status | Meaning |
|--------|---------|
| `active` | Investigation in progress. |
| `graduated` | Analysis against `00-META` confirmed alignment; the design lives in `02-DESIGN` (see `became:`). |
| `concluded-artifact` | Concluded into an outward-facing document in `99-ARTIFACTS` (see `became:`). |
| `abandoned` | Stopped or superseded; not pursued further. Nothing is deleted. |

Starting and closing efforts is playbook territory: [`00-META/process/01-research.md`](../00-META/process/01-research.md) and [`02-graduation.md`](../00-META/process/02-graduation.md).

## Rules

- All files must be Markdown.
- Do not skip sequence numbers — use the next available number.
- Each effort is self-contained in its own folder.

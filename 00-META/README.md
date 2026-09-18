# 00-META

This folder is the **northern star** of the project. It contains the mission statement and foundational project information that all research and design decisions must align with.

## Purpose

- Define what the project is and what it aims to accomplish.
- Establish the core principles and constraints that govern the project.
- Serve as the reference point when evaluating whether research or design is on track.

## Contents

| File / folder | What it is |
|---|---|
| `mission.md`, `context.md`, `effect.md` | What the project is, the world it lives in, the effect it aims for. |
| `how-we-build.md` | The engineering postures, backed by the records in [`../03-DECISIONS`](../03-DECISIONS/). |
| [`how-we-deploy.md`](how-we-deploy.md) | How a built service reaches a running environment — the release and deploy flows, and what is expected to bring one up. |
| [`repos.md`](repos.md) | The map of every project repository and what each owns. |
| [`process/`](process/) | The playbooks — how work moves through this repo, for engineers and agents alike. |

## Rules

- All files must be Markdown.
- Content here is **stable by nature** — changes should be deliberate and reflect a genuine shift in project mission, not day-to-day iteration.
- Research and design work should be traceable back to the mission defined here.

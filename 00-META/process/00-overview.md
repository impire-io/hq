# Process — overview

How work moves through the hq repo, and who may do what. Every other document in this folder is a playbook: trigger, who runs it, steps, outputs. Engineers and agents follow the same playbooks; agents must not act outside them.

## The audiences

| Audience | Contract |
|---|---|
| **Engineers** | Read and write everything. The hq repo is the single source of truth for mission, research, design, decisions, and issue diagnosis. |
| **AI agents** | The same rights as engineers, exercised through these playbooks. |
| **External readers** | Read the project's derived docs site (if it keeps one), never this repo. External is strictly downstream: no decision is ever made or first recorded there. |

## The knowledge flow

```
idea ──► 01-RESEARCH ──► decision (03-DECISIONS) ──► 02-DESIGN ──► spec-kit spec ──► implemented
 │            │  │                                                  (code repo)
 │            │  └──► artifact (99-ARTIFACTS)
 │            └────► abandoned (recorded, kept)
 └─(small/obvious, decision recorded)──────────────► 02-DESIGN directly

bug/symptom ─────────► 04-ISSUES ──► diagnosis ──► code-repo fix and/or design amendment
deferred follow-up ──► 04-ISSUES (kind: task, no diagnosis) ──► done in its repo
```

## The playbooks

| # | Playbook | Trigger |
|---|---|---|
| [01](01-research.md) | Research | An idea worth investigating before committing to design |
| [02](02-graduation.md) | Graduation & design change | Research concludes, or a design must change |
| [03](03-issues.md) | Issues | Something needs doing — a defect (owner often unknown), or a deferred follow-up (`kind: task`) |
| [04](04-build-handoff.md) | Build handoff | A design is ready to be built |
| [05](05-external-sync.md) | External sync *(optional)* | The hq repo changed something the derived docs site retells |
| [06](06-builder-skill-sync.md) | Builder-skill sync *(optional)* | A contract a derived builder skill teaches changed in the repo that owns it |
| [07](07-parallel-work.md) | Parallel work | Any piece of work is about to start — how it is isolated, pushed, and landed |

Playbooks 05 and 06 apply only to a project that keeps those derived views (a plain-language docs site, a builder-skills marketplace). A project without them deletes both playbooks and the steps that reference them.

Playbook 07 is the odd one out: it is not a stage of the knowledge flow but the mechanics **every** other playbook runs on. Whenever a playbook says work happens in a repo, 07 says where on disk, how it is pushed, and how it lands.

## Status lives in frontmatter

Research overviews, design docs, and issue reports each carry their status as YAML frontmatter (schemas in the section READMEs and playbooks). There are **no central status files**; cross-cutting views — a status matrix, derived-site badges — are generated from frontmatter, never hand-maintained.

The same records carry `feature:` — the [`06-FEATURES/`](../../06-FEATURES/) doc they belong to. A feature is the thread through the stages above: the level people ask about ("where do we stand with Workloads?") and the level the roadmap orders. Its doc is prose only; its state is derived from its members, and the roadmap is the numbered list in [`06-FEATURES/README.md`](../../06-FEATURES/README.md). Set the field at filing (`allocate-issue.sh --feature`), by `set-issue.sh feature=` on an issue, or with the frontmatter on a research or design doc.

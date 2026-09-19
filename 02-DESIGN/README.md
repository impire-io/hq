# 02-DESIGN

This folder is the **authoritative design specification** for the project. All implementation work is built against the content here.

## Purpose

- Document what the project does and how it works, functionally.
- Provide a stable reference for implementation decisions.
- Capture graduated research as concrete, agreed-upon design.

## Implementation status

A design being settled says nothing about whether it is built. Every design doc that **states a contract** carries YAML frontmatter tracking that third axis:

```yaml
---
status: designed | in-progress | implemented | abandoned
code: [svc-a]            # owning code repo(s); set at build handoff, omitted before
updated: 2026-07-13      # date of the last status change (not of text edits)
feature: gateway         # optional — the 06-FEATURES doc this design belongs to (file name without .md)
lands:                   # cross-repo builds only; the declared landing order
  - { repo: svc-a, mr: "!10", after: [] }
  - { repo: svc-b, mr: "!20", after: [svc-a] }
---
```

`lands:` states the *plan* — which repos the build lands in and in what order — written at build handoff, with `mr:` filled in as each MR opens. A single-repo build omits it; the forge stays authoritative for live state. See playbook [`00-META/process/07-parallel-work.md`](../00-META/process/07-parallel-work.md).

**A doc that only aggregates carries no frontmatter at all** — the READMEs, and a layer or cluster overview whose job is framing, reading order, and what lives elsewhere. It has no contract of its own, so a status on it is either a duplicate of its siblings' or wrong about them, and it is one more thing to remember to flip. Its state is read from the docs it points at.

The test is what the doc does, not what it is called. A doc *named* as an overview that in fact states a contract — a decision procedure, a wire grammar, evaluation semantics — is something someone builds and claims, so it carries a status. A doc that is genuinely framing and reading order does not, whatever its name.

Status changes when **implementation state** changes — a service ships, a runtime lands — never because design text was edited. An `implemented` claim must be defensible from the owning repo's main branch, not from intent. An `abandoned` design keeps its doc, with a banner line at the top. Cross-cutting overviews (a status matrix, derived-site badges) are **generated** from this frontmatter, never hand-maintained. Every status flip triggers the external-sync playbook ([`00-META/process/05-external-sync.md`](../00-META/process/05-external-sync.md)).

## Organisation

Group designs into subfolders by logical domain — for example a foundation layer, the services on top of it, and the first-party clients. Each subfolder may carry an aggregating README (no frontmatter) that gives the reading order.

## What Belongs Here

- Functional analysis documents
- Feature specifications
- Architectural descriptions (no code — prose and diagrams only)

Subfolders are allowed and encouraged to organise content by logical domain or concern.

## What Does Not Belong Here

- Code or pseudocode
- Speculative ideas or open questions (those belong in `01-RESEARCH`)
- Raw research notes

## Rules

- All files must be Markdown.
- Content here represents **decisions already made**, not options being evaluated.
- Changes to design should be traceable back to a completed research effort or a direct decision rooted in `00-META`.

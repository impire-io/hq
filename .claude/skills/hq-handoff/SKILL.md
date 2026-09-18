---
name: hq-handoff
description: Use when an hq design is ready to be built, or must be rebuilt after an amendment, in its owning code repo. Triggers on "hand this off to build", "start building the design", "this design is ready to implement".
---

# hq-handoff

Documents the handoff of a design to its owning code repo. **Authoritative playbook:** [`00-META/process/04-build-handoff.md`](../../../00-META/process/04-build-handoff.md). The hq repo documents the handoff; the code repos run spec-kit — spec-kit is referenced, not absorbed here.

## Steps

1. Identify the owning code repo(s) via [`00-META/repos.md`](../../../00-META/repos.md).
2. In the **owning repo**, create the spec-kit spec. It must cite the hq design doc by **path and commit hash**.
3. Check the repo's constitution against the design. A conflict is resolved in the hq repo **first** (via `hq-amend-design`) — never by quietly diverging in the code repo.
4. In the design doc's frontmatter: set `code:` to the owning repo(s), `status: in-progress`, and `updated:` to today's date.
5. Build in the code repo through its spec-kit flow.
6. When the design's core contract runs on the owning repo's **main branch**, set `status: implemented` and `updated:`. The claim must be defensible **from main**, not from intent.
7. Run the **`hq-sync-docs`** skill after every status flip — if the project keeps a derived docs site.

## Do not

- Do not mark `implemented` from a feature branch or from intent — only when it holds on main.
- Do not resolve a design/constitution conflict in the code repo; fix the design in the hq repo first.

# Playbook 04 — build handoff

**Trigger:** a design in `02-DESIGN` is ready to be built, or must be re-built after an amendment.
**Who:** an engineer initiates; an agent executes in the owning code repo.

The hq repo documents the handoff; the code repos run spec-kit. Spec-kit is referenced, not absorbed.

## Steps

1. Identify the owning code repo(s) via [`../repos.md`](../repos.md). If the
   fleet keeps a shared bootstrap library or service framework, a new service
   builds on it rather than re-rolling the plumbing — name that convention in
   [`../how-we-build.md`](../how-we-build.md) once it exists.
2. Open the workspace via [playbook 07](07-parallel-work.md) — one worktree per owning repo, all on the design's work ID.
3. In the owning repo, create the spec-kit spec. It must cite the hq design doc by **path and commit hash**.
4. Check the repo's constitution against the design. A conflict is resolved in the hq repo first ([playbook 02](02-graduation.md)) — never by quietly diverging in the code repo.
5. In the design doc's frontmatter: set `code:` to the owning repo(s), `status: in-progress`, and `updated:` to today. When the build spans more than one repo, add the ordered `lands:` block ([playbook 07](07-parallel-work.md)) — the landing order is declared here, never left as prose.
6. Build in the code repo through its spec-kit flow, pushing to a draft MR from the first commit ([playbook 07](07-parallel-work.md)).
7. When the design's core contract runs on the owning repo's **main branch**, set `status: implemented` and `updated:`. The claim must be defensible from main, not from intent.
8. Run [playbook 05](05-external-sync.md) after every status flip.
9. If the project keeps a derived builder-skills repo and the built contract is one its skills teach, run [playbook 06](06-builder-skill-sync.md). That repo's `DERIVATION.md` says which contracts those are.
10. Tear the workspace down once every MR of the work item has merged ([playbook 07](07-parallel-work.md)).

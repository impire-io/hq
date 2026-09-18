# HQ — the source-of-truth repository

This repository is the single source of truth for the project's mission, research, design, decisions, and issue diagnosis. Implementation lives in the code repos beside it (the *fleet*); this repo holds what they are built against.

> **Starting from the template?** This repo begins as a skeleton. Run the `hq-setup` skill in Claude Code — it asks for the project's name, GitLab host and group, writes [`05-TOOLS/config.sh`](05-TOOLS/config.sh), seeds [`00-META/repos.md`](00-META/repos.md), and walks you through filling in the mission, context, and effect documents. Everything the wizard writes can also be edited by hand.

## Getting the code, and keeping it current

The hq repo is the one repository you clone by hand; [`05-TOOLS/sync.sh`](05-TOOLS/sync.sh) keeps the rest of the fleet beside it up to date.

```
git clone git@<forge-host>:<group>/<hq-repo>.git <clone-root>/<hq-repo>
<clone-root>/<hq-repo>/05-TOOLS/sync.sh
```

**Run it whenever you want the fleet current, not only on day one.** Setting up a machine is just the case where every repository happens to be missing: the script clones what is missing, fast-forwards what is clean, and leaves everything else alone. It keeps no state between runs, so there is no wrong moment to run it.

It needs `git`, [`glab`](https://gitlab.com/gitlab-org/cli), `jq`, and an SSH key on the GitLab host — it reports whatever is missing and installs nothing. It discovers the repositories from the GitLab group and its subgroups (configured in `05-TOOLS/config.sh`), so a repository added to the group appears on its own, and a subgroup becomes a directory beside the other clones. It only ever fast-forwards a clean clone sitting on its default branch; anything dirty or on a work branch is fetched and then left untouched, which is what makes it safe to run while other people's — and other agents' — work is in progress. Use `--dry-run` to see what it would do, and `--root` to put the clones somewhere other than this repo's parent.

Workspaces for actual work are a separate matter — one worktree per repo under `.work/<work-id>/`, per [playbook 07](00-META/process/07-parallel-work.md).

## Audiences

| Audience | What they do here |
|---|---|
| **Engineers** | Read and write everything. This repo is where truth lives. |
| **AI agents** | The same, always through the playbooks in [`00-META/process/`](00-META/process/). |
| **External readers** | Nothing — if the project keeps a derived plain-language docs site, they read that. No decision is ever made or first recorded there. |

## Repository structure

| Folder | Purpose |
|--------|---------|
| [`00-META`](00-META/) | Mission, principles, how we build, the repo map, and the process playbooks. The northern star for all decisions. |
| [`01-RESEARCH`](01-RESEARCH/) | Active and historical research efforts. Ideas not yet solidified into design. |
| [`02-DESIGN`](02-DESIGN/) | The authoritative design specification. Implementation is built against this. |
| [`03-DECISIONS`](03-DECISIONS/) | Decision records — numbered, immutable, superseded but never edited. The "why" trail behind META and DESIGN. |
| [`04-ISSUES`](04-ISSUES/) | The single front door for "something is wrong". Triage and cross-repo diagnosis records. |
| [`05-TOOLS`](05-TOOLS/) | The executable tree — every checked-in tool, from workspace rails to the atomic allocator, and the project's `config.sh`. |
| [`06-FEATURES`](06-FEATURES/) | One plain-language document per feature — what it is and provides — and the roadmap: the order we pursue them in. Membership and status are read from the records, never written here. |
| [`99-ARTIFACTS`](99-ARTIFACTS/) | Derived, outward-facing documents. Downstream only — never a source of decisions. |

## The flow

```
idea ──► 01-RESEARCH ──► decision (03-DECISIONS) ──► 02-DESIGN ──► spec-kit spec ──► implemented
 │            │  │                                                  (code repo)
 │            │  └──► artifact (99-ARTIFACTS)
 │            └────► abandoned (recorded, kept)
 └─(small/obvious, decision recorded)──────────────► 02-DESIGN directly

bug/symptom ──► 04-ISSUES ──► diagnosis ──► code-repo fix and/or design amendment
```

Implementation lives in the code repos (see [`00-META/repos.md`](00-META/repos.md)); how far each design is implemented is tracked in that design doc's frontmatter. A research effort, a design, or an issue names the feature it belongs to with `feature:` in that same frontmatter, and [`06-FEATURES`](06-FEATURES/) is where a feature is described and the roadmap ordered; where a feature stands is derived from its members (`05-TOOLS/status.sh --roadmap`).

## Rules

- All files in the numbered content folders are **Markdown only**; [`05-TOOLS`](05-TOOLS/) is the executable tree.
- Do not create new top-level folders without explicit confirmation.
- Status lives in document frontmatter, never in central status files. Cross-cutting status overviews (matrices, badges) are generated, not maintained.
- Every workflow is a playbook in [`00-META/process/`](00-META/process/) — follow them.

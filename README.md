# HQ — the source-of-truth repository

This repository is the single source of truth for the project's mission, research, design, decisions, and issue diagnosis. Implementation lives in the code repos beside it (the *fleet*); this repo holds what they are built against.

**New here?** Start at [Getting started](#getting-started) — it covers both starting a project from this template and joining one that already has an hq.

## Getting started

There are two ways in: you are **starting a project** from this template, or you are **joining a project** that already has an hq. Both end in the same place — a clone you never edit, a workspace you do edit, and the fleet's code repos beside them. Read the three short sections first; that is where people get stuck.

### What you need on the machine

- `git`, `bash` and `python3`. The tools in [`05-TOOLS/`](05-TOOLS/) are shell scripts and the guard hooks are Python; there is nothing more to install.
- [Claude Code](https://claude.com/claude-code). The skills (`/hq-setup`, `/hq-work`, …) and the hooks are built for it. Everything they do can also be done by hand with the playbooks in [`00-META/process/`](00-META/process/).
- The forge CLI, logged in: [`gh`](https://cli.github.com) on GitHub (`gh auth login`), or [`glab`](https://gitlab.com/gitlab-org/cli) plus `jq` on GitLab (`glab auth login --hostname <host>`).
- An SSH key registered on the forge host. The clones use SSH.

### Where things go on disk

The directory that holds the hq clone is the project's root. [`05-TOOLS/sync.sh`](05-TOOLS/sync.sh) clones the code repos into it, and workspaces open under its `.work/`. Give each project a directory of its own, and put nothing else in it.

```
<clone-root>/                  one per project
├── <hq-repo>/                 the hq clone — read-only, the refresh point
├── <code-repo>/               the code repos, cloned by 05-TOOLS/sync.sh
└── .work/<work-id>/           one workspace per piece of work
    ├── <hq-repo>/             a worktree on branch <work-id>
    └── <code-repo>/           one per repo the work touches
```

### The clones are read-only

Every clone under the root is shared by everyone on the machine, so editing, committing, branching and pushing in one is **refused** by a Claude Code hook, not merely discouraged; by hand, the rule is the same. Work happens in a workspace: one command opens it, with one worktree per repo on a branch named for the work.

```
<clone-root>/<hq-repo>/05-TOOLS/open-workspace.sh <work-id> [code-repo...]
cd <clone-root>/.work/<work-id>/<hq-repo>
```

This includes the very first change to a fresh instance. A session opened in a clone is told so at the start; if a write is refused, you are in a clone — open a workspace, do not work around it. The full mechanics are [playbook 07](00-META/process/07-parallel-work.md).

### Starting a new project from the template

**1. Make your copy.** This is a plain repository, not a forge template: clone it under a fresh root, keep the template as a remote named `template`, and push `main` to a new repository of your own. On GitHub:

```
mkdir ~/atlas && cd ~/atlas                              # the project's root, nothing else in it
git clone git@github.com:impire-io/hq.git atlas-hq
cd atlas-hq
git remote rename origin template
gh repo create my-org/atlas-hq --private --source=. --remote=origin --push
```

On GitLab, or any other forge, create an empty project there first, then point `origin` at it:

```
git remote rename origin template
git remote add origin git@gitlab.example.com:my-group/atlas-hq.git
git push -u origin main
```

**2. Open a workspace and run the setup wizard.** The clone you just made is read-only like any other, so configuration happens in a workspace — name it `setup`:

```
./05-TOOLS/open-workspace.sh setup
cd ../.work/setup/atlas-hq
claude
```

In Claude Code, run **`/hq-setup`**. It asks for the project's name, the forge and its org or group, the code repos you already have, the template's URL, and who merges a ready MR; it writes [`05-TOOLS/config.sh`](05-TOOLS/config.sh) and [`00-META/repos.md`](00-META/repos.md), records the template commit for later upgrades, interviews you for the mission, context and effect documents, sets this README's title, and offers to delete the other forge's CI file. Everything it writes can be edited by hand afterwards.

It ends by listing what only you can do on the forge: a rule on `main` that lets the three direct-to-main tools push, and the read-only token the CI fleet checks need (`HQ_FLEET_TOKEN`, see `05-TOOLS/check-refs.sh --help`). Until that token exists, those checks fail once `config.sh` names a group.

**3. Land it.** Commit in the workspace, push, open a pull request, and merge it — this is the one piece of work with no predecessor and no one else to wait for:

```
git status                                               # what the wizard wrote
git add -A && git commit -m "setup: configure atlas-hq"
git push -u origin setup
gh pr create --title "setup: configure atlas-hq" --body "Initial configuration."   # glab mr create --push --yes on GitLab
```

After the merge, fast-forward the clone (`git pull --ff-only` in it — a fast-forward is one of the things a clone is for) and remove the workspace:

```
cd ~/atlas/atlas-hq && git pull --ff-only
./05-TOOLS/teardown-workspace.sh setup
```

**4. Bring in what exists.** From the clone, `./05-TOOLS/sync.sh` clones every repository in the configured org or group beside it. If the project already has decision records, design docs or a backlog, open a workspace and run **`/hq-migrate`**: it routes each kind into the numbered structure, with the curation this repo's rules demand.

### Joining a project that already has an hq

The hq repo is the one repository you clone by hand; `sync.sh` fetches the rest of the fleet beside it.

```
mkdir ~/atlas && cd ~/atlas
git clone git@<forge-host>:<group>/<hq-repo>.git
<hq-repo>/05-TOOLS/sync.sh
```

**Run `sync.sh` whenever you want the fleet current, not only on day one.** Setting up a machine is just the case where every repository happens to be missing: the script clones what is missing, fast-forwards what is clean, and leaves everything else alone. It keeps no state between runs, so there is no wrong moment to run it. It discovers the repositories from the org or group in `05-TOOLS/config.sh` (GitLab subgroups included, mirrored as directories), reports whatever prerequisite is missing and installs nothing, and only ever fast-forwards a clean clone sitting on its default branch — anything dirty or on a work branch is fetched and then left untouched, which is what makes it safe to run while other people's, and other agents', work is in progress. Use `--dry-run` to see what it would do, and `--root` to put the clones somewhere other than this repo's parent.

### Your first piece of work

Every change, in the hq repo or a code repo, follows the same loop. In Claude Code, **`/hq-work`** walks it; the authoritative text is [playbook 07](00-META/process/07-parallel-work.md).

1. **Pick the work ID.** The number and slug of the record the work is rooted in — an issue or a design — or, where there is none, a bare descriptive slug. Never a number you have not allocated yet.
2. **Open the workspace**, naming only the code repos the work touches; the hq repo is always included. Run the same command again to add a repo later.

   ```
   <clone-root>/<hq-repo>/05-TOOLS/open-workspace.sh <work-id> [code-repo...]
   cd <clone-root>/.work/<work-id>/<repo>
   claude
   ```

3. **Push early, and open a *draft* MR on the first push.** That is what claims the work and tells everyone else it has started.
4. **Mark it ready yourself** when the quality gate is green and every declared predecessor has merged; then merge, or hand over, by the project's policy (`05-TOOLS/merge-policy.sh`).
5. **Tear down** once everything has merged: `05-TOOLS/teardown-workspace.sh <work-id>`.

The other skills map one-to-one onto the playbooks: `/hq-status` for where things stand, `/hq-new-research`, `/hq-graduate`, `/hq-amend-design`, `/hq-handoff` for the knowledge flow, `/hq-new-issue`, `/hq-diagnose`, `/hq-defer` for issues. [`AGENTS.md`](AGENTS.md) is the one-page brief an agent reads before anything else; it is a good second read for a person too.

### Staying current with the template

The template keeps improving after your project is created. [`05-TOOLS/migrate.sh`](05-TOOLS/migrate.sh) pulls its machinery updates — tools, skills, playbooks, CI — into the instance as an ordinary reviewable change, file by file with a three-way merge; your content is never touched. Run it in a workspace, review the diff, land it by MR.

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

## License

The template is released under the [MIT License](LICENSE). A project created from it keeps or replaces that file as it sees fit — `05-TOOLS/migrate.sh` never touches it.

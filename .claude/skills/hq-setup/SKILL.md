---
name: hq-setup
description: Use when configuring a fresh instance of this hq template for a new project — naming the project, wiring the forge (GitHub or GitLab), and filling the 00-META content docs. Triggers on "set up this hq repo", "configure the template", "initialize this project", "run the setup wizard".
---

# hq-setup

Turns a fresh copy of the hq template into a configured project repo. Run it once, right after the repo is created from the template; every value it writes can also be edited by hand later. Work conversationally — ask, confirm, write — one section at a time, and show each file after writing it.

## 1. The facts

Ask for, and confirm back:

- **Project name** — the human name used in doc titles (e.g. "Atlas").
- **This repo's name** — the clone directory name (e.g. `atlas-hq`). If the current directory's name already looks right, propose it.
- **The forge** — GitHub or GitLab; this varies per project and per organization.
- **Forge host** (e.g. `github.com` or `gitlab.example.com`) and **org/group path** (e.g. `my-org`, or `my-org/atlas` on GitLab, where subgroups exist) — the place that holds, or will hold, the fleet.
- **Known code repos**, if any exist yet: name + one line on what each owns (and the forge project slug where it differs from the directory name).
- **The template repo's URL** — where this instance was created from, so `05-TOOLS/migrate.sh` can pull later template improvements. Skip it only if the project will never migrate.
- **Who merges a ready MR** — `agents` (whoever did the work merges once it is ready, in landing order) or `humans` (the agent stops at ready; a human merges). The template has no default: ask, and if the human is not ready to choose, leave it empty — agents then stop at ready and ask each time.

## 2. Write the config

Fill the values at the top of [`05-TOOLS/config.sh`](../../../05-TOOLS/config.sh): `HQ_REPO`, `HQ_FORGE`, `HQ_FORGE_HOST`, `HQ_GROUP_PATH`, `HQ_TEMPLATE_REPO`, `HQ_MERGE_POLICY`. Leave `HQ_REPO` empty when the repo's directory name equals its repo name, and `HQ_FORGE` empty when the host makes it obvious (a host containing "github" infers github; anything else gitlab) — the tools derive both. If the project deploys via a Helm umbrella + values-file shape, also offer the optional `HQ_DEPLOY_*` values (see `05-TOOLS/check-deployed.sh --help`); otherwise leave them out.

With `HQ_TEMPLATE_REPO` set, record the migration baseline so `05-TOOLS/migrate.sh` knows where this instance forked off:

```
git fetch <template-url> main && git rev-parse FETCH_HEAD > 05-TOOLS/template-commit
```

(Right for a freshly created instance; an older one passes the true creation commit to `migrate.sh --base` once instead.)

## 3. Seed the repo map

In [`00-META/repos.md`](../../../00-META/repos.md): add the hq repo's own row and one row per known code repo, keeping the exact table shape the file documents (it is machine-parsed). Leave the commented example in place for later readers, or drop it once real rows exist.

## 4. The content docs — the real interview

These deserve the most time. For each, read the guidance comments in the file, interview rather than dictate, draft, and iterate until the user owns the words:

1. [`00-META/mission.md`](../../../00-META/mission.md) — vision, mission, core values. Push back on values that would never veto anything.
2. [`00-META/context.md`](../../../00-META/context.md) — organizational mandates vs defaults. Ask what is truly non-negotiable.
3. [`00-META/effect.md`](../../../00-META/effect.md) — concrete scenes of the finished picture. Push for specifics over abstractions.
4. [`00-META/how-we-deploy.md`](../../../00-META/how-we-deploy.md) — only if the deployment shape is already known; otherwise leave the skeleton and note it as a follow-up.
5. [`00-META/how-we-build.md`](../../../00-META/how-we-build.md) — the template seeds three process postures; ask whether the project already has settled fleet-wide postures to add. Do not invent any.

## 5. Titles

Set the project's name in the `README.md` H1 (keep the rest), and check `AGENTS.md` still reads correctly.

## 6. Forge prerequisites (tell, don't do)

List for the user what only they can set up on the forge — the shape differs per forge:

**GitHub**
- **Protected main the writers can still push:** the three direct-to-main writers (`allocate-issue.sh`, `claim.sh`, `set-issue.sh`) need push access to `main` — a branch protection rule or ruleset that requires PRs for everyone else but lets the intended people/apps push directly.
- **CI read token:** the fleet checkers need the `HQ_FLEET_TOKEN` Actions secret — a fine-grained PAT (or GitHub App token) with read-only **Contents** access to the org's repositories (see `05-TOOLS/check-refs.sh --help`).
- **gh + SSH:** each machine needs `gh auth login --hostname <host>` and an SSH key on the host before `05-TOOLS/sync.sh` works.

**GitLab**
- **Protected main + Developer push:** the same three writers need Developer push access to `main` (Settings → Repository → Protected branches).
- **CI deploy token:** the fleet checkers need `HQ_FLEET_USER` / `HQ_FLEET_TOKEN` CI variables — a **group deploy token** with `read_repository` scope (Masked, Protected), not a group access token (see `05-TOOLS/check-refs.sh --help`).
- **glab + SSH:** each machine needs `glab auth login --hostname <host>`, `jq`, and an SSH key on the host before `05-TOOLS/sync.sh` works.

## 7. Verify

- `bash 05-TOOLS/commit-to-main.sh --self-test` and the other `--self-test` tools (status, set-issue, allocate-issue, claim, check-numbers, check-features) — all green.
- `05-TOOLS/check-features.sh` and, once there is a remote, `05-TOOLS/status.sh` run clean.
- `grep -ri` for the previous project's name returns nothing unexpected.

## 8. Existing material

When the project brings existing knowledge — decision records, design docs, a backlog, roadmaps — continue with the **`hq-migrate`** skill after this wizard: it routes each kind into the numbered structure with the curation the rules here demand.

## 9. Trim what does not apply

- **The other forge's CI file:** the template ships both `.github/workflows/checks.yml` and `.gitlab-ci.yml`; delete the one the chosen forge does not use.
- **Derived views:** ask whether the project keeps a derived docs site and/or a builder-skills marketplace. If not, offer to delete playbooks 05/06 (`00-META/process/05-external-sync.md`, `06-builder-skill-sync.md`), the `hq-sync-docs` skill, and the references to them (the overview table in `00-META/process/00-overview.md`, step 8–9 of playbook 04, step 5 of the graduation flows) — and this section's own reminder in AGENTS.md.

## Do not

- Do not fabricate mission/context/effect content the user has not said — placeholders beat invented commitments.
- Do not change the machine-contract shape of `repos.md` or the frontmatter schemas.
- Do not commit anything without the user's go-ahead; they may want to review the whole configuration first.

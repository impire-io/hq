# 05-TOOLS — the executable tree

The content folders are Markdown-only; this folder is where every checked-in
tool lives. One line each:

- `config.sh` — the one place this project names itself: the hq repo's name, the forge (github|gitlab), its host and its org/group. Sourced by every tool; filled by the `hq-setup` skill.
- `open-workspace.sh` — open (or extend) a work item's isolated workspace under `.work/<id>/`.
- `teardown-workspace.sh` — remove one work item's worktrees, branch and directory, nothing wider.
- `sync.sh` — clone/fast-forward every clone the forge org/group holds.
- `status.sh` — render the status view from frontmatter at `origin/main`. Light: this repo only. `--roadmap` and `--feature <name>` read `feature:` and the list in `06-FEATURES/README.md`.
- `allocate-issue.sh` — mint the next issue number by committing the record to main. Atomic.
- `claim.sh` — claim/release an issue (`claimed-by:` intent), committed to main. Atomic.
- `set-issue.sh` — set an issue's scalar state fields (`kind`, `priority`, `status`, `located-in`, `feature`, `blocked-by`, `resolved`), committed to main with playbook 03's rules. A close runs `check-claims.sh --only` first. Atomic.
- `commit-to-main.sh` — sourced CAS core for the three writers above; the only code that pushes to main.

  All three writers require push access to the protected main branch — on GitLab, Developer push (Settings → Repository → Protected branches); on GitHub, a branch protection rule or ruleset that lets the writers push. Without it they fail at push, loudly, changing nothing.
- `check-refs.sh` — every relative markdown link, this repo and siblings, must resolve (CI).
- `check-numbers.sh` — no duplicate issue (NNN) or decision (NNNN) numbers, working tree or vs origin/main (CI).
- `check-features.sh` — every `feature:` names a doc in `06-FEATURES/`, every feature doc is on the roadmap list once, no frontmatter on a feature doc (CI).
- `check-claims.sh` — a record claiming completion must have its named MRs merged (CI). `--only <issue>` checks one record against just the repos it names.
- `check-unclaimed.sh` — no repo's main may name an issue this repo still shows open (CI).
- `check-deployed.sh` — the install's pins vs each repo's releases: behind, unreleased, unknown. Reports, never fails on lag. Optional and Helm-shaped; enabled by the `HQ_DEPLOY_*` values in `config.sh` (CI).
- `check-shipped.sh` — a design a sibling spec cites may not still read `designed` (CI).
- `session-workspace-notice.sh` — SessionStart hook: says whether the session is in a clone or a workspace.
- `guard-readonly-clone.py` — PreToolUse hook: refuses writes in the shared clones.
- `guard-workspace-delete.py` — PreToolUse hook: refuses deletes reaching past one work item.

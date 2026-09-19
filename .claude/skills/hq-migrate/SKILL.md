---
name: hq-migrate
description: Use when an existing project adopts this hq template and its current knowledge — decision records, design docs, an issue backlog, roadmaps, scattered wikis — must move into the numbered structure. Triggers on "migrate our project into the hq", "adopt the hq for X", "import our existing docs/ADRs/backlog", "move our decisions in here".
---

# hq-migrate

Moves an existing project's material onto the hq way of working. Run **`hq-setup` first** — it configures the repo and interviews for mission, context and effect; this skill is about everything the project already has. (For pulling *template* updates into an instance, that is `05-TOOLS/migrate.sh`, not this skill.)

## The posture

- **Migration is curation, not conversion.** The hq's value is that being in it means something. Import the records a future reader needs; leave the rest where it is, with a pointer. A wholesale import buries the few records that matter under the many that don't — the same failure the issue curation rule exists to prevent.
- **The old system keeps its history.** Nothing here rewrites the past; the hq becomes authoritative from the migration forward. Where an old page stays useful as history, link to it rather than copying it.
- **One thing becomes authoritative per fact.** After a document moves, the old copy either redirects here or dies. Two live copies is how drift starts.

## 1. Inventory

Sit with the user and list where knowledge currently lives: READMEs and wikis, an ADR folder, design documents, the issue tracker, roadmap spreadsheets, decision threads in chat or email. For each source note roughly what it holds and how alive it is. Do not read everything yet — inventory first, so the routing below is decided per source, not per page.

## 2. Route by kind

| What exists | Where it goes | The rules that bite |
|---|---|---|
| Vision / strategy docs | `00-META/` (mission, context, effect) | Filled via the `hq-setup` interview; cite the old doc as the source rather than pasting it. |
| Settled engineering conventions | `00-META/how-we-build.md` postures | Only what is genuinely settled fleet-wide. A convention still being argued is not a posture. |
| ADRs / decision records | `03-DECISIONS/`, renumbered `0001…` in original chronological order | Keep the original date and context in the body. **Immutable from the moment they land** — a decision that later changed is imported as-is and superseded by a new record, never edited. Import superseded ones only when they still explain current reality. |
| Current architecture / design docs | `02-DESIGN/`, with status frontmatter | Status is judged against reality, not aspiration: `implemented` only if it is defensible from the owning repo's main; otherwise `designed` or `in-progress`. Set `code:` to the owning repos. Prose and diagrams only — code stays in code repos. |
| Open proposals, spikes, unanswered questions | `01-RESEARCH/` efforts (`status: active`) | One numbered folder each, with a real `00-overview.md`. A dead proposal worth remembering imports as `abandoned` with `became:` saying what superseded it. |
| The issue backlog | `04-ISSUES/`, **through `05-TOOLS/allocate-issue.sh`** | The strictest gate. Import only open items that pass the curation rule — worth a future reader's attention in that repo. Never bulk-import; never hand-make numbered folders. Closed history stays in the old tracker, linked once. A large dropped batch gets **one** rollup task pointing at the old tracker, never one record per item. |
| Feature lists / roadmaps | `06-FEATURES/` — one prose doc per feature + the numbered roadmap list | Feature docs carry no status and no member list; tag the imported records with `feature:` instead. |
| Whitepapers, external reports | `99-ARTIFACTS/` | Downstream only; mark stale ones stale rather than silently updating them. |
| The repo inventory | `00-META/repos.md` rows | Keep the exact table shape — it is machine-parsed. |

## 3. Sequence

Order matters because later records cite earlier ones:

1. `hq-setup` is done: config, repos.md, mission/context/effect.
2. **Decisions** land first (designs will cite them), oldest to newest so the numbering reads chronologically.
3. **Designs**, with honest status frontmatter; then **features** and the roadmap, then tag records with `feature:`.
4. **Research** for whatever is genuinely open.
5. **Issues last**, through `allocate-issue.sh`, after the duplicate-check grep each time.
6. Verify: `05-TOOLS/check-numbers.sh`, `check-features.sh`, and `status.sh --all` reads sensibly; `check-refs.sh` once sibling clones exist.
7. Land the whole migration by MR ([playbook 07](../../../00-META/process/07-parallel-work.md)) — it is reviewable work like any other, and the review is where the curation calls get challenged.
8. In each old location, leave a pointer to the hq (or retire the location). Announce the switch: from now on, decisions and designs happen here first.

## Do not

- Do not bulk-import a backlog, a wiki, or a folder of drafts. Inventory, curate, import the vital few.
- Do not edit an imported decision's meaning to match the present — supersede it with a new record.
- Do not assign `implemented` to a design nobody can defend from the owning repo's main.
- Do not leave the old copy authoritative. A migration that ends with two sources of truth has made things worse.
- Do not hand-craft issue folders or numbers — the allocator and `set-issue.sh` are the writers.

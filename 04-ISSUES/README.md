# 04-ISSUES

The single front door for "something needs doing" — a **defect** (`kind: bug`) or a **known follow-up** (`kind: task`). Report symptoms here even — especially — when you don't know which repo owns the problem: several repos are often suspects at once. Diagnosis happens here, where the whole system is visible; the fix lands in the owning code repo.

**This is a curated signal, not a complete log.** Being tracked here means an item is worth a future reader's attention when they next work in that repo. Completeness lives in the trail — the reviews, diagnoses, and commits git already holds. Polish and trivia are triaged *out*, deliberately, and left in that trail; see the curation rule below.

## Structure

One numbered folder per issue:

```
NNN-short-name/
  00-report.md      the symptom as observed, in plain terms; status in frontmatter
  01-diagnosis.md   the investigation trail (agent + engineer)
```

## Frontmatter (on `00-report.md`)

```yaml
---
kind: bug | task               # defaults to bug; task is a known follow-up, not a defect (see below)
status: open | diagnosing | located | resolved | wontfix
priority: high | normal | low  # optional triage signal, defaults to normal; surfaced in the hq-status board
claimed-by:        # optional — set via 05-TOOLS/claim.sh, never by hand; intent, not started work
claimed:           # YYYY-MM-DD, written by claim.sh alongside claimed-by
located-in: [svc-a]            # owning repo(s); for a task, set at filing — a task already knows its repo
feature:                       # optional — the 06-FEATURES doc this belongs to (file name without .md); --feature at filing, set-issue.sh later
discovered-while:              # optional backref to where this was noticed (a path, an issue, an MR)
fixed-by:                      # what fixed it, filled at resolution (see below)
  - repo: svc-a
    mr: "!12"                  # or commit: <sha> | tag: vX.Y.Z | action: deploy
    note: "fix 008 — the guard now skips the reserved prefixes"
amended-design:                # design doc path, when the root cause was a design gap
lands:                         # cross-repo fixes only; the declared landing order
  - { repo: svc-a, mr: "!31", after: [] }
  - { repo: svc-b, mr: "!20", after: [svc-a] }
---
```

### `kind: bug` vs `kind: task`

`bug` (the default) is the project's symptom→component memory: something is wrong, the owner may be unknown, and diagnosis localizes it. `task` is a **known follow-up** — sync docs, rename a thing, chase a dependency, hand a design off to build — noticed while doing something else and deferred so it isn't lost.

A task **skips diagnosis**: it already knows its repo, so it opens with `located-in:` set and moves `open → resolved` (or `wontfix`), never passing through `diagnosing`/`located`. Keep the two kinds distinct so the bug corpus stays a clean symptom→component record — filter `kind: bug` and the maintenance tasks fall away.

Not every deferral belongs here. Bugs and follow-ups do; a question to **investigate** is a research effort ([playbook 01](../00-META/process/01-research.md)); a design already decided is visible through its own `status:`/`code:` and needs a task only if it is genuinely at risk of being forgotten. The quick way to file a deferred item without stopping is the [`hq-defer`](../.claude/skills/hq-defer/SKILL.md) skill.

### `fixed-by:` entries

Each entry names a repo, **one** reference, and a note. Three reference kinds are
verified against git on every CI run:

| Kind | Meaning |
|---|---|
| `mr: "!N"` | a merge commit carrying GitLab's `See merge request …!N` |
| `commit: <sha>` | an ancestor of `origin/main` — for a merge with no MR trailer |
| `tag: vX.Y.Z` | a tag resolving to a commit on main |
| `action: <kind>` | an operational act (a deploy reconcile). **Out of scope** — it happened outside git, so no git check can attest to it. Reported separately, never counted as a gap. |

`note:` carries the prose: what the change did, what it did *not* do, what was
confirmed live. Structure was added around the prose, not in place of it.

**`fixed-by:` contains only what fixed the issue.** Work that has not happened
belongs in its own issue, not inside a closed one — outstanding work in a
`resolved` record is invisible to every status view.

`lands:` states the *plan*: which repos the fix lands in and in what order. It is written when the fix is planned, with `mr:` filled in as each MR opens; a single-repo fix omits it entirely. GitLab remains authoritative for live state — see playbook [`00-META/process/07-parallel-work.md`](../00-META/process/07-parallel-work.md).

## Rules

- Anyone may open an issue; no localization is required to report. Before opening, `grep` this directory — resolved issues included — for the symptom, and link any prior match: the kept corpus is the duplicate-detection memory.
- **Curate; do not dump.** File only what is worth surfacing later. Filing every minor buries the few that matter — the classic failure the reviewer avoids by *not* filing polish. "**Deferred, not filed**" is a first-class outcome: triage a pile, file the vital few, and leave the rest in the trail (the review, the diagnosis, git history). If a dropped batch is large enough to be worth a pointer, leave **one** rollup task ("~N minors triaged as polish; in the review history at `<ref>`"), never N records. The lightweight path is doing nothing — it must stay lighter than filing.
- The full flow is playbook [`00-META/process/03-issues.md`](../00-META/process/03-issues.md).
- Closed issues are never deleted and never archived — they stay in place as the project's symptom→component memory and the corpus the duplicate-check searches. Deleting them hides that memory from a working-tree `grep`; a `98-ARCHIVE/` folder would split the searchable corpus in two. There is **no archive directory by design**. Directory growth is not clutter — the accumulation is the asset; use [`hq-status`](../.claude/skills/hq-status/SKILL.md) for the generated "what's open" view.

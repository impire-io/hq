# Playbook 03 — issues

**Trigger:** something needs doing in the project — a **defect** (`kind: bug`, often without knowing which repo owns it), or a **known follow-up** (`kind: task`) noticed while doing something else and deferred so it isn't lost.
**Who:** anyone reports; agent and engineer diagnose together.

## Why the front door is here

The reporter usually cannot localize a symptom — several repos are often suspects at once. The hq repo is the one place that sees the whole system (the repo map, every design, every decision), so diagnosis starts here. The fix still lands in the owning code repo.

## Steps

1. **Report.** First **check for a duplicate**: `grep` across `04-ISSUES/` — *including resolved issues* — for the symptom. The kept-forever corpus is the project's symptom→component memory; if this symptom was seen before, link that prior issue in the new report (and if it is truly the same open problem, add to it rather than opening a second). Then mint the record with [`05-TOOLS/allocate-issue.sh`](../../05-TOOLS/allocate-issue.sh) `--symptom "<the symptom in plain terms and how it was observed>"` — it commits a minimal real report straight to `origin/main`, taking the next number atomically (a rejected push retries against the new main, so two parallel filings cannot collide; `check-numbers` remains the CI backstop for hand-made folders). The printed ID is the work ID. Expand the report body by MR from the workspace. No localization required. Frontmatter:

   ```yaml
   ---
   kind: bug          # bug (default) | task — a task is a known follow-up, not a defect
   status: open
   priority: normal   # high | normal | low — optional, defaults to normal; triage signal only. Change it, and every scalar field below, with 05-TOOLS/set-issue.sh — never by MR
   feature:           # optional — the 06-FEATURES doc this belongs to (file name without .md); set at filing with --feature or later with set-issue.sh
   claimed-by:        # optional — set via 05-TOOLS/claim.sh, never by hand; intent, not started work
   claimed:           # YYYY-MM-DD, written by claim.sh alongside claimed-by
   blocked-by:        # only with status: blocked — what is being waited on: an issue/MR ref or plain prose
   ---
   ```

   A **`kind: task`** is a deferred follow-up (sync docs, rename, hand a design off). It already knows its repo, so it opens with `located-in:` set and skips straight to step 4 — no diagnosis. Optionally carry `discovered-while:` so the context you noticed it in isn't lost. The one-line way to file one mid-flow, without stopping to number folders, is the [`hq-defer`](../../.claude/skills/hq-defer/SKILL.md) skill.

   **Curate; do not dump.** File only what is worth surfacing when someone next works in that repo. Filing every minor buries the few that matter. "Deferred, not filed" is a valid, deliberate outcome — leave triaged-out polish in the trail (the review, the diagnosis, git), not in a record. A large dropped batch may warrant **one** rollup task pointing at the trail, never one record per item.

2. **Diagnose** (bugs only — a `kind: task` already knows its repo and skips to step 4). Using [`../repos.md`](../repos.md) and the design docs' `code:` fields to see the system's shape, reproduce and localize. Record the trail — hypotheses, evidence, dead ends — in `01-diagnosis.md`. Set `status: diagnosing` while working; `status: located` with `located-in: [repo, ...]` once the owner is known. Both are one command, committed straight to main: `05-TOOLS/set-issue.sh <NNN> status=diagnosing`, then `05-TOOLS/set-issue.sh <NNN> status=located located-in=repo,repo` — the trail itself still lands by MR.
3. **Resolve.** Before opening the workspace, **claim the issue**: `05-TOOLS/claim.sh <NNN>`. A claim is intent — "this is mine, don't start it" — recorded in the report's frontmatter on main; the draft MR ([playbook 07](07-parallel-work.md)) remains the signal that work has *started*. `claim.sh <NNN> --release` hands it back; `--steal` takes over an abandoned claim, attributed in the commit message. Open the workspace via [playbook 07](07-parallel-work.md) — the issue number is the work ID — and push to a draft MR from the first commit. When the fix spans repos, declare the landing order in this report's `lands:` block rather than as prose.
   - Implementation bug → hand the fix to the owning repo's spec-kit bugfix flow; record `fixed-by:` (PR/spec links).
   - Design gap or ambiguity → amend the design **first** ([playbook 02](02-graduation.md)), record `amended-design:`; the code fix follows the amended design via [playbook 04](04-build-handoff.md).

   **Blocked is a status, not a comment.** At any point — reported, diagnosing, or located — an issue that cannot move gets `status: blocked`, with the reason in `blocked-by:`: an issue number, an MR, an external party, a pending decision — whatever names the thing being waited on. Blocked is active, not terminal: the record stays on the triage board with its reason beside it, and a claim on it stays meaningful. When the blocker lifts, restore the status the issue was in and clear `blocked-by:`. A blocked issue with no `blocked-by:` is legal but weak — the next reader has to rediscover the blocker, so name it when you know it. `05-TOOLS/set-issue.sh <NNN> status=blocked blocked-by="<what>"` records it on main directly, and setting any other status through it clears `blocked-by:` for you.
4. **Close.** Set `status: resolved` with `resolved: <YYYY-MM-DD>`, or `wontfix` with the reasoning in the report, **and drop `claimed-by:` and `claimed:` in the same edit.** When the record already carries every `fixed-by:` entry it needs, `05-TOOLS/set-issue.sh <NNN> status=resolved` does all of that in one commit to main, after verifying the refs with `check-claims.sh --only`; a close that still has entries to write goes by MR, as the `closes: true` step of the `lands:` block. A claim is intent to work (step 3); a terminal record has no work left to intend, and who did it is already in the merge commits and the `fixed-by:` notes. A closed record that still carries a claim is flagged by `05-TOOLS/status.sh`; `05-TOOLS/claim.sh <NNN> --release` cleans up one a closing edit missed.

   ### The definition of done: delivered, not verified-by-someone-eventually

   An issue is done when its work is **built**, **released** where the repo cuts releases, **deployed** where the change only takes effect once deployed, and **validated on the install**. All four, and nothing beyond them.

   **Validated means one live read of the running system that could not succeed if the thing were broken.** Not a merge — a merged fix can change nothing on the install. Not a command that exited zero. Prefer a read whose *failure modes differ*, so a pass is evidence rather than coincidence: a response that only the fixed path can produce beats one that several broken states would also produce.

   Record that read as a `fixed-by:` entry with **`action: deploy`** and the evidence in the note, beside the `mr:`/`commit:` entries for the code. `05-TOOLS/check-claims.sh` counts these as operational and does not try to resolve them to a commit — the note is the proof, so write what you actually observed, not what you ran.

   **What does not hold a record open:**

   - **A manual exercise nobody has scheduled.** "Someone should try it end to end once" is a wish, not a blocker. If the exercise genuinely matters, it is its own record with its own owner — file the follow-up against the original rather than holding the original open for it.
   - **Work owned by another repo or another issue.** Name the dependency and close; do not inherit someone else's worklist.
   - **The possibility of a defect.** A defect found afterwards is a **new issue** against the repo that owns it, never a reopening. The corpus is symptom→component memory; reopening corrupts the record of when a thing was delivered.

   The reason this bar exists rather than a stricter one: an issue held open for something nobody is scheduled to do stops being a worklist item and becomes indistinguishable from undelivered work. A triage board where half the open records are actually finished is a board no one can act on — the same rot as [`05-TOOLS/check-unclaimed.sh`](../../05-TOOLS/check-unclaimed.sh) catches, arrived at from the opposite direction.

   ### Recording the refs

   Where the work spanned repos, closing is the `closes: true` entry declared in this report's own `lands:` block ([playbook 07](07-parallel-work.md) step 3): an hq MR landing **after** every code MR, so each `fixed-by:` reference is already an ancestor of its repo's main and `05-TOOLS/check-claims.sh` can verify it. Closing has a declared place in the landing order rather than being remembered afterwards — the omission is the single most common way the hq repo goes stale, and [`05-TOOLS/check-unclaimed.sh`](../../05-TOOLS/check-unclaimed.sh) fails CI when a repo's main names an issue the hq repo still shows as open.

   Two ref forms bite at exactly this moment, because flipping to `resolved` is what makes `05-TOOLS/check-claims.sh` read the *whole* record rather than only the parts already claimed as done — so refs that sat unverified for months all fail at once, on the closing branch:

   - **`mr:` only where the merge leaves a marker.** On GitLab a `mr: "!N"` ref is verified by a merge commit ending `See merge request <group>/<repo>!N`; on GitHub a `mr: "#N"` ref by a `Merge pull request #N` merge commit or a squash-merge subject ending `(#N)`. A repo that fast-forwards (GitLab) or rebase-merges (GitHub) produces no such marker, so `mr:` there is unverifiable no matter how real the MR was — `commit: <sha>` is the only honest form. A `lands:` block that *says so in a comment* while still using `mr:` is not protection.
   - **A closing entry cannot cite its own MR.** The ref must be an ancestor of `origin/main` and a commit cannot cite itself, so filling the closing entry's `mr:` in makes CI fail on the very branch carrying the closure. Leave it `mr: ""` — git history recovers it.

   Closed issues are kept forever, **in place** — they are the project's symptom→component memory and the corpus the duplicate-check in step 1 searches. Deleting them (leaving only git history) or moving them to an archive folder both defeat that: the first makes the memory unreachable by a working-tree `grep`, the second splits the searchable corpus in two. There is no archive directory by design; the "what's open" view is generated on demand by [`hq-status`](../../.claude/skills/hq-status/SKILL.md), so resolved records never clutter it.

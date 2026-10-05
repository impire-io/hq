# How We Build

The cross-repo engineering posture for every repo in the fleet. Where `mission.md`
says *why* and `context.md` says *in what environment*, this document says
*how* — the durable engineering stances every repo is expected to share.

It is **stable by nature** (see the folder [README](README.md)): a posture
lands here once it is settled fleet-wide, not while it is still being argued.
Each repo's own brief (`AGENTS.md` / `CLAUDE.md`) refines this for its context;
when a repo brief and this document disagree, **this document wins** until the
brief is corrected. Postures are recorded as their own dated decisions under
[`03-DECISIONS/`](../03-DECISIONS/); this file states the durable form, the
decision record carries the context and consequences.

One section per posture. Add deliberately — a posture that is really one
repo's convention belongs in that repo's brief, not here. The template seeds
the three postures its own process machinery depends on; the rest are the
project's to write.

<!-- Project postures go here: the architectural stances every repo shares —
the service shape, the tenancy model, where authorization lives, what the
public contract is. Each section states the durable rule, two or three
bullets that make it concrete, and a pointer to the decision record behind
it. -->

## Build the minimal feature; expand only for a real, present need

The project is built to the requirement in front of it, not the one imagined
for later. A capability earns its place by a consumer that exists *today*;
speculative generality — a config knob nothing sets, a store nothing reads, a
mode no caller selects — is carrying cost with no power drawn against it, and it
is left out rather than kept "just in case." Scope grows when a genuine gap
surfaces, never by default.

- **The minimal build is the default; every addition carries the burden of
  proof.** An addition must name the present need it serves — "we might want it
  later" is not that need. When two designs both satisfy the requirement, the
  smaller one wins.

- **"What this does not do" is part of the design.** A service states its
  non-goals as plainly as its goals. Naming the boundary keeps scope creep
  visible instead of accreting silently.

- **A missed requirement is the reason to expand — a hypothetical is not.** If
  real use shows something genuinely necessary was left out, add it, deliberately,
  to that need. The rule is minimal-to-the-requirement, not minimalism for its
  own sake: the guard is against speculative scope, not against doing the job
  completely.

## Spec-driven, constitution-governed development

Every repo develops the same way: a versioned constitution states its principles
and a binding Constitution Check gates non-trivial work, which flows
Specify → Plan → Tasks → Implement with the artifacts committed. This document is
the cross-repo layer above those constitutions — restating the durable form so
the per-repo briefs stay consistent (when a repo brief and this document
disagree, this document wins until the brief is corrected).

- **The public contract is the thing under test, against the real thing.**
  Anything that exercises the wire contract runs against a real or embedded
  instance of the substrate and real backends; mocking the transport or the
  crypto is forbidden. Tests are written first or alongside; external providers
  use recorded-replay fixtures, never live calls in CI.

- **The quality gate is blocking.** `make fmt && make test && make lint` green —
  with the race detector where it applies — is when a *change* is done. Hook
  failures stop the line; commits are signed; `--no-verify` and `--no-gpg-sign`
  are not used without explicit owner authorization, and local settings are never
  committed.

- **An *issue* is done when the work is delivered.** Delivered means built,
  released where the repo cuts releases, deployed where deployment is what makes
  a change take effect, and **validated by one live read of the running system
  that could not succeed if the thing were broken**. Nothing beyond that holds a
  record open — not a manual exercise nobody has scheduled, not another repo's
  work, not the possibility of a defect, which is a new issue and never a
  reopening. The bar is delivery rather than verification-by-someone-eventually
  because a record held open for something nobody is scheduled to do is
  indistinguishable from work that was never done, and a triage board half-full
  of finished records is one nobody can act on. The mechanics — what counts as a
  live read, and how to record it — are [playbook 03](process/03-issues.md)
  step 4.

## Work in isolation; push continuously; land in a declared order

Several agents run on one machine and several engineers work the same fleet, so
a change must be isolated where it is made and visible from the moment it is
started. One **work ID** — a single string — names the branch in
every repo the change touches, the workspace directory, and the MR label
(MR — merge request; a pull request on GitHub). It is
taken only from a record that **already exists** — an hq design or issue, a
repo's spec-kit feature — and otherwise is a bare descriptive slug. Never from a
record the work will produce: an unallocated number is not yours, and building an
ID on one means renaming the branch when someone takes it first. There are no
`spec/`, `fix/`, or `feat/` prefixes: a prefix that varies by author defeats the
one query the ID exists to make possible.

- **The clone is the refresh point, never the workspace.** Each work item gets
  its own directory holding one git worktree per repo it touches, all on branch
  `<work-id>`; the clones stay on main. One agent therefore has one working
  directory containing every repo its change spans, and two agents can never
  share a working tree — the failure this prevents is not a merge conflict but
  work flowing silently into the wrong change. The clones are **read-only**, and
  the workspace is opened by one command rather than a recipe: what was left to
  discipline drifted, so a guard now refuses a write to a clone and
  `05-TOOLS/open-workspace.sh` derives the path and the branch name that used to
  be retyped.

- **The draft MR is the claim, and it opens on the first push.** Commits are
  pushed as they are made and the first push opens a *draft* MR, so the MR exists
  at the beginning of the work rather than the end. That is what makes
  "keep scope small" enforceable instead of merely requested: one group-wide MR
  query answers what everyone is working on right now. An agent may branch,
  push, open the draft, and flip it out of draft; whether it also merges is this
  project's `HQ_MERGE_POLICY` (`05-TOOLS/config.sh`).
  Flipping to ready requires the blocking quality gate green *and* every declared
  predecessor merged.

- **Cross-repo landing order is declared, not inferred.** A change spanning repos
  carries an ordered `lands:` block on its hq work item naming each repo,
  its MR, and what it waits on. The hq repo states the plan; the forge holds
  the live state. "Held until the other half lands" is a field, not a sentence buried
  in a report.

- **A cross-repo reference is verified, not trusted.** Sibling repos cite hq
  documents by relative path, and those links break silently whenever the hq
  repo moves a file. No sibling can catch it (in its own pipeline the repo is
  cloned alone), so the hq repo's CI checks every such reference on each change
  and daily, and fails on a sibling it cannot read rather than skipping it.

The executable steps are [playbook 07](process/07-parallel-work.md).

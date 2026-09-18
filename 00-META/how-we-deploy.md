# How We Deploy

<!-- Fill this in once the project has a deployment shape (the hq-setup skill
offers to draft it). Where how-we-build.md says the durable engineering
posture a service is built to, this document says how a built service actually
reaches a running environment: the repos involved, the release and deploy
flows, and what is expected of anyone bringing a service up. -->

It is an **operational explainer**, not a runbook. Be concrete about the
topology and the flow so anyone can orient, and point at the code repos as the
authoritative source for exact commands and values — those mechanics live in
the repos that own them (see the ground rule in [`repos.md`](repos.md):
implementation lives in the code repos). Describe **today's reality**, not the
intended end state.

## The pieces

_Which repos own which deploy-time layer — typically: a charts/manifests repo,
each service repo owning its own image, a deploy repo holding the desired
state, and whatever connects CI to the target environment. A table works well._

| Repo | Owns at deploy time |
|---|---|
| _repo_ | _layer_ |

## The release flow

_How a service goes from merged code to a deployable artifact: what triggers a
build (a tag? a merge?), what gets published where, and what makes an artifact
immutable and reproducible._

## The deploy flow

_How an artifact reaches the environment: what file or system is the single
source of desired state, what applies it, and what a person actually edits to
ship a change. State explicitly what is **not** done by hand._

## What's expected before enabling a service

_The out-of-band prerequisites that must exist before a first deploy —
credentials, secrets, seeded configuration — in order, so enabling a service
before they exist stops being a discovered-in-production surprise._

## A green pipeline is not a healthy service

_How to verify a deploy actually worked: the rollout check, the health read,
the logs. Treat the running workload, not the pipeline badge, as the
definition of deployed._

## Rollout ordering and the shared environment

_Any ordering constraints between services, and the etiquette of shared
environments: who else is affected by a deploy, and what care that demands._

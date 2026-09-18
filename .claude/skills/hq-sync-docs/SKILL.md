---
name: hq-sync-docs
description: Use when the hq repo changed something the project's derived external docs site retells — design content, a research conclusion, or an implementation-status flip. Triggers on "sync the docs", "update the docs site", after graduating/amending/handing off a design. Only applies when the project keeps a derived docs site.
---

# hq-sync-docs

Redraws the derived external site from hq changes. **Authoritative playbook:** [`00-META/process/05-external-sync.md`](../../../00-META/process/05-external-sync.md). The docs site (a sibling repo) is a **derived view** — every page carries `derived_from:` frontmatter listing the hq files it retells. **No decision is ever made or first recorded there.**

This skill applies only to a project that keeps such a site; if this one does not, say so and delete this skill together with playbook 05.

## Steps

1. **Diff** the hq repo since the last sync — the hq commit recorded as the sync marker in the docs repo's README.
2. **Map** changed files to affected pages via their `derived_from:` frontmatter. A changed file no page derives from may warrant a new page — judge by audience value, not completeness.
3. **Redraft** the affected pages in plain language a non-technical reader follows. Update status badges and the "Where things stand" view **from the design docs' frontmatter** — never hand-maintained.
4. **Engineer review is mandatory** — an agent drafts, an engineer reviews, publish only after review. Review is never skipped.
5. **Update the sync marker** in the docs repo to the hq commit just synced.

## Do not

- Do not publish without engineer review.
- Do not record anything new there — the docs site is strictly downstream.
- Do not hand-write status badges; generate them from frontmatter.

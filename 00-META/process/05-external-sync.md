# Playbook 05 — external sync *(optional)*

**Applies only when the project keeps a derived plain-language docs site.** A project without one deletes this playbook and the steps that reference it.

**Trigger:** anything changed in the hq repo that the docs site retells — design content, a research conclusion, an implementation-status flip.
**Who:** an agent drafts; an engineer reviews before publish. Review is never skipped.

## The derivation contract

- The docs site (a sibling repo) is a **derived view**. Every page carries `derived_from:` frontmatter listing the hq files it retells.
- Page status badges and the "Where things stand" page are generated from the design docs' frontmatter.
- The site's own writing rules hold: plain language a non-technical reader follows, status stated under each opener, research pages never reading as commitments.

## Steps

1. Diff the hq repo since the last sync — the hq commit recorded as the sync marker in the docs repo's README.
2. Map the changed files to affected pages via their `derived_from:` frontmatter. A changed file no page derives from may warrant a new page — judge by audience value, not completeness.
3. Redraft the affected pages in plain language. Update badges and status lines from the design docs' frontmatter.
4. An engineer reviews the drafts. Publish only after review.
5. Update the sync marker in the docs repo to the hq commit just synced.

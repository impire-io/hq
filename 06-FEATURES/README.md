# 06-FEATURES

A **feature** is the thread that runs through the numbered stages: the research that explored it, the decisions that settled it, the designs that state its contracts, and the issues filed against it. It is the level most people ask about — *what does feature X provide, and where do we stand with it?* — and the level the roadmap orders.

The folder holds one Markdown document per feature, **prose only**: what the feature is, what it provides once done, and what it deliberately does not cover, written for the reader who wants the picture rather than the contract. A feature doc carries **no frontmatter and no status**. It states no contract of its own; the designs under it do, and its state is read from them.

## The roadmap

The sequence we pursue, in order. No dates, no quarters, no owners: the order is the whole statement, and it changes by MR when our minds change. Where a feature stands is never written here; `05-TOOLS/status.sh --roadmap` prints this list with each feature's live rollup beside it.

<!-- The numbered list of features. Entries start at column 0; the indented
example below is ignored by the tools:

    1. [Feature name](feature-name.md)
    2. [Another feature](another-feature.md)

-->

Every feature doc in this folder appears in the list exactly once; `05-TOOLS/check-features.sh` fails CI when one is missing or listed twice. Features that are live and merely maintained sit at the bottom; their relative order carries no meaning.

## Membership lives on the records

A record joins a feature by naming it in its own frontmatter — never by being listed here:

```yaml
feature: feature-name  # the feature doc's file name without .md; optional
```

The field is accepted on a research overview (`00-overview.md`), a design doc that carries frontmatter, and an issue report (`00-report.md`). A record belongs to at most one feature. Not every record needs one: project plumbing and hq housekeeping may stay unassigned, and the roadmap view lists what is unassigned so the gaps are visible rather than hidden.

On an issue the field is a scalar state field: set it with `05-TOOLS/set-issue.sh <NNN> feature=<name>`, or at filing with `05-TOOLS/allocate-issue.sh … --feature <name>`. On research and design docs it is written by MR with the rest of the frontmatter. A value that names no doc in this folder is refused by the writers and fails CI.

## Where a feature stands is derived

`05-TOOLS/status.sh --feature <name>` lists a feature's members grouped by kind with their live state, and `--roadmap` prints one rollup line per feature. The rollup is a deterministic reading of the members' frontmatter:

| Rollup | Rule |
|---|---|
| `exploring` | no design carries the feature; at least one research effort is `active` |
| `designing` | designs exist, none is `in-progress` or `implemented` |
| `building` | at least one design is `in-progress` |
| `live` | at least one design is `implemented`, and none is `in-progress` or `designed` (abandoned designs are ignored) |
| `no open work` | none of the above: no members, or only terminal ones |

Beside the rollup the line counts the members that are not terminal: research still active, designs not yet implemented, issues open. Open issues never demote a live feature; they are counted beside it.

## Rules

- All files must be Markdown, one document per feature, named in kebab-case; the file name is the value records use.
- A feature doc never carries frontmatter, a status line, or a list of its members. Membership is derived from the records, status from their frontmatter.
- Adding, renaming, or removing a feature, and reordering the roadmap, goes by MR ([playbook 07](../00-META/process/07-parallel-work.md)). Renaming a feature renames its value on every member in the same MR.

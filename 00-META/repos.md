# The project repositories

The map of every repository in the project: what each owns and how it relates
to this one. Humans use it for orientation; agents use it for issue triage
(playbook [`process/03-issues.md`](process/03-issues.md)). The `code:`
frontmatter field in design docs points at entries here.

**The table below is a machine contract.** The tools in `05-TOOLS/` parse it:
`set-issue.sh` validates `located-in:` against its rows, and the fleet
checkers (`check-refs.sh`, `check-claims.sh`, `check-unclaimed.sh`,
`check-shipped.sh`) enumerate siblings from it. Keep the shape exactly —
one row per repo, the name in backticks in the first column:

- `` | `name` | what it owns | `` — the name is the clone's directory name.
- When a repo's GitLab project slug differs from the local directory name,
  record it in the second column as `` (gitlab project `slug`) `` — the
  checkers read that note to find the project.
- This hq repo itself gets a row too; the checkers skip it by name.

<!-- Example rows (the hq-setup skill fills in the real ones). Rows start at
column 0; the indented example below is ignored by the tools:

    | `my-hq` | This repo — mission, research, design, decisions, issue diagnosis. The source of truth. |
    | `my-service` | The frobnicator service: what it owns, stated as a boundary. |
    | `my-lib` | The shared client library (gitlab project `my-client-lib`). |

-->

| Repository | Owns |
|---|---|

**Deprecated:** _list retired repos here with a "never build on it" note, so
the records that cite them keep verifying while nothing new refers to them._

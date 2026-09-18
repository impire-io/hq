---
name: hq-status
description: Use when you need a cross-cutting view of where the hq repo's efforts stand — the roadmap, where a feature stands, research state, design implementation state, open issues, or what's outstanding for a given repo. Triggers on "what's the status", "what's the roadmap", "what's next", "where do we stand with <feature>", "what does <feature> provide", "show the status matrix", "where do things stand", "what's in progress", "what's open for <repo>", "what's waiting in <project>".
---

# hq-status

The status view is rendered by [`05-TOOLS/status.sh`](../../../05-TOOLS/status.sh); the hq repo has **no central status file by design**. This skill is a thin wrapper: run the script, show its output, answer follow-ups from it.

## Steps

1. Pick the flag from the ask: default (issues triage board), `--roadmap` ("what's next", "the roadmap" — the ordered features with a derived rollup each), `--feature <name>` ("where do we stand with X" — its research, designs and issues; for "what is X" read `06-FEATURES/<name>.md` too), `--research`, `--design`, `--repo <name>` ("what's open for X"), `--all`. Run `05-TOOLS/status.sh <flag>` from any checkout of this repo — it fetches and reads `origin/main` itself.
2. Present the output as-is (it is already markdown), then answer follow-ups from it. Read individual records only when a follow-up needs a body, not for the view.
3. The board reflects **frontmatter**, and says so in its footer. When the user asks whether it is *true* — not just what it says — run [`05-TOOLS/check-unclaimed.sh`](../../../05-TOOLS/check-unclaimed.sh) (the fleet's git history vs the record; slower, fetches siblings) and fold its findings in.

## Do not

- Do not write a `STATUS.md` or any status file — the view is always generated, always ephemeral. A feature's state is never written into its `06-FEATURES` doc either.
- Do not re-derive the view by reading frontmatter yourself; the script is the renderer. If its output looks wrong, flag it, do not silently correct it.
- Do not present a `--no-fetch` render as the fleet's state.

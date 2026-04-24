<!-- last-verified: 2026-04-24 -->

# 2026-04-24 — Fix unified governance skill contract drift

## Goal

Close the drift found after PR #32 between the unified `governance` skill
docs, `packverb` helper surface, and the pack catalog contract.

Closes [#33](https://github.com/Duaility/governance-kit/issues/33).

## Scope

- Keep catalog search refs directly usable by `pack add`, including
  monorepo-hosted packs that declare `source.path`.
- Keep the documented `packverb validate-pack` command backed by a real
  helper path.
- Guard `INIT_FLOW.md` against stale references to rule ids rolled into
  `required-docs`.
- Keep `@<40-char-sha>` pack refs supported by implementation and tests.

## Plan

1. Inspect the current helper and flow docs to see which issue findings are
   already fixed in the worktree.
2. Add user-facing contract coverage so future changes cannot regress the
   catalog, validation, init-doc, or SHA-ref behavior.
3. Run pack tests and the governance suite.


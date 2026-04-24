<!-- governance: allow-plan-validation legacy -->
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

## Follow-up

After review of the first draft PR, the local hook contract was tightened:

- Add `pre-commit-test-gate` to the constitution and governance rules.
- Wire `scripts/test-packs.sh` into this repo's tracked
  `.githooks/pre-commit` (source repo only — the generated dispatcher
  template that ships into target repos is left untouched, since the
  pack-author tests have no meaning there).
- Keep `scripts/test-packverb.py` inside `scripts/test-packs.sh`, so packverb
  contract coverage is part of every normal local commit. The pack-test
  step gracefully skips with a notice when `uv` is not installed locally;
  CI still enforces it.

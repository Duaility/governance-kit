# Move ledger append out of `prepare-commit-msg`

## Goal

Fix the CI failure on commit `bbafba7` — `Cost-Key 'claude-code-b8c3537c-03c-1776873692' should have exactly 1 row in COSTS.md, found 0` — by relocating the `COSTS.md` append and `git add` from the `prepare-commit-msg` hook into the wrapper script that runs before `git commit`.

## Root cause

`prepare-commit-msg` appended a row to `COSTS.md` and staged it. But git captures the index snapshot for the current commit before that hook runs; the freshly staged ledger row lands in the *next* commit's index rather than the tree that's about to be committed. So every agent-authored commit shipped trailers whose matching row was written *a commit later* — and on origin, the branch tip's trailer had no row at all (the next commit hadn't happened yet).

Observed locally: right now the index has a staged `COSTS.md` modification for `bbafba7`'s cost-key, but `git show bbafba7:COSTS.md` has no data rows.

## Design

Split the contract cleanly:

- **Wrapper (per runtime)** computes tokens → computes `Cost-Key` → appends ledger row → `git add` → exports `AGENT_*` including `AGENT_COST_KEY` → `exec git commit`.
- **`prepare-commit-msg` hook** only stamps trailers from env vars. Never touches `COSTS.md`. Requires `AGENT_COST_KEY` to be set upstream (by the wrapper).

Disproven en route: I initially suspected a mawk/gawk regex-in-split bug in `ledger_rows()`. Tested against mawk directly — behaves identically to BSD awk. Hypothesis withdrawn, awk parse code left alone.

## Steps

1. Move the `COSTS.md` write + `git add` block from `.githooks/prepare-commit-msg` and `governance-bootstrap/assets/githooks/prepare-commit-msg` into `scripts/claude-code-commit.sh`. Parse `-m` / `--message` / `--message=` / `-F` from argv so the wrapper can infer `AGENT_ISSUE` and build the ledger row's note column before `git commit` runs.
2. Add `require_var AGENT_COST_KEY` to the hook and stamp the trailer from that env var. The hook no longer computes a default cost-key — that's the wrapper's job.
3. Update `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md` to describe the new split and rewrite the Codex wrapper example so it too appends + stages before `exec git commit`.
4. Let this commit itself ship two `COSTS.md` rows: the orphaned `bbafba7` row (already staged from the old hook), plus the new wrapper's row for this commit. After that, every subsequent commit writes its own row into its own tree — and CI's `Cost-Key … found 0` error goes away.

## Non-goals

- No shared helper library. Each wrapper owns ~15 lines of ledger-write logic; factoring it out adds indirection that outweighs the duplication.
- No automatic re-stamping of older commits. Trailer history stays as-is; `bbafba7`'s row gets reconciled into the ledger by this commit so CI can resolve it.

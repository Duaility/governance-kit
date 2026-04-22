# Make the commit wrapper runtime-agnostic

## Goal

Give Claude Code and Codex equal first-class support. The previous refactor left all of the governance logic (issue parsing, cost-key generation, ledger append, staging, exec) glued inside `scripts/claude-code-commit.sh`, so Codex users would have been asked to re-implement ~60 lines of identical boilerplate in their own wrapper.

## Design

Split the commit pipeline along the one honest dimension: transcript-reading is per-runtime; everything else is shared.

- `scripts/governance-commit.sh` — runtime-agnostic helper. Takes cumulative session tokens in, writes the per-commit delta row, exports the `AGENT_*` trailer contract, `exec`s `git commit`. One place to get "append before commit" right.
- `scripts/claude-code-commit.sh` — slims down to transcript discovery + `python3` sum of `.message.usage`. Ends with `exec governance-commit.sh "$@"`.
- `scripts/codex-commit.sh` — new, parallel shape. Discovers `~/.codex/sessions/<thread>.jsonl`, sums tokens handling the shapes Codex versions ship (top-level `usage`, `message.usage`, `response.usage`; `input_tokens`/`output_tokens` or `prompt_tokens`/`completion_tokens`).

Each wrapper is ~40 lines. Adding a new runtime = write one more wrapper; nothing else changes.

## Env-var contract

- **Wrapper → helper:** `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`, `AGENT_CUM_OUTPUT`.
- **Helper → hook:** `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_TOKEN_INPUT` (delta), `AGENT_TOKEN_OUTPUT` (delta), `AGENT_COST_KEY`, `AGENT_ISSUE`.

The helper owns the cumulative→delta subtraction because it has to read `COSTS.md` anyway to stage the row.

## Steps

1. Create `scripts/governance-commit.sh`.
2. Rewrite `scripts/claude-code-commit.sh` as a thin transcript reader + `exec` handoff.
3. Create `scripts/codex-commit.sh`.
4. Mirror all three under `governance-bootstrap/assets/scripts/` so bootstrapped repos get them.
5. Update the reference doc to drop the inline Codex snippet and describe the three-layer split.

## Non-goals

- No auto-detection of which runtime is active. The user picks the wrapper; the env-var contract between layers is shared.
- No Codex schema version detection. The wrapper tries the common shapes and falls back to zero — users on an outlier schema set `CODEX_USAGE_JQ` or edit the wrapper.

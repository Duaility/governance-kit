<!-- COSTS.md — append-only agent token-accounting ledger -->
<!-- governance: allow-plan-captured -->

# COSTS.md

Append-only ledger of token consumption for agent-authored commits. Rows are
keyed by `Cost-Key`, which is mirrored into the commit trailers so the ledger
survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable system-of-record
that the `agent-token-accounting` governance rule validates.

The pre-commit hook (`scripts/governance/agent-accounting.sh`) appends a row
before git snapshots the tree; the `prepare-commit-msg` hook stamps the
matching trailers. See
[governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md](governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md)
for wiring instructions.

## Ledger

Schema:

- `model` — runtime-reported model id (e.g. `claude-sonnet-4-5`); empty for
  legacy rows and runtimes that don't surface it.
- `input` — truly-new tokens (not from cache).
- `cache-create` / `cache-read` — prompt-cache traffic, split for visibility.
  Zero when the runtime doesn't report the cache fields.
- `output` — model output tokens.
- `new-work` = `input + cache-create + output`. Self-checking. `cache-read`
  is tracked but deliberately excluded — it's the same bytes re-read each
  turn, not new work — so `new-work` matches `Token-Total` in the commit
  trailer by construction.
- `cost-usd` — the true dollar cost for this row, computed from `model` via
  `scripts/governance/lib/rates.py` and all four token columns (cache_read
  included — that's the only place cache rent actually appears). Empty when
  the model isn't in the rate table. This is the only single-number headline
  that's comparable across commits with different cache mixes.

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-b8c3537c-03c-1776873692 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 13748948 | 0 | 0 | 148354 | 13897302 |  | docs(governance): note worktree-local hooksPath requirement (#13) |
| claude-code-b8c3537c-03c-1776874721 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 12138876 | 0 | 0 | 117281 | 12256157 |  | feat(governance): move ledger append from hook to wrapper (#13) |
| claude-code-b8c3537c-03c-1776875141 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 3032147 | 0 | 0 | 34287 | 3066434 |  | refactor(governance): split commit wrapper into runtime-agnostic helper + per-ru |
| claude-code-b8c3537c-03c-1776876126 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 8579217 | 0 | 0 | 118905 | 8698122 |  | refactor(governance): make git commit the baseline for agent accounting (#13) |
| claude-code-b8c3537c-03c-1776876354 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 2327249 | 0 | 0 | 22683 | 2349932 |  | docs(plans): consolidate six #13 plans into one (#13) |
| claude-code-b8c3537c-03c-1776912518 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 0 | 1119082 | 48089930 | 103302 | 1222384 |  | refactor(governance): split cache tokens into own columns, move ledger to python |
| claude-code-b8c3537c-03c-1776931918 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 0 | 446668 | 7667667 | 58560 | 505228 |  | refactor(governance): exclude cache_read from COSTS.md total (#13) |
| claude-code-b8c3537c-03c-1776933349 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | claude-opus-4-7 | 0 | 212534 | 10138629 | 104827 | 317361 | 9.0183 | feat(governance): add model + cost-usd columns, rename total to new-work (#13) |
| claude-code-b8c3537c-03c-1776934117 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | claude-opus-4-7 | 0 | 66335 | 6967296 | 44506 | 110841 | 5.0109 | refactor(governance-amend): drop inline approval loops, commit atomically (#13) |

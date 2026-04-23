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

Schema: `input` counts truly-new tokens; `cache-create` and `cache-read`
split out prompt-cache traffic (0 for runtimes that don't report them);
`output` is model output; `total = input + cache-create + cache-read + output`.
Commit trailers surface a narrower `Token-Input = input + cache-create` so
reviewers see new work rather than cache rent.

| cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-b8c3537c-03c-1776873692 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 13748948 | 0 | 0 | 148354 | 13897302 | docs(governance): note worktree-local hooksPath requirement (#13) |
| claude-code-b8c3537c-03c-1776874721 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 12138876 | 0 | 0 | 117281 | 12256157 | feat(governance): move ledger append from hook to wrapper (#13) |
| claude-code-b8c3537c-03c-1776875141 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 3032147 | 0 | 0 | 34287 | 3066434 | refactor(governance): split commit wrapper into runtime-agnostic helper + per-ru |
| claude-code-b8c3537c-03c-1776876126 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 8579217 | 0 | 0 | 118905 | 8698122 | refactor(governance): make git commit the baseline for agent accounting (#13) |
| claude-code-b8c3537c-03c-1776876354 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 2327249 | 0 | 0 | 22683 | 2349932 | docs(plans): consolidate six #13 plans into one (#13) |
| claude-code-b8c3537c-03c-1776912518 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | 0 | 1119082 | 48089930 | 103302 | 49312314 | refactor(governance): split cache tokens into own columns, move ledger to python |

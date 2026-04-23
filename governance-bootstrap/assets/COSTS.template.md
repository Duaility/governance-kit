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

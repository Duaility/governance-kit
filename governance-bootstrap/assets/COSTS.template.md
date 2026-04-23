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
`output` is model output; `total = input + cache-create + output`. `cache-read`
is tracked but deliberately excluded from `total` — it's the same bytes
re-read each turn, not new work. This keeps `total == Token-Total` in the
commit trailer, so the ledger's headline number and the reviewer-facing
number are the same.

| cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

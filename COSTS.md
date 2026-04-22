<!-- COSTS.md — append-only agent token-accounting ledger -->
<!-- governance: allow-plan-captured -->

# COSTS.md

Append-only ledger of token consumption for agent-authored commits. Rows are
keyed by `Cost-Key`, which is mirrored into the commit trailers so the ledger
survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable system-of-record
that the `agent-token-accounting` governance rule validates.

The `prepare-commit-msg` hook appends a row automatically when an agent
runtime wrapper exports the `AGENT_*` environment variables. See
[governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md](governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md)
for wiring instructions.

## Ledger

| cost-key | agent | session | issue | input | output | total | note |
| --- | --- | --- | --- | --- | --- | --- | --- |

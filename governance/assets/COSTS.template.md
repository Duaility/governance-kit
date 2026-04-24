<!-- COSTS.md — append-only agent token-accounting ledger -->
<!-- governance: allow-plan-captured -->

# COSTS.md

Append-only ledger of token consumption for agent-authored commits. Rows are
keyed by `Cost-Key`, which is mirrored into the commit trailers so the ledger
survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable system-of-record
that the `agent-token-accounting` governance rule validates.

The `agent-token-accounting` rule's `hooks/pre-commit.sh` appends a row
before git snapshots the tree; its `hooks/prepare-commit-msg.sh` stamps
the matching trailers. Both live inside the rule folder at
`tests/governance/rules/agent-token-accounting/hooks/`. See
[governance/references/AGENT_TOKEN_ACCOUNTING.md](governance/references/AGENT_TOKEN_ACCOUNTING.md)
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
  the rule's `lib/rates.py` and all four token columns (cache_read
  included — that's the only place cache rent actually appears). Empty when
  the model isn't in the rate table. This is the only single-number headline
  that's comparable across commits with different cache mixes.

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

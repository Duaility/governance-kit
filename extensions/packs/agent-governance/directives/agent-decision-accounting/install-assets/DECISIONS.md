<!-- DECISIONS.md — append-only human-vs-agent decision ledger -->
<!-- governance: allow-plan-captured -->

# DECISIONS.md

Append-only ledger of **load-bearing** human decisions made during
agent-driven development. Rows are keyed by `decision-key`, which is
mirrored into the `Decision-Key:` commit trailer so the ledger survives
squash merges. Paired with `COSTS.md` via the optional `cost-key` column
so "cost of overriding the agent" is a join away.

**Record every load-bearing decision**, not just divergences. Baseline
density is what makes override-rate, reframe-rate, and time-to-override
measurable. Trivial `AskUserQuestion` prompts ("continue? y/n") should
not be tagged — only decisions the agent considers load-bearing.

**Do not** rewrite or reorder rows. This file is the durable
system-of-record that the `agent-decision-accounting` governance
directive validates.

## Divergence vocabulary

Exactly one of:

- `agreed` — human picked the agent's lean.
- `overrode` — human picked a different option the agent offered.
- `reframed` — human rejected the question itself ("wrong thing to ask").
- `deferred` — human kicked the decision to later.

`reframed` is the most valuable signal — it flags the *agent's question
set itself* as broken, not just its lean accuracy.

## Phase vocabulary

Exactly one of: `scoping` | `plan-review` | `pr-review` | `post-merge`.

## Ledger

| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

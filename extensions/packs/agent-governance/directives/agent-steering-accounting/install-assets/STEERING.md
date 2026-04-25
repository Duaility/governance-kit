<!-- STEERING.md — append-only human-steering ledger -->
<!-- governance: allow-plan-captured -->

# STEERING.md

Append-only ledger of human-steering events for agent-authored commits. Rows are
keyed by `steer-key`, which is mirrored into a `Steer-Key:` commit trailer so the
ledger survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable record that the
`agent-steering-accounting` governance directive validates.

`type` ∈ `tool-denial` | `interrupt` | `correction` ·
`tier` ∈ `structural` | `lexical`.

## Ledger

| steer-key | session | issue | type | tier | tool | proposed | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

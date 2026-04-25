<!-- STEERING.md — append-only human-steering ledger -->
<!-- governance: allow-plan-captured -->

# STEERING.md

Append-only ledger of human-steering events for agent-authored commits. Rows are
keyed by `steer-key`, which is mirrored into a `Steer-Key:` commit trailer so the
ledger survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable record that the
`agent-steering-accounting` governance directive validates.

`type` ∈ `interrupt` | `correction` ·
`tier` ∈ `structural` | `classifier` | `lexical` (the lexical tier is a
silent fallback for when the runtime CLI is unreachable).

## Ledger

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-8240a0685cb-1777111842-1 | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | correction | classifier | missing expected steering trailers in commit message | chore(governance): dogfood agent-steering-accounting + corrections (#53) |
| steer-8240a0685cb-1777111842-2 | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | correction | classifier | rejected tool-denial signal entirely; remove it | chore(governance): dogfood agent-steering-accounting + corrections (#53) |
| steer-8240a0685cb-1777111842-3 | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | correction | classifier | challenged Steer-Count: 0 — the removal request itself is steering | chore(governance): dogfood agent-steering-accounting + corrections (#53) |

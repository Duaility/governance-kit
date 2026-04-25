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
| steer-6c4e62ac993-1777113362-1 | 6c4e62ac-9936-4904-a8af-12d87f7a7a7c | #57 | correction | classifier | rejected proposed inline drafts; asked for higher-level re-evaluation | docs(readme): sharpen positioning + add Transparency section (#57) |
| steer-ece4c7df4b1-1777133400-1 | ece4c7df-4b11-4ab8-b15a-2bacd47b5637 | #59 | correction | classifier | rejected 'atomic triple' framing and asked to rethink from scratch | docs(readme): tighten dev-facing pitch + add macro and loop diagrams (#59) |
| steer-ece4c7df4b1-1777133400-2 | ece4c7df-4b11-4ab8-b15a-2bacd47b5637 | #59 | correction | classifier | pushed back on minutia; wants focus on why, not mechanics | docs(readme): tighten dev-facing pitch + add macro and loop diagrams (#59) |
| steer-e2468206d4b-1777135665-1 | e2468206-d4b9-4c96-bb52-722a1ed046ad | #61 | correction | classifier | rejected proposed tightening; asked to rethink from scratch | docs(readme): reframe Why around steering + visibility, promote ledgers (#61) |
| steer-e2468206d4b-1777135665-2 | e2468206-d4b9-4c96-bb52-722a1ed046ad | #61 | correction | classifier | expanded scope: rethink entire README, not just diagram area | docs(readme): reframe Why around steering + visibility, promote ledgers (#61) |
| steer-e2468206d4b-1777135665-3 | e2468206-d4b9-4c96-bb52-722a1ed046ad | #61 | interrupt | structural |  | docs(readme): reframe Why around steering + visibility, promote ledgers (#61) |

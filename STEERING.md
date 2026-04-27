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
| steer-9dd1ddeacf4-1777221518-1 | 9dd1ddea-cf43-4129-b8a4-16a462b285a4 | #63 | correction | classifier | rejected plan-centric framing; said taxonomy must shift to verification criteria | feat(governance): replace plans-as-audit-artifact with receipts (#63) |
| steer-9dd1ddeacf4-1777221518-2 | 9dd1ddea-cf43-4129-b8a4-16a462b285a4 | #63 | correction | classifier | questioned need for coverage check given shape checks in CI | feat(governance): replace plans-as-audit-artifact with receipts (#63) |
| steer-9dd1ddeacf4-1777221518-3 | 9dd1ddea-cf43-4129-b8a4-16a462b285a4 | #63 | correction | classifier | pushed back that shape checks already cover file existence and sections | feat(governance): replace plans-as-audit-artifact with receipts (#63) |
| steer-9dd1ddeacf4-1777221518-4 | 9dd1ddea-cf43-4129-b8a4-16a462b285a4 | #63 | correction | classifier | rejected coverage directive and told agent to start fresh, not amend | feat(governance): replace plans-as-audit-artifact with receipts (#63) |
| steer-c55035570e3-1777223440-1 | c5503557-0e31-400d-9893-168680b87436 | #65 | correction | classifier | User pushed back on chosen directive name, suggesting a more obvious alternative | refactor(governance): rename receipt-shape to receipt-per-issue + require What … |
| steer-c55035570e3-1777223440-2 | c5503557-0e31-400d-9893-168680b87436 | #65 | correction | classifier | User rejected the split proposal and dictated bundled approach with all sections checked | refactor(governance): rename receipt-shape to receipt-per-issue + require What … |
| steer-6c9722b774f-1777274551-1 | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | correction | classifier | rejected opt-in checklist; demanded mandatory with exceptions for legacy | feat(agent-governance): add ## Checklist + crosswalk to receipts; gate PR exist… |
| steer-6c9722b774f-1777274551-2 | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | correction | classifier | halted post-commit script; asked to remodel as a directive instead | feat(agent-governance): add ## Checklist + crosswalk to receipts; gate PR exist… |
| steer-6c9722b774f-1777274551-3 | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | correction | classifier | rejected keeping split; wants merge since V0 ignores backward compat | feat(agent-governance): add ## Checklist + crosswalk to receipts; gate PR exist… |
| steer-6c9722b774f-1777274881-1 | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | correction | classifier | Push back on including 'Open PR' as a checklist item; remove it | docs(receipts): drop ceremonial 'Open PR' item from issue-69 checklist (#69) |

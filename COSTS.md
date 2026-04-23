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
[governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md](governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md)
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
| claude-code-b8c3537c-03c-1776873692 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 13748948 | 0 | 0 | 148354 | 13897302 |  | docs(governance): note worktree-local hooksPath requirement (#13) |
| claude-code-b8c3537c-03c-1776874721 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 12138876 | 0 | 0 | 117281 | 12256157 |  | feat(governance): move ledger append from hook to wrapper (#13) |
| claude-code-b8c3537c-03c-1776875141 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 3032147 | 0 | 0 | 34287 | 3066434 |  | refactor(governance): split commit wrapper into runtime-agnostic helper + per-ru |
| claude-code-b8c3537c-03c-1776876126 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 8579217 | 0 | 0 | 118905 | 8698122 |  | refactor(governance): make git commit the baseline for agent accounting (#13) |
| claude-code-b8c3537c-03c-1776876354 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 2327249 | 0 | 0 | 22683 | 2349932 |  | docs(plans): consolidate six #13 plans into one (#13) |
| claude-code-b8c3537c-03c-1776912518 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 0 | 1119082 | 48089930 | 103302 | 1222384 |  | refactor(governance): split cache tokens into own columns, move ledger to python |
| claude-code-b8c3537c-03c-1776931918 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 |  | 0 | 446668 | 7667667 | 58560 | 505228 |  | refactor(governance): exclude cache_read from COSTS.md total (#13) |
| claude-code-b8c3537c-03c-1776933349 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | claude-opus-4-7 | 0 | 212534 | 10138629 | 104827 | 317361 | 9.0183 | feat(governance): add model + cost-usd columns, rename total to new-work (#13) |
| claude-code-b8c3537c-03c-1776934117 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | claude-opus-4-7 | 0 | 66335 | 6967296 | 44506 | 110841 | 5.0109 | refactor(governance-amend): drop inline approval loops, commit atomically (#13) |
| claude-code-b8c3537c-03c-1776934485 | claude-code | b8c3537c-03c3-4ba3-8e42-ceb02b2da58b | #13 | claude-opus-4-7 | 0 | 19641 | 2798442 | 9089 | 28730 | 1.7492 | docs(plans): consolidate PR #14 plans into one umbrella file (#13) |
| claude-code-d70074d5-c7d-1776937263 | claude-code | d70074d5-c7d9-47e9-872e-d6434ebba353 | #17 | claude-opus-4-7 | 90 | 135005 | 4221982 | 55041 | 190136 | 4.3312 | feat(governance): make agent-token-accounting mandatory on every non-merge commi |
| claude-code-2ff1de86-c43-1776938847 | claude-code | 2ff1de86-c431-4d9f-b1f6-3207628ac98e | #19 | claude-opus-4-7 | 93 | 183429 | 4516732 | 42054 | 225576 | 4.4566 | feat(governance): replace plan-captured with commit-issue-plan-match (#19) |
| codex-019db9a2-47d-1776939439 | codex | 019db9a2-47d3-7012-93b5-4b0cbb9adaa8 | #13 | gpt-5.4 | 228312 | 0 | 5097984 | 19716 | 248028 | 2.1410 | fix(governance): complete codex agent accounting (#13) |
| claude-code-2ee76956-1f7-1776942079 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 72 | 219460 | 2057421 | 15701 | 235233 | 2.7932 | docs(plans): add plan for issue 23 rule packs refactor (#23) |
| claude-code-2ee76956-1f7-1776942344 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 38 | 51778 | 3910335 | 37949 | 89765 | 3.2277 | feat(packs): add pack manifest schema, loader, and core pack.yaml (#23) |
| claude-code-2ee76956-1f7-1776942368 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 4 | 4567 | 462284 | 3310 | 7881 | 0.3425 | feat(packs): add pack manifest schema, loader, and core pack.yaml (#23) |
| claude-code-2ee76956-1f7-1776942571 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 37 | 22399 | 4651804 | 13535 | 35971 | 2.8045 | refactor(packs): migrate rule scripts into core pack + add snippets (#23) |
| claude-code-2ee76956-1f7-1776942768 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 27 | 33737 | 3958194 | 17384 | 51148 | 2.6247 | feat(packs): promote this repo's rules into agent-governance pack (#23) |
| claude-code-2ee76956-1f7-1776943072 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 21 | 43243 | 1004234 | 21652 | 64916 | 1.3138 | docs(packs): rewrite governance-bootstrap SKILL.md for pack flow (#23) |
| claude-code-2ee76956-1f7-1776943230 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 31 | 32830 | 1417967 | 22284 | 55145 | 1.4714 | feat(packs): manifest-driven hook generator + collision detection (#23) |
| claude-code-2ee76956-1f7-1776944025 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 130 | 444501 | 14455180 | 75254 | 519885 | 11.8877 | test(packs): per-rule evals + CI wiring + portability fix (#23) |
| claude-code-2ee76956-1f7-1776944107 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 12 | 9365 | 1867947 | 4409 | 13786 | 1.1028 | test(packs): per-rule evals + CI wiring + portability fix (#23) |
| claude-code-2ee76956-1f7-1776944474 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 47 | 81166 | 2983542 | 21305 | 102518 | 2.5319 | docs(packs): update catalog + add pack-authoring guide (#23) |
| claude-code-2ee76956-1f7-1776944546 | claude-code | 2ee76956-1f71-48a1-b8ed-5f0da9c878ce | #23 | claude-opus-4-7 | 14 | 11929 | 618519 | 3330 | 15273 | 0.4671 | docs(governance): record pack refactor in evolution log (#23) |
| claude-code-3ffd2eba-cd2-1776946025 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 42 | 127620 | 1549947 | 17406 | 145068 | 2.0080 | fix(packs): fall back to awk when yq expression fails (#23) |
| claude-code-3ffd2eba-cd2-1776946058 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 8 | 3347 | 526288 | 1703 | 5058 | 0.3267 | fix(packs): fall back to awk when yq expression fails (#23) |
| claude-code-3ffd2eba-cd2-1776946817 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 138 | 300744 | 11592692 | 64156 | 365038 | 9.2806 | refactor(packs): model each rule as a self-contained folder (#23) |
| claude-code-3ffd2eba-cd2-1776954519 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 306 | 740103 | 26016221 | 136526 | 876935 | 21.0484 | refactor(packs): pull rule dependencies inside the rule folder (#23) |
| codex-019dbad3-0b7-1776957557 | codex | 019dbad3-0b7b-7c80-b884-5dffbd1bd7bb | #23 | gpt-5.4 | 632803 | 0 | 22140928 | 46330 | 679133 | 7.8122 | fix(packs): parse manifests with pyyaml (#23) -m Replace ad hoc YAML parsing wit |
| codex-019dbad3-0b7-1776957588 | codex | 019dbad3-0b7b-7c80-b884-5dffbd1bd7bb | #23 | gpt-5.4 | 4821 | 0 | 1144704 | 656 | 5477 | 0.3081 | feat(packs): codify install-time contracts (#23) -m Add installer-facing helpers |
| codex-019dbad3-0b7-1776957621 | codex | 019dbad3-0b7b-7c80-b884-5dffbd1bd7bb | #23 | gpt-5.4 | 4178 | 0 | 1159040 | 429 | 4607 | 0.3066 | docs(skills): align companions to rule folders (#23) -m Update amend and gardene |
| claude-code-3ffd2eba-cd2-1776958080 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 63 | 364771 | 4269939 | 10600 | 375434 | 4.6801 | ci(governance): install uv so pack manifest parsing works (#23) |
| claude-code-3ffd2eba-cd2-1776958096 | claude-code | 3ffd2eba-cd2f-439f-9aa0-7090cbcd3511 | #23 | claude-opus-4-7 | 4 | 2641 | 241814 | 2132 | 4777 | 0.1907 | ci(governance): install uv so pack manifest parsing works (#23) |

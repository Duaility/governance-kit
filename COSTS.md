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
| claude-code-7109f1b4-393-1776961095 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 63 | 229719 | 1317336 | 23493 | 253275 | 2.6821 | docs(plan): draft governance-reset skill plan (#25) |
| claude-code-7109f1b4-393-1776961345 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 20 | 33244 | 1757867 | 23650 | 56914 | 1.6781 | feat(reset): add governance-reset skill with uninstall matrix and manifest schem |
| claude-code-7109f1b4-393-1776961546 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 34 | 22205 | 3690592 | 14136 | 36375 | 2.3376 | test(reset): add baseline evals M-bM^@M^T hard-reset, idempotent, dry-run (#25) |
| claude-code-7109f1b4-393-1776961610 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 14 | 13634 | 1706069 | 5285 | 18933 | 1.0704 | docs(reset): list governance-reset in AGENTS.md + README.md (#25) |
| claude-code-7109f1b4-393-1776962705 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 100 | 139996 | 7962170 | 50429 | 190525 | 6.1173 | feat(bootstrap): expand manifest to v1 + AGENTS directive closing marker (#25) |
| claude-code-7109f1b4-393-1776962915 | claude-code | 7109f1b4-393a-45ce-8318-02e4f85a277c | #25 | claude-opus-4-7 | 30 | 43726 | 1748294 | 17707 | 61463 | 1.5903 | docs(reset): align manifest schema with v1 emitter + legacy fallbacks (#25) |
| claude-code-7df52b9a-2cf-1776964418 | claude-code | 7df52b9a-2cf6-4a6f-a177-56e61ebf2e5d | #27 | claude-opus-4-7 | 458 | 337689 | 12507263 | 86581 | 424728 | 10.5310 | feat(bootstrap): add scripts/setup-clone.sh and fix install-assets leak (#27) |
| claude-code-8165bc21-e5b-1777004785 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 94 | 274861 | 4578349 | 27715 | 302670 | 4.7004 | feat(packs): roll up low-signal core rules into substantive ones (#29) |
| claude-code-8165bc21-e5b-1777004833 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 13 | 8606 | 1124679 | 5011 | 13630 | 0.7415 | feat(packs): roll up low-signal core rules into substantive ones (#29) |
| claude-code-8165bc21-e5b-1777004862 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 8 | 3748 | 718563 | 1686 | 5442 | 0.4249 | feat(packs): roll up low-signal core rules into substantive ones (#29) |
| claude-code-8165bc21-e5b-1777004910 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 5 | 5831 | 459790 | 2872 | 8708 | 0.3382 | feat(packs): roll up low-signal core rules into substantive ones (#29) |
| claude-code-8165bc21-e5b-1777005202 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 34 | 13674 | 1910958 | 6014 | 19722 | 1.1915 | ci(pack-tests): install uv so packctl.py can run (#29) |
| claude-code-8165bc21-e5b-1777005219 | claude-code | 8165bc21-e5be-420c-a7b8-b1ca86e21e68 | #29 | claude-opus-4-7 | 3 | 1839 | 316265 | 1657 | 3499 | 0.2111 | ci(pack-tests): install uv so packctl.py can run (#29) |
| claude-code-ee6dceb1-16d-1777007136 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 81 | 175876 | 3032992 | 27157 | 203114 | 3.2951 | feat(packs): formalize pack contract with kit version + capability schema (#31) |
| claude-code-ee6dceb1-16d-1777007177 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 5 | 5201 | 429176 | 2135 | 7341 | 0.3005 | feat(packs): formalize pack contract with kit version + capability schema (#31) |
| claude-code-ee6dceb1-16d-1777007224 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 8 | 4842 | 721010 | 3443 | 8293 | 0.4769 | feat(extensions): add community pack catalog scaffold (#31) |
| claude-code-ee6dceb1-16d-1777007241 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 3 | 2098 | 277709 | 1513 | 3614 | 0.1898 | feat(extensions): add community pack catalog scaffold (#31) |
| claude-code-ee6dceb1-16d-1777007410 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 19 | 17579 | 1926926 | 10166 | 27764 | 1.3276 | feat(governance): scaffold unified governance skill with init and uninstall verb |
| claude-code-ee6dceb1-16d-1777012955 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 304 | 351318 | 19484531 | 154943 | 506565 | 15.8131 | feat(governance): land pack verbs with SHA pinning, lockfile, and capability enf |
| claude-code-ee6dceb1-16d-1777013078 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 18 | 16230 | 2213358 | 10712 | 26960 | 1.4760 | feat(governance): land rule verbs via delegation to governance-amend atomic-trip |
| claude-code-ee6dceb1-16d-1777013248 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 26 | 33321 | 3636818 | 16162 | 49509 | 2.4308 | feat(extensions): seed catalog with forward-looking agent-governance entry (#31) |
| claude-code-ee6dceb1-16d-1777013411 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 18 | 20086 | 2804893 | 16994 | 37098 | 1.9529 | feat(governance): soft-retire legacy lifecycle skills in favor of unified govern |
| claude-code-ee6dceb1-16d-1777014401 | claude-code | ee6dceb1-16d7-404c-a5bb-46a72dc01a2b | #31 | claude-opus-4-7 | 138 | 212740 | 11001680 | 51364 | 264242 | 8.1153 | feat(packs): adopt monorepo layout for community-shaped packs (#31) |
| claude-code-9e05791b-0ee-1777016229 | claude-code | 9e05791b-0ee0-423e-b0c8-2234df57840a | #31 | claude-opus-4-7 | 299 | 800940 | 23858935 | 163357 | 964596 | 21.0208 | refactor(governance): physically retire legacy lifecycle skills into unified gov |
| claude-code-9e05791b-0ee-1777017833 | claude-code | 9e05791b-0ee0-423e-b0c8-2234df57840a | #31 | claude-opus-4-7 | 92 | 180009 | 7092007 | 25609 | 205710 | 5.3117 | fix(governance): address codex review on PR #32 (#31) |
| claude-code-9e05791b-0ee-1777017859 | claude-code | 9e05791b-0ee0-423e-b0c8-2234df57840a | #31 | claude-opus-4-7 | 4 | 3933 | 462351 | 1887 | 5824 | 0.3030 | fix(governance): address codex review on PR #32 (#31) |
| codex-019dbe8d-0a4-1777018919 | codex | 019dbe8d-0a49-7f30-9dbd-470aae006dff | #33 | gpt-5.5 | 209357 | 0 | 2008064 | 9510 | 218867 | 1.1681 | test(pack): cover packverb contract drift (#33) |
| codex-019dbe8d-0a4-1777019641 | codex | 019dbe8d-0a49-7f30-9dbd-470aae006dff | #33 | gpt-5.5 | 162470 | 0 | 6231424 | 14698 | 177168 | 2.1845 | test(hooks): require pack tests in pre-commit (#33) |
| claude-code-ae9c2998-434-1777020372 | claude-code | ae9c2998-4343-4f9e-a176-dfb594b1647d | #33 | claude-opus-4-7 | 125 | 155093 | 4472564 | 33986 | 189204 | 4.0559 | fix(hooks): address review feedback on PR #34 (#33) |
| claude-code-eb65db20-283-1777021586 | claude-code | eb65db20-283c-42f0-919f-bc589beea322 | #34 | claude-opus-4-7 | 34 | 38587 | 466265 | 13836 | 52457 | 0.8204 | test(governance): cover pack contract drift (#34) |
| claude-code-eb65db20-283-1777021689 | claude-code | eb65db20-283c-42f0-919f-bc589beea322 | #34 | claude-opus-4-7 | 13 | 22257 | 601497 | 11913 | 34183 | 0.7377 | test(governance): cover pack contract drift (#34) |
| claude-code-35defae4-ca7-1777022426 | claude-code | 35defae4-ca70-47d2-adbb-4db6e0489b11 | #35 | claude-opus-4-7 | 160 | 214277 | 12552159 | 106227 | 320664 | 10.2718 | feat(accounting): family-fallback rates + Cost-USD trailer + tput colors (#35) |
| claude-code-35defae4-ca7-1777023627 | claude-code | 35defae4-ca70-47d2-adbb-4db6e0489b11 | #35 | claude-opus-4-7 | 136 | 306699 | 11526635 | 79456 | 386291 | 9.6673 | feat(accounting): make Cost-USD mandatory (#35) |
| claude-code-04b28aac-fc8-1777024974 | claude-code | 04b28aac-fc85-4c80-8c94-9734e26101ac | #37 | claude-opus-4-7 | 10228 | 116988 | 4594193 | 31105 | 158321 | 3.8570 | chore(gardener): remove governance-gardener skill (#37) |
| claude-code-04b28aac-fc8-1777025034 | claude-code | 04b28aac-fc85-4c80-8c94-9734e26101ac | #37 | claude-opus-4-7 | 6 | 10552 | 488065 | 3333 | 13891 | 0.3933 | chore(gardener): remove governance-gardener skill (#37) |
| claude-code-b5006e23-eec-1777028604 | claude-code | b5006e23-eec5-490f-a729-b1b521ef6d7c | #39 | claude-opus-4-7 | 113 | 141430 | 6236287 | 40440 | 181983 | 5.0136 | feat(governance): roll harness-engineering lessons into existing rules (#39) |
| codex-019dbf0a-490-1777029444 | codex | 019dbf0a-4903-72e2-85d3-cf7ba74fbd61 | #39 | gpt-5.5 | 186330 | 0 | 5170432 | 18398 | 204728 | 2.0344 | fix(governance): keep plan waivers scoped (#39) |
| claude-code-cbdb387d-7ce-1777031062 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 41 | 57720 | 759346 | 11128 | 68889 | 1.0188 | docs(readme): expand with hook, quickstart, and concrete examples (#42) |
| claude-code-cbdb387d-7ce-1777031137 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 7 | 10855 | 334876 | 3054 | 13916 | 0.3117 | docs(readme): expand with hook, quickstart, and concrete examples (#42) |
| claude-code-cbdb387d-7ce-1777031174 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 3 | 5954 | 159623 | 796 | 6753 | 0.1369 | docs(readme): expand with hook, quickstart, and concrete examples (#42) |
| claude-code-cbdb387d-7ce-1777031639 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 27 | 14344 | 1026875 | 5772 | 20143 | 0.7475 | docs(readme): fix pack install ref and soften capability claim (#42) |
| claude-code-cbdb387d-7ce-1777031677 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 3 | 5955 | 196756 | 1257 | 7215 | 0.1670 | docs(readme): fix pack install ref and soften capability claim (#42) |

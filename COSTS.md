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
`.governance/rules/agent-token-accounting/hooks/`. See
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
| claude-code-cbdb387d-7ce-1777032172 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 64 | 109038 | 2464308 | 13427 | 122529 | 2.2496 | docs(readme): lead install with npx skills, note Agent Skills conformance (#42) |
| claude-code-cbdb387d-7ce-1777032452 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 26 | 5941 | 609661 | 3248 | 9215 | 0.4233 | docs(readme): drop -g from quickstart install command (#42) |
| claude-code-cbdb387d-7ce-1777032488 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 3 | 5970 | 313338 | 1012 | 6985 | 0.2193 | docs(readme): drop -g from quickstart install command (#42) |
| claude-code-cbdb387d-7ce-1777032949 | claude-code | cbdb387d-7ce5-4d1e-811c-554144dfd305 | #42 | claude-opus-4-7 | 56 | 25257 | 2445714 | 20567 | 45880 | 1.8952 | docs(readme): reframe around direction-setting for frontier agents (#42) |
| codex-019dbf52-2f5-1777033274 | codex | 019dbf52-2f52-7471-bfbe-26508d5f165a | #42 | gpt-5.5 | 136035 | 0 | 2682752 | 10209 | 146244 | 1.1639 | docs(readme): clarify direction-setting philosophy (#42) -m Tightens the governa |
| claude-code-1e9311de-d96-1777033786 | claude-code | 1e9311de-d964-43a7-b5c3-589a068ad926 | #44 | claude-opus-4-7 | 53 | 61177 | 655272 | 9396 | 70626 | 0.9452 | docs(readme): swap example to doc-freshness (#44) |
| claude-code-1e9311de-d96-1777033852 | claude-code | 1e9311de-d964-43a7-b5c3-589a068ad926 | #44 | claude-opus-4-7 | 7 | 12331 | 345455 | 3266 | 15604 | 0.3315 | docs(readme): swap rule example to doc-freshness (#44) |
| claude-code-4cd3e3d3-c4a-1777043703 | claude-code | 4cd3e3d3-c4a6-4a3a-a008-1bf541c71e85 | #47 | claude-opus-4-7 | 59 | 43051 | 607507 | 7431 | 50541 | 0.7589 | docs(github): add issue templates for proposal and bug flows (#47) |
| claude-code-4cd3e3d3-c4a-1777043757 | claude-code | 4cd3e3d3-c4a6-4a3a-a008-1bf541c71e85 | #47 | claude-opus-4-7 | 7 | 9385 | 279110 | 1680 | 11072 | 0.2402 | docs(github): add issue templates for proposal and bug flows (#47) |
| codex-019dc008-577-1777044965 | codex | 019dc008-5775-7431-8505-18d9039f905f | #47 | gpt-5.5 | 117361 | 0 | 2965760 | 17486 | 134847 | 1.2971 |  |
| claude-code-4cd3e3d3-c4a-1777046888 | claude-code | 4cd3e3d3-c4a6-4a3a-a008-1bf541c71e85 | #47 | claude-opus-4-7 | 73 | 58593 | 3042815 | 27233 | 85899 | 2.5688 | refactor(issue-templates): loosen rule to required IDs only (#47) |
| claude-code-1782a181-dbb-1777053507 | claude-code | 1782a181-dbb9-4a92-95c7-a7d085823ca8 | #49 | claude-opus-4-7 | 574 | 1069629 | 50379524 | 248735 | 1318938 | 38.0962 |  |
| claude-code-1782a181-dbb-1777053566 | claude-code | 1782a181-dbb9-4a92-95c7-a7d085823ca8 | #49 | claude-opus-4-7 | 8 | 6560 | 1005003 | 3341 | 9909 | 0.6271 |  |
| claude-code-1782a181-dbb-1777053617 | claude-code | 1782a181-dbb9-4a92-95c7-a7d085823ca8 | #49 | claude-opus-4-7 | 6 | 3995 | 774485 | 2100 | 6101 | 0.4647 | feat!: rename rule/invariant vocabulary to directive (#49) -m Breaking vocabular |
| claude-code-1782a181-dbb-1777053699 | claude-code | 1782a181-dbb9-4a92-95c7-a7d085823ca8 | #49 | claude-opus-4-7 | 8 | 6302 | 1057490 | 4140 | 10450 | 0.6717 | feat!: rename rule/invariant vocabulary to directive (#49) -m Breaking vocabular |
| claude-code-62860d53-f99-1777105141 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 152 | 407402 | 14255417 | 133594 | 541148 | 13.0146 | feat(governance): add agent-steering-accounting directive (#53) |
| claude-code-62860d53-f99-1777105218 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 5 | 9549 | 881712 | 3407 | 12961 | 0.5857 | feat(governance): add agent-steering-accounting directive (#53) |
| claude-code-62860d53-f99-1777107286 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 162 | 115586 | 21322816 | 87760 | 203508 | 13.5786 | feat(governance): summary trailers + CLI-driven tier-2 classifier (#53) |
| claude-code-62860d53-f99-1777107331 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 3 | 2780 | 776372 | 2291 | 5074 | 0.4629 | feat(governance): summary trailers + CLI-driven tier-2 classifier (#53) |
| claude-code-62860d53-f99-1777108259 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 50 | 31365 | 6698442 | 16874 | 48289 | 3.9674 | fix(governance): align steering-accounting docs with install-only gate (#53) |
| claude-code-62860d53-f99-1777108301 | claude-code | 62860d53-f995-4018-be8b-382325f91041 | #53 | claude-opus-4-7 | 3 | 2230 | 833584 | 1721 | 3954 | 0.4738 | fix(governance): align steering-accounting docs with install-only gate (#53) |
| claude-code-8240a068-5cb-1777109041 | claude-code | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | claude-opus-4-7 | 94 | 136116 | 3726905 | 26251 | 162461 | 3.3709 | chore(governance): dogfood agent-steering-accounting into this repo (#53) |
| claude-code-8240a068-5cb-1777110315 | claude-code | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | claude-opus-4-7 | 123 | 361625 | 12529079 | 118297 | 480045 | 11.4827 | chore(governance): dogfood agent-steering-accounting + bash 3.2 fix + always-on  |
| claude-code-8240a068-5cb-1777111303 | claude-code | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | claude-opus-4-7 | 105 | 112256 | 18245523 | 79706 | 192067 | 11.8175 | chore(governance): dogfood agent-steering-accounting + bash 3.2 fix + always-on  |
| claude-code-8240a068-5cb-1777111342 | claude-code | 8240a068-5cb7-456d-807b-3c9e29a6dd6d | #53 | claude-opus-4-7 | 2 | 3576 | 536300 | 3538 | 7116 | 0.3790 | chore(governance): dogfood agent-steering-accounting + corrections (#53) |
| claude-code-984ec8d3-ce2-1777111842 | claude-code | 984ec8d3-ce24-44d6-9833-8e4887fcedb7 | #53 | claude-opus-4-7 | 5 | 16483 | 14783 | 185 | 16673 | 0.1151 | chore(governance): dogfood agent-steering-accounting + corrections (#53) |
| claude-code-878ac246-f41-1777113363 | claude-code | 878ac246-f412-4e33-9aa4-922523e81504 | #57 | claude-opus-4-7 | 5 | 15307 | 14783 | 134 | 15446 | 0.1064 | docs(readme): sharpen positioning + add Transparency section (#57) |
| claude-code-c9fdc80b-19a-1777113831 | claude-code | c9fdc80b-19ae-400b-b790-b2efd2e45c7e | #57 | claude-opus-4-7 | 5 | 13290 | 14783 | 24 | 13319 | 0.0911 | docs(readme): rework GDD section + drop redundant Core Philosophy (#57) |
| claude-code-98161b98-bb3-1777114196 | claude-code | 98161b98-bb34-47b4-a97c-59d6ec69fa7e | #57 | claude-opus-4-7 | 5 | 14179 | 14783 | 45 | 14229 | 0.0972 | docs(readme): add 'The promise' payoff to GDD section (#57) |
| claude-code-ece4c7df-4b1-1777133400 | claude-code | ece4c7df-4b11-4ab8-b15a-2bacd47b5637 | #59 | claude-opus-4-7 | 209 | 434010 | 8977759 | 201887 | 636106 | 12.2497 | docs(readme): tighten dev-facing pitch + add macro and loop diagrams (#59) |
| claude-code-63b8cb06-ac0-1777135666 | claude-code | 63b8cb06-ac0e-4381-ac55-0ddfccdb69db | #61 | claude-opus-4-7 | 5 | 15523 | 14783 | 149 | 15677 | 0.1082 | docs(readme): reframe Why around steering + visibility, promote ledgers (#61) |
| claude-code-3b58d484-eb9-1777221519 | claude-code | 3b58d484-eb9e-46ab-88c4-a6145097d4fe | #63 | claude-opus-4-7 | 10 | 40246 | 29566 | 2076 | 42332 | 0.3183 | feat(governance): replace plans-as-audit-artifact with receipts (#63) |
| claude-code-3fa8ea8b-22c-1777223440 | claude-code | 3fa8ea8b-22ce-40b2-9d91-43b45f98e24e | #65 | claude-opus-4-7 | 5 | 15205 | 14783 | 117 | 15327 | 0.1054 | refactor(governance): rename receipt-shape to receipt-per-issue + require What c |
| claude-code-c5503557-0e3-1777223485 | claude-code | c5503557-0e31-400d-9893-168680b87436 | #65 | claude-opus-4-7 | 186 | 269713 | 9877913 | 71021 | 340920 | 8.4011 | refactor(governance): rename receipt-shape M-bM^FM^R receipt-per-issue + require |
| claude-code-c5503557-0e3-1777223522 | claude-code | c5503557-0e31-400d-9893-168680b87436 | #65 | claude-opus-4-7 | 3 | 4005 | 382512 | 2826 | 6834 | 0.2870 | refactor(governance): rename receipt-shape M-bM^FM^R receipt-per-issue + require |
| claude-code-c5503557-0e3-1777223744 | claude-code | c5503557-0e31-400d-9893-168680b87436 | #65 | claude-opus-4-7 | 20 | 19452 | 2679235 | 8672 | 28144 | 1.6781 | refactor(governance): rename receipt-shape M-bM^FM^R receipt-per-issue + require |
| claude-code-b25c8a6f-0cc-1777225550 | claude-code | b25c8a6f-0cc4-4023-bc79-04da0cffece4 | #66 | claude-opus-4-7 | 5 | 14753 | 14783 | 24 | 14782 | 0.1002 | refactor(governance): drop Steer-Key trailers + fix retry-after-failed-commit-ms |
| claude-code-6eabd8fb-a9c-1777274552 | claude-code | 6eabd8fb-a9c7-4135-b2cd-cfe6701af9bb | #69 | claude-opus-4-7 | 5 | 20671 | 14783 | 328 | 21004 | 0.1448 | feat(agent-governance): add ## Checklist + crosswalk to receipts; gate PR existe |
| claude-code-6c9722b7-74f-1777274604 | claude-code | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | claude-opus-4-7 | 419 | 494341 | 28154400 | 400032 | 894792 | 27.1697 | feat(agent-governance): require ## Checklist in receipts; gate PR on completion  |
| claude-code-6c9722b7-74f-1777274652 | claude-code | 6c9722b7-74f8-4fd7-a4ed-5e1c5f8a164f | #69 | claude-opus-4-7 | 3 | 3642 | 634866 | 5238 | 8883 | 0.4712 | feat(agent-governance): add ## Checklist + crosswalk to receipts; gate PR existe |
| claude-code-8d1cac7e-15a-1777274881 | claude-code | 8d1cac7e-15a8-4d39-8fcd-280934346c60 | #69 | claude-opus-4-7 | 5 | 13872 | 14783 | 47 | 13924 | 0.0953 | docs(receipts): drop ceremonial 'Open PR' item from issue-69 checklist (#69) |
| claude-code-f2936bc8-f36-1777275754 | claude-code | f2936bc8-f36b-4527-9b9e-e7797ee651e0 | #69 | claude-opus-4-7 | 5 | 14798 | 14783 | 89 | 14892 | 0.1021 | feat(governance): add post-commit hook kind; move pr-required to it (#69) |
| claude-code-20cdef1a-eeb-1777276294 | claude-code | 20cdef1a-eebd-4171-a004-53c07698ea72 | #69 | claude-opus-4-7 | 5 | 15214 | 14783 | 86 | 15305 | 0.1047 | refactor(governance): replace GOVERNANCE_TEST_PR_EXISTS env-var seam with PATH-s |
| claude-code-fd6439d8-eac-1777277457 | claude-code | fd6439d8-eacb-4ded-83ad-b34a4d82d131 | #71 | claude-opus-4-7 | 5 | 13871 | 14783 | 24 | 13900 | 0.0947 | feat(governance): add pre-push as a supported hook kind (#71) |
| claude-code-2d7aaa04-be7-1777277534 | claude-code | 2d7aaa04-be7a-48c6-a9ce-a75f2824939c | #71 | claude-opus-4-7 | 194 | 457295 | 6723139 | 67642 | 525131 | 7.9117 | feat(governance): add pre-push as a supported hook kind (#71) |
| claude-code-5be94409-9a7-1777279575 | claude-code | 5be94409-9a77-43d9-8d22-b9b26e2ef84a | #73 | claude-opus-4-7 | 5 | 14191 | 14783 | 24 | 14220 | 0.0967 | refactor(agent-governance): tighten pr-required-when-checklist-complete agent co |
| claude-code-6417872e-277-1777279638 | claude-code | 6417872e-2779-4f99-bcf5-3c02cd536f4e | #73 | claude-opus-4-7 | 81 | 137693 | 3602128 | 50969 | 188743 | 3.9363 | refactor(agent-governance): tighten pr-required-when-checklist-complete agent co |
| claude-code-f85dd98a-464-1777284347 | claude-code | f85dd98a-464e-4aad-9b36-afe0ded10cc2 | #75 | claude-opus-4-7 | 5 | 22856 | 14783 | 208 | 23069 | 0.1555 | docs: surface receipts as first-class artifact + add PHILOSOPHY.md (#75) |
| claude-code-15d03f23-c88-1777298979 | claude-code | 15d03f23-c888-45b4-bbc8-eaf2ddc5f37b | #77 | claude-opus-4-7 | 5 | 15440 | 14783 | 87 | 15532 | 0.1061 | feat(governance): add `reset` verb to restore directives to pinned pack version  |
| claude-code-92df7fa3-6f5-1777299221 | claude-code | 92df7fa3-6f5f-4e7c-9f26-49ceec430dee | #77 | claude-opus-4-7 | 140 | 293274 | 5501495 | 133102 | 426516 | 7.9120 | feat(governance): add reset verb to restore directives to pinned pack version (# |
| claude-code-6433df5d-f75-1777304230 | claude-code | 6433df5d-f756-469f-b7c3-9ef32b7c82aa | #79 | claude-opus-4-7 | 5 | 32460 | 0 | 169 | 32634 | 0.2071 | feat(agent-governance): add pr-review-required-when-checklist-complete directive |
| claude-code-a88a9128-eac-1777307085 | claude-code | a88a9128-eaca-4a7e-9209-364b6364b0e7 | #79 | claude-opus-4-7 | 5 | 19737 | 14783 | 433 | 20175 | 0.1416 | feat(governance): loud POST-COMMIT GOVERNANCE FAILED banner for agent readers (# |
| claude-code-6cf1d4fa-561-1777358609 | claude-code | 6cf1d4fa-5613-4ead-b7de-d7341959e74b | #83 | claude-opus-4-7 | 5 | 16057 | 14783 | 154 | 16216 | 0.1116 | refactor(agent-governance): rename review-gate to pr-review-when-pr-ready (#83) |
| claude-code-f9cb7381-084-1777356393 | claude-code | f9cb7381-084a-4920-bbe7-c32415cdff90 | #81 | claude-opus-4-7 | 5 | 16475 | 14783 | 87 | 16567 | 0.1126 | refactor(governance): rename core directive conventional-commits to commit-messa |
| claude-code-87996dc2-5a6-1777356506 | claude-code | 87996dc2-5a66-4609-812d-4e714bfd7fb4 | #81 | claude-opus-4-7 | 203 | 271194 | 11219582 | 80084 | 351481 | 9.3079 | refactor(governance): rename core directive conventional-commits to commit-messa |
| codex-019dd375-06b-1777369983 | codex | 019dd375-06b5-7ef2-b51e-c4d19cc8cc70 | #84 | gpt-5.5 | 216891 | 0 | 1154176 | 8937 | 225828 | 0.9648 | docs(readme): describe repo-state reconciliation (#84) |
| claude-code-14b863b3-9dd-1777447048 | claude-code | 14b863b3-9dd8-42ce-8c22-5dfd650972a8 | #85 | claude-opus-4-7 | 5 | 32667 | 0 | 161 | 32833 | 0.2082 | refactor(agent-governance): decouple steering accounting; retire pr-required dir |
| claude-code-c1f15af7-99e-1777447133 | claude-code | c1f15af7-99e9-4088-973e-20e21c391ad6 | #85 | claude-opus-4-7 | 7027 | 459422 | 25420339 | 181109 | 647558 | 20.1444 | refactor(agent-governance): decouple steering accounting; retire pr-required dir |
| claude-code-5afec8e4-505-1777447671 | claude-code | 5afec8e4-505c-4a33-803c-8487a6a80a64 | #86 | claude-opus-4-7 | 5 | 14425 | 14869 | 24 | 14454 | 0.0982 | refactor(agent-governance): decouple steering accounting; retire pr-required dir |
| claude-code-1a97c22b-7fc-1777447727 | claude-code | 1a97c22b-7fcf-456c-8573-6678139c85c9 | #86 | claude-opus-4-7 | 42 | 61224 | 819654 | 12914 | 74180 | 1.1155 | refactor(agent-governance): decouple steering accounting; retire pr-required dir |
| claude-code-81c29f54-b18-1777449179 | claude-code | 81c29f54-b18f-432d-82e6-ab0d68651bd3 | #87 | claude-opus-4-7 | 5 | 15727 | 14869 | 45 | 15777 | 0.1069 | refactor(governance): retire GOVERNANCE_*_DISABLE env-var sub-check toggles (#87 |
| claude-code-9c1412c3-084-1777449396 | claude-code | 9c1412c3-0840-4404-9c79-0ac0414b3ea0 | #87 | claude-opus-4-7 | 160 | 319831 | 11304599 | 104826 | 424817 | 10.2727 | refactor(governance): retire GOVERNANCE_*_DISABLE env-var sub-check toggles (#87 |
| claude-code-9c1412c3-084-1777449484 | claude-code | 9c1412c3-0840-4404-9c79-0ac0414b3ea0 | #87 | claude-opus-4-7 | 6 | 14915 | 1056139 | 7251 | 22172 | 0.8026 | refactor(governance): retire GOVERNANCE_*_DISABLE env-var sub-check toggles (#87 |
| codex-019dd851-4ff-1777453216 | codex | 019dd851-4ffb-74c3-abd6-f9ffcc0920d3 | #89 | gpt-5.5 | 700167 | 0 | 16548224 | 30883 | 731050 | 6.3507 | refactor(governance): relocate state to dotfolder (#89) |
| codex-019dd851-4ff-1777453404 | codex | 019dd851-4ffb-74c3-abd6-f9ffcc0920d3 | #89 | gpt-5.5 | 14732 | 0 | 1184000 | 921 | 15653 | 0.3466 |  |
| codex-019dd851-4ff-1777453495 | codex | 019dd851-4ffb-74c3-abd6-f9ffcc0920d3 | #89 | gpt-5.5 | 8079 | 0 | 1425536 | 849 | 8928 | 0.3893 |  |
| claude-code-c3833f65-231-1777456515 | claude-code | c3833f65-231c-4c20-8f64-f11b90b9eb6e | #89 | claude-opus-4-7 | 331 | 534447 | 24908248 | 185206 | 719984 | 20.4262 | fix(agent-governance): repair lib.sh comment and add cross-worktree transcript f |
| claude-code-c3833f65-231-1777456586 | claude-code | c3833f65-231c-4c20-8f64-f11b90b9eb6e | #89 | claude-opus-4-7 | 6 | 8813 | 761759 | 3984 | 12803 | 0.5356 | fix(agent-governance): repair lib.sh comment and add cross-worktree transcript f |
| claude-code-6a5db1ad-46c-1777460054 | claude-code | 6a5db1ad-46c9-4268-ac9f-6b80e670aaa8 | #91 | claude-opus-4-7 | 5 | 16423 | 14869 | 146 | 16574 | 0.1138 | refactor(governance): bash-only init; drop stack classification (#91) |
| claude-code-51bf1a91-346-1777460130 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #91 | claude-opus-4-7 | 183 | 241265 | 8735431 | 40900 | 282348 | 6.8990 | refactor(governance): bash-only init; drop stack classification (#91) |
| claude-code-51bf1a91-346-1777460210 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #91 | claude-opus-4-7 | 6 | 7737 | 702232 | 5207 | 12950 | 0.5297 | refactor(governance): bash-only init; drop stack classification (#91) |
| claude-code-e50f35af-f81-1777462243 | claude-code | e50f35af-f812-4770-bffb-209de26d35b3 | #93 | claude-opus-4-7 | 5 | 16233 | 14869 | 129 | 16367 | 0.1121 | test(governance): add comprehensive kit-internal test coverage + local pre-commi |
| claude-code-51bf1a91-346-1777462274 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #93 | claude-opus-4-7 | 191 | 227878 | 30426566 | 151936 | 380005 | 20.4369 | test(governance): add comprehensive kit-internal test coverage + local pre-commi |
| claude-code-51bf1a91-346-1777462302 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #93 | claude-opus-4-7 | 1 | 545 | 276855 | 186 | 732 | 0.1465 | test(governance): add comprehensive kit-internal test coverage + local pre-commi |
| claude-code-51bf1a91-346-1777462404 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #93 | claude-opus-4-7 | 10 | 8860 | 2797069 | 8029 | 16899 | 1.6547 | test(governance): add comprehensive kit-internal test coverage + local pre-commi |
| claude-code-51bf1a91-346-1777462747 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #93 | claude-opus-4-7 | 33 | 51181 | 9922134 | 31882 | 83096 | 6.0782 | test(governance): add comprehensive kit-internal test coverage + local pre-commi |
| claude-code-51bf1a91-346-1777462812 | claude-code | 51bf1a91-3461-487e-b78d-5fdbdb18ce6c | #94 | claude-opus-4-7 | 5 | 6148 | 1574272 | 2604 | 8757 | 0.8907 | refactor(governance): retire pr-review-required-when-pr-ready directive (#94) |
| claude-code-1a97c22b-7fc-1777466021 | claude-code | 1a97c22b-7fcf-456c-8573-6678139c85c9 | #92 | claude-opus-4-7 | 6 | 12090 | 300449 | 1153 | 13249 | 0.2546 | refactor(governance): bash-only init + kit-internal tests + retire pr-review dir |
| claude-code-1a97c22b-7fc-1777466059 | claude-code | 1a97c22b-7fcf-456c-8573-6678139c85c9 | #92 | claude-opus-4-7 | 0 | 0 | 0 | 0 | 0 | 0.0000 | refactor(governance): bash-only init + kit-internal tests + retire pr-review dir |
| claude-code-3ab47c7c-e1f-1777471675 | claude-code | 3ab47c7c-e1f3-491a-804d-b4379c7f089d | #95 | claude-opus-4-7 | 5 | 15960 | 14869 | 123 | 16088 | 0.1103 | ci: bump checkout@v5, consolidate kit-internal tests, fix umbrella git env leak  |
| claude-code-abd20131-333-1777471738 | claude-code | abd20131-333b-4f4a-b2e9-831e15766050 | #95 | claude-opus-4-7 | 209 | 341864 | 11611385 | 91532 | 433605 | 10.2317 | ci: bump checkout@v5, consolidate kit-internal tests, fix umbrella git env leak  |
| claude-code-abd20131-333-1777471839 | claude-code | abd20131-333b-4f4a-b2e9-831e15766050 | #95 | claude-opus-4-7 | 7 | 9515 | 851308 | 6821 | 16343 | 0.6557 | ci: bump checkout@v5, consolidate kit-internal tests, fix umbrella git env leak  |
| claude-code-1b6e8b462ca-1777474500 | claude-code | 1b6e8b46-2cad-4ad9-b513-0eecc4ec897e | #96 | claude-opus-4-7 | 0 | 0 | 0 | 0 | 0 | 0.0000 | refactor(governance): collapse local/ into <owner>/<name> pack namespace          |
| claude-code-d575136b-1c8-1777478193 | claude-code | d575136b-1c82-442f-b0ba-cfa93c9cd42a | #99 | claude-opus-4-7 | 5 | 16565 | 14869 | 45 | 16615 | 0.1121 | refactor(governance): fold agent-governance pack into core (#99) |
| claude-code-7db750f1-073-1777534428 | claude-code | 7db750f1-073e-4a67-b41e-2774982296a6 | #101 | claude-opus-4-7 | 5 | 16202 | 14820 | 45 | 16252 | 0.1098 | feat(governance): husky populator parity + mandatory steering (#101) |
| claude-code-c95ec1d2-be1-1777563991 | claude-code | c95ec1d2-be17-4a45-9f1c-ec7865ad5d9b | #103 | claude-opus-4-7 | 5 | 22498 | 14820 | 318 | 22821 | 0.1560 | refactor(governance): split installed-packs.yaml into install.yaml + packs.lock  |
| claude-code-b69c852e-d25-1777564242 | claude-code | b69c852e-d25d-4dd1-b4fd-21fa59110878 | #103 | claude-opus-4-7 | 424 | 1011558 | 50342222 | 282175 | 1294157 | 38.5498 | refactor(governance): split installed-packs.yaml into install.yaml + packs.lock  |
| claude-code-81b91a66-869-1777564906 | claude-code | 81b91a66-8699-4dc9-8301-2622c1785a81 | #103 | claude-opus-4-7 | 5 | 15615 | 14820 | 69 | 15689 | 0.1068 | docs(governance): narrow directive-amend refusal to source: gh/builtin + add loc |
| claude-code-b69c852e-d25-1777564950 | claude-code | b69c852e-d25d-4dd1-b4fd-21fa59110878 | #103 | claude-opus-4-7 | 48 | 51690 | 10796823 | 30854 | 82592 | 6.4931 | docs(governance): narrow directive-amend refusal + add lockfile-sync step (#103) |
| claude-code-b69c852e-d25-1777565095 | claude-code | b69c852e-d25d-4dd1-b4fd-21fa59110878 | #103 | claude-opus-4-7 | 20 | 20076 | 6935152 | 7582 | 27678 | 3.7827 | docs(governance): narrow directive-amend refusal + add lockfile-sync step (#103) |
| claude-code-585e739b-832-1777566671 | claude-code | 585e739b-8325-4573-8e1d-6a177903eeef | #105 | claude-opus-4-7 | 5 | 15823 | 14820 | 24 | 15852 | 0.1069 | test(governance): rewrite evals for current verb surface (#105) |
| claude-code-723f8267-3fd-1777566816 | claude-code | 723f8267-3fd0-45a4-86b9-8bbb91c0ca49 | #105 | claude-opus-4-7 | 198 | 327616 | 24445495 | 110330 | 438144 | 17.0296 | test(governance): rewrite evals for current verb surface (#105) |
| claude-code-7355eafe-b1d-1777567250 | claude-code | 7355eafe-b1d7-4248-b6f9-ce574b7e9d6c | #105 | claude-opus-4-7 | 5 | 15790 | 14820 | 45 | 15840 | 0.1072 | test(governance): add first-class local-pack evals (#105) |
| claude-code-6787bbce-116-1777624296 | claude-code | 6787bbce-1161-4e95-9331-35bcd688db7c | #107 | claude-opus-4-7 | 5 | 15886 | 14820 | 45 | 15936 | 0.1078 | fix(governance): rewrite eval-report.sh for verb-folder layout (#107) |
| claude-code-53aad805-2c4-1778219678 | claude-code | 53aad805-2c45-4bca-9adb-24ef75bbda0c | #112 | claude-opus-4-7 | 5 | 14757 | 14820 | 66 | 14828 | 0.1013 | feat(governance): receipt-per-issue must require kebab-case slug (#112) |
| claude-code-8f2c46be-a51-1778225550 | claude-code | 8f2c46be-a519-4292-b7b9-6c93214471e3 | #115 | claude-opus-4-7 | 5 | 17981 | 14820 | 293 | 18279 | 0.1271 | feat(governance): add working-tree resolver for self-referential pack fetches (# |
| claude-code-a64b45e3-777-1778225662 | claude-code | a64b45e3-777b-40c3-9916-e50fa435987d | #115 | claude-opus-4-7 | 297 | 549588 | 26881867 | 278185 | 828070 | 23.8320 | feat(governance): add working-tree resolver for self-referential pack fetches (# |
| claude-code-e1b6537a-842-1778227507 | claude-code | e1b6537a-842e-43b7-bf87-51f52046bf8f | #117 | claude-opus-4-7 | 5 | 15280 | 14820 | 24 | 15309 | 0.1035 | feat(governance): relocate core pack to packs/ and drop builtin source type (#11 |
| claude-code-a64b45e3-777-1778228030 | claude-code | a64b45e3-777b-40c3-9916-e50fa435987d | #118 | claude-opus-4-7 | 260 | 294380 | 79200556 | 221924 | 516564 | 46.9896 | feat(governance): lockfile-driven pack reconstruction; retire dogfood mirror (#1 |

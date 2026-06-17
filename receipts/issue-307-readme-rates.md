# Receipt: README core idea and GPT-5.5 rates

## Checklist

- [x] README core idea is crisper while preserving the product story.
- [x] Current README no longer says the durable record or ledger path uses commit trailers.
- [x] agent-token-accounting defaults include `rate gpt-5.5 5.00 5.00 0.50 30.00`.
- [x] Governance checks pass.

## What changed

- `README.md` tightens the opening core idea prose while preserving the same story: agents can complete local tasks while violating repo-level intent, prompt bloat is not durable control, and governance kit moves repeated corrections into executable repo invariants plus issue receipts.
- `README.md` removes the current commit-trailer wording from the durable-record diagram and the invariant ladder, replacing it with receipts/accounting language.
- `packs/audit/directives/agent-token-accounting/defaults.conf` adds the explicit `rate gpt-5.5 5.00 5.00 0.50 30.00` row and adjusts the GPT-5 family comment so GPT-5.5 is no longer described as only a fallback case.
- `receipts/issue-307-readme-rates.md` records this issue's checklist, scope, verification, and attestations.
- README core idea is crisper while preserving the product story.
- Current README no longer says the durable record or ledger path uses commit trailers.
- agent-token-accounting defaults include `rate gpt-5.5 5.00 5.00 0.50 30.00`.

## Decisions

- Kept historical mentions of trailers outside the live README out of scope because they document old behavior in frozen receipts, cost ledgers, or directive rationale.
- Added the GPT-5.5 row in the source pack under `packs/audit/` only, matching the repo rule that source pack changes do not hand-edit the consumed `.governance/` tree.

## Out of scope

- No change to historical `COSTS.md`, `STEERING.md`, or old receipts that mention retired trailer behavior.
- No release/version bump or consumed-tree update.

## Verification

```sh
rg -n "trailers|Git trailers|receipt \\+ trailers" README.md
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost gpt-5.5 1000000 1000000 1000000 1000000
bash .governance/run.sh
```

Governance checks pass.

## Audit

PASS - The receipt maps to the intended diff: `README.md` carries the crisper core idea and no longer uses trailer language for the live durable record or ledger row; `packs/audit/directives/agent-token-accounting/defaults.conf` adds the requested GPT-5.5 rate row; and this receipt names every changed file. The checklist mirrors issue #307's acceptance criteria and each checked item is evidenced in `## What changed` or `## Verification`.

## Layer boundaries

PASS - The changed files stay in their owning layers: public README copy remains at the repo root, pack-owned rate-card data changes in the audit pack source under `packs/audit/`, and the receipt lives under `receipts/`. No kit engine logic lands in a pack and no consumed `.governance/` materialization is hand-edited.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed445-462-1781678243-1 | codex | 019ed445-4625-7af2-bb97-4059ffe54704 | #307 | gpt-5.5 | 157214 | 0 | 1757568 | 7816 | 165030 | 0.9497 | 157214 | 0 | 1757568 | 7816 | docs(readme): sharpen core idea and rates (#307) |
| codex-019ed445-462-1781678392-1 | codex | 019ed445-4625-7af2-bb97-4059ffe54704 | #307 | gpt-5.5 | 40821 | 0 | 636032 | 1360 | 42181 | 0.2815 | 198035 | 0 | 2393600 | 9176 | docs(readme): sharpen core idea and rates (#307) -m governance: allow-agent-toke |

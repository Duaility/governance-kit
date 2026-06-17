# Issue 314: Refine README headings and navigation

Closes [#314](https://github.com/Duaility/governance-kit/pull/314).

## Checklist

- [x] README installation guidance appears before the rule-depth explanation.
- [x] README section headings use question-form labels where they explain reader concerns.
- [x] README navigation anchors match the renamed sections.
- [x] README introduces the constitution as the repo's set of invariants.
- [x] Governance suite passes.

## What changed

- `README.md` now places `How do you install it in 60 seconds?` and `Where should you read next?` before `How strict can a rule be?`, so installation comes before the deeper rule model.
- `README.md` now uses question-form section headings for reader-facing sections, including `What problem does it solve?`, `What does Governance Kit change?`, `How does the loop work?`, `What are packs?`, and `How does it compare?`.
- `README.md` updates the top navigation anchors to match the renamed question-form section headings.
- `README.md` introduces the term constitution in the core explanation: Governance Kit calls the repo's set of invariants a constitution, represented by `CONSTITUTION.md` plus directive rationale and checks.
- `receipts/issue-314-readme-headings-navigation.md` records the README heading, navigation, constitution-terminology, and CI-repair work for this issue.

README installation guidance appears before the rule-depth explanation.
README section headings use question-form labels where they explain reader concerns.
README navigation anchors match the renamed sections.
README introduces the constitution as the repo's set of invariants.

## Out of scope

- No kit runtime, skill shim, bundled pack source, consumed `.governance/` tree, or generated docs site pages changed.
- No product behavior or directive behavior changed.

## Decisions

- Kept terse non-reader-flow headings only where the README convention is clearer than a question, such as table column labels and details summaries.
- Treated PR #314 as the receipt token because the change was opened directly as a README refinement PR without a separate issue.

## Verification

```sh
bash .governance/run.sh
```

Result: all 17 governance directives passed locally after adding this receipt.

Governance suite passes.

## Audit

PASS - Checked against the branch diff and PR #314. The product-facing change is limited to `README.md`, and this receipt names the actual README edits: installation moved before rule-depth explanation, question-form headings, updated navigation anchors, clearer docs routing, and the constitution terminology. The checklist items crosswalk into `## What changed` and `## Verification`.

## Layer boundaries

PASS - The diff stays in the documentation and audit layers: `README.md` is public repo documentation and this receipt lives under `receipts/`. No `skill/`, `kit/`, `packs/`, or consumed `.governance/` runtime/source files are modified, and no dependency edge changes across the declared skill -> kit -> packs -> consumed repo model.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed52d-983-1781693997-1 | codex | 019ed52d-983e-72d3-8919-8a181b53b3e6 | #314 | gpt-5.5 | 220386 | 0 | 2514432 | 14569 | 234955 | 1.3981 | 220386 | 0 | 2514432 | 14569 | docs(readme): refine headings and navigation (#314) |

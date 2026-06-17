## Checklist

- [x] README section headers use direct developer-facing language.
- [x] The Documentation section clearly tells developers when to use the site vs kit/references.
- [x] README self-links still resolve.
- [x] Governance suite passes.

## What changed

- Updated `README.md` so README section headers use direct developer-facing language: `Why this exists`, `How strict a rule can be`, `What you get`, `Install in 60 seconds`, `What ships with it`, `This repo uses it`, `Use it from any agent`, `When it fits`, `Commands you will use`, `Read the docs`, and `How it compares`.
- Updated the top README navigation anchors to match the renamed sections.
- Replaced the confusing Documentation intro so the Documentation section clearly tells developers when to use the site vs kit/references: use the site when learning the tool, and use `kit/references/` when changing behavior or checking the exact runtime contract.
- Updated the old `Lifecycle` self-link in `README.md` to point at `Commands you will use`, so README self-links still resolve.

README section headers use direct developer-facing language.
The Documentation section clearly tells developers when to use the site vs kit/references.

## Out of scope

- No product behavior, kit runtime, pack source, consumed `.governance/` tree, or generated docs site pages changed.
- No broader README restructuring beyond the requested tone and clarity cleanup.

## Decisions

None.

## Verification

```sh
bash .governance/run.sh
```

Result: all 17 governance directives passed.

This verifies that the governance suite passes.

## Audit

PASS - Checked against the diff and issue #311. `README.md` is the only product-facing file changed, and the receipt names the exact README edits: developer-facing section headers, matching navigation anchors, clearer Documentation guidance for site vs `kit/references/`, and the updated self-link to `Commands you will use`. The checklist mirrors issue #311's acceptance criteria, and each checked item is realized by the README diff or the recorded governance run.

## Layer boundaries

PASS - The change stays in the documentation layer: `README.md` is public repo documentation and this file is the issue receipt. No `skill/`, `kit/`, `packs/`, or `.governance/` runtime/source trees are changed, no dependency edge is introduced across the declared `skill -> kit -> packs -> consumed repo` model, and no shared logic is added or duplicated.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed514-c35-1781691756-1 | codex | 019ed514-c35d-7230-9dca-1be95a0903ca | #311 | gpt-5.5 | 122447 | 0 | 1606912 | 7632 | 130079 | 0.8223 | 122447 | 0 | 1606912 | 7632 | docs: refine README section tone (#311) |

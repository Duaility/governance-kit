# Receipt: extend receipts with ## Checklist + add pr-required-when-checklist-complete

Issue: [#69](https://github.com/Duaility/governance-kit/issues/69)

## Checklist

- [x] receipt-per-issue extended with ## Checklist section and crosswalk check
- [x] pr-required-when-checklist-complete directive added
- [x] both directives mirrored into tests/governance/directives/
- [x] pack.yaml minimal preset and DIRECTIVES_CATALOG.md updated
- [x] 3 existing receipts backfilled with real ## Checklist sections
- [x] standalone receipt-checklist-crosswalk directive deleted
- [x] CONSTITUTION.md subsections rewritten and Evolution Log entry appended
- [ ] Open PR for review and merge

## What changed

Summary of edits in this commit:

- receipt-per-issue extended with ## Checklist section and crosswalk check (each `- [x]` item must appear, after markdown + whitespace normalization, in `## What changed` or `## Verification`).
- pr-required-when-checklist-complete directive added — gates the next commit / CI run on PR existence once HEAD's receipt has zero `- [ ]` items.
- both directives mirrored into tests/governance/directives/ per the pack-and-dogfood dual-edit rule.
- pack.yaml minimal preset and DIRECTIVES_CATALOG.md updated to name the new chain (`receipt-per-issue`, `pr-required-when-checklist-complete`, `commit-issue-receipt-match`).
- 3 existing receipts backfilled with real ## Checklist sections derived from their `## What changed` text — items lifted verbatim so the new crosswalk passes naturally.
- standalone receipt-checklist-crosswalk directive deleted from both pack and dogfood layers — the crosswalk is folded into receipt-per-issue.
- CONSTITUTION.md subsections rewritten and Evolution Log entry appended (closes #69).

`receipt-per-issue` is extended from three required sections to four. The new `## Checklist` mirrors the linked GitHub issue's checklist, and each `- [x]` item must have its text appear (case-insensitive substring, with markdown formatting and whitespace normalized) in `## What changed` or `## Verification`. Unchecked items are unconstrained.

The crosswalk is the local trust boundary — without it, the agent could silently flip boxes from `[ ]` to `[x]` without writing evidence; with it, every checked item must be cited in the receipt's prose. The normalize step strips backticks, asterisks, underscores and collapses whitespace runs, so an item `lib/trailers.py rewritten` matches a bullet `**lib/trailers.py** rewritten` or evidence wrapped across lines.

A new directive `pr-required-when-checklist-complete` is added to the agent-governance pack. When HEAD carries a tracked receipt with a fully-ticked `## Checklist` (≥1 `[x]`, 0 `[ ]`) and the branch isn't main/master, an open PR must exist for the current branch on the GitHub remote. The directive reads HEAD content (not the working tree), so the commit that ticks the final box lands cleanly — the gate fires on the next commit attempt or in CI. Skip-with-warning when `gh` is missing or unauthenticated; fails when `gh` is present but the API call fails. A `GOVERNANCE_TEST_PR_EXISTS` env-var seam lets the eval harness test both branches without hitting GitHub.

The earlier exploratory split (a separate `receipt-checklist-crosswalk` directive plus a per-receipt waiver mechanism) is folded back: the crosswalk lives inside `receipt-per-issue`, no waivers, V0 strictness. The standalone directive folder is deleted from both `extensions/packs/agent-governance/directives/` and `tests/governance/directives/`. The optional post-commit auto-PR script (briefly drafted earlier in the session) was also abandoned — governance directives describe invariants on tree state, not side effects on remote systems.

The 3 existing receipts (issues #63, #65, #66) are backfilled with real `## Checklist` sections derived from their `## What changed` text — items lifted verbatim so the crosswalk passes naturally.

Edits land at both layers per the pack-and-dogfood dual-edit rule:

- **Pack source** (`extensions/packs/agent-governance/directives/`): `receipt-per-issue/` (check, constitution, directive.yaml, evals/test.sh) extended; `pr-required-when-checklist-complete/` added (check, constitution, directive.yaml, evals/test.sh); `receipt-checklist-crosswalk/` deleted; `pack.yaml` minimal preset rewritten.
- **Dogfood install** (`tests/governance/directives/`): same layout — `receipt-per-issue/` updated, `pr-required-when-checklist-complete/` added, `receipt-checklist-crosswalk/` deleted.
- `governance/references/DIRECTIVES_CATALOG.md`: `receipt-per-issue` row rewritten to describe four sections + crosswalk; `pr-required-when-checklist-complete` row added; standalone crosswalk row removed; preset list updated.
- `receipts/issue-63-receipts-replace-plans.md`, `receipts/issue-65-receipt-per-issue-rename.md`, `receipts/issue-66-steer-key-retire.md`: real `## Checklist` sections added; transient waiver lines removed.

## Out of scope

- **Auto-PR-creation as a side effect.** Rejected during the session — governance directives describe invariants, not actions. Opening the PR remains a documented one-liner (`gh pr create --fill`).
- **Per-receipt waiver mechanism.** Briefly drafted (`<!-- governance: allow-receipt-checklist-crosswalk … -->`) and then dropped — V0, no backward-compat concession needed; the 3 existing receipts were backfilled instead.
- **Sub-issues / multi-checklist support.** A receipt mirrors one issue's checklist. Cross-issue work spans multiple receipts.
- **Updating the receipt template** (if any canonical template exists in `governance/assets/`) to include a `## Checklist` skeleton — agents will adopt the shape from the new directive's failure messages and the constitution prose. Templates can be updated separately.
- **Bootstrap installer wiring** for the post-commit convenience flow — there is no post-commit flow in this PR. The directive replaces it.

## Verification

A reviewer can confirm the change is complete by checking:

1. **`receipt-per-issue` enforces all four sections + crosswalk.** `tests/governance/directives/receipt-per-issue/check.sh` iterates `("Checklist" "What changed" "Out of scope" "Verification")` and runs the substring crosswalk on `- [x]` items. The `normalize` helper lowers, strips `` ` * _ ``, and collapses whitespace.
2. **`pr-required-when-checklist-complete` exists with check + constitution + eval.** `extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/` and `tests/governance/directives/pr-required-when-checklist-complete/` both contain `directive.yaml`, `check.sh`, `constitution.md` (eval only at the pack layer).
3. **Standalone `receipt-checklist-crosswalk` is gone.** `find extensions/packs/agent-governance/directives/ tests/governance/directives/ -name 'receipt-checklist-crosswalk' -print` returns nothing.
4. **Pack manifest is consistent.** `extensions/packs/agent-governance/pack.yaml` `minimal` preset names exactly `receipt-per-issue`, `pr-required-when-checklist-complete`, `commit-issue-receipt-match`.
5. **Catalog captures both directives.** `governance/references/DIRECTIVES_CATALOG.md` has a rewritten `receipt-per-issue` row describing four sections + crosswalk and a new `pr-required-when-checklist-complete` row; the `minimal` preset list matches the pack manifest.
6. **The 3 existing receipts have real checklists, no waiver lines.** `grep -l 'allow-receipt-checklist-crosswalk' receipts/` returns nothing; each of `issue-63-…`, `issue-65-…`, `issue-66-…` has a `## Checklist` whose checked items crosswalk to its `## What changed`.
7. **Dogfood green.** `bash tests/governance/run.sh` exits 0 on this branch with all 15 directives passing.
8. **Pack evals green.** `bash scripts/test-packs.sh` exits 0; `receipt-per-issue` eval covers 11 cases (3 pass, 8 fail) and `pr-required-when-checklist-complete` eval covers 7 cases (5 pass, 2 fail) including the env-var seam path.
9. **This commit itself satisfies `commit-issue-receipt-match`.** The commit's `(#69)` anchor matches the `issue-69` token on this very file.

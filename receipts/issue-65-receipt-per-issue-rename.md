# Receipt: rename receipt-shape → receipt-per-issue and require three sections

Issue: [#65](https://github.com/Duaility/governance-kit/issues/65)

## Checklist

- [x] renamed to receipt-per-issue
- [x] section check is expanded
- [x] deferred-work section is canonicalised to ## Out of scope
- [x] Folder rename completed at both layers
- [x] Eval coverage extended

## What changed

The `receipt-shape` directive is renamed to `receipt-per-issue`, and its section check is expanded from one required section (`## Verification`) to three (`## What changed`, `## Out of scope`, `## Verification`).

The rename surfaces what the directive actually enforces ("one receipt per issue") rather than the TS-ish "shape" framing. It also restores parallelism with the retired `plan-per-issue` directive this lineage descends from.

The expanded section check bakes in conventions that already organically appeared on the only tracked receipt (`receipts/issue-63-receipts-replace-plans.md`): reviewers were leaning on `What changed` (surface area) and the deferred-work block ("What is NOT in this change") even though only `Verification` was mechanically required. The deferred-work section is canonicalised to `## Out of scope` (shorter than "What is NOT in this change") and the existing receipt's heading is updated in place.

Edits land at both layers per the pack-and-dogfood dual-edit rule:

- **Pack source** (`extensions/packs/agent-governance/directives/`): `receipt-shape/` renamed to `receipt-per-issue/` via `git mv`. `directive.yaml`, `check.sh`, `constitution.md`, and `evals/test.sh` updated. The eval grew two new failure cases (missing `## What changed`, missing `## Out of scope`) and the existing pass cases were extended to include all three required sections.
- **Dogfood install** (`tests/governance/directives/`): same folder rename and same updates to `directive.yaml`, `check.sh`, `constitution.md` (no eval at this layer).
- `CONSTITUTION.md`: `### receipt-shape` subsection renamed to `### receipt-per-issue` with the new directive text; `commit-issue-receipt-match` rationale updated to reference the new id; Evolution Log entry appended (2026-04-26, closes #65).
- `.governance-kit/installed-packs.yaml`: directive id and installed-path updated under `duaility/agent-governance`.
- `extensions/packs/agent-governance/pack.yaml`: `minimal` preset directive list updated and the chain comment updated.
- `extensions/packs/agent-governance/README.md`: directive table row renamed.
- `extensions/packs/agent-governance/directives/commit-issue-receipt-match/`: rationale comment in `check.sh` and rationale line in `constitution.md` updated to reference the new id (mirrored in the dogfood layer).
- `extensions/catalog.community.json`: pack summary updated.
- `governance/references/DIRECTIVES_CATALOG.md`: catalog row and `minimal` preset row updated; the row's section list now names all three required sections.
- `README.md`: pack table summary row updated.
- `receipts/issue-63-receipts-replace-plans.md`: the `## What is NOT in this change` heading is renamed to `## Out of scope` so the historical receipt continues to satisfy the new directive. Body text describing the #63 work as it stood at the time (referencing `receipt-shape`) is preserved as a point-in-time record.

## Out of scope

- **Splitting the directive** into `receipt-per-issue` (filename binding) + `receipt-has-verification` (section check) — discussed and deferred. Keeping bundled.
- **Other receipt sections** considered (Follow-ups, Risks/Rollback, Evidence, Reviewer hints) — left as template suggestions, not enforced. The trap with required sections is that every one of them is one more thing to fake.
- **Retroactive edits** to the body of `receipts/issue-63-receipts-replace-plans.md` describing the directive's old name. Receipts are point-in-time records; the Evolution Log carries the rename forward.
- **Coverage check** ("every closed issue has a receipt") — still out of scope, same as #63.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Folder rename completed at both layers.** `extensions/packs/agent-governance/directives/receipt-per-issue/` and `tests/governance/directives/receipt-per-issue/` exist; the old `receipt-shape/` paths do not.
2. **Check enforces all three required sections.** `tests/governance/directives/receipt-per-issue/check.sh` iterates over `("What changed" "Out of scope" "Verification")` and emits a violation per missing section. Smoke test on this branch: `bash tests/governance/run.sh receipt-per-issue` exits 0.
3. **Eval coverage extended.** `extensions/packs/agent-governance/directives/receipt-per-issue/evals/test.sh` now includes two new failure cases (`missing-what-changed`, `missing-out-of-scope`) alongside the existing `missing-verification`. `bash scripts/test-packs.sh` exits 0.
4. **Manifest is consistent.** `.governance-kit/installed-packs.yaml` lists `receipt-per-issue` (not `receipt-shape`) under `duaility/agent-governance`. `extensions/packs/agent-governance/pack.yaml` `minimal` preset names `receipt-per-issue`.
5. **No live references to `receipt-shape` remain** outside the two Evolution Log entries (the original 2026-04-26 entry for #63 and the new entry for #65) and the body of `receipts/issue-63-receipts-replace-plans.md`. Search: `grep -rn 'receipt-shape'`.
6. **Constitution captures the change.** `CONSTITUTION.md` has the `### receipt-per-issue` subsection (the old `### receipt-shape` subsection is gone), the `commit-issue-receipt-match` rationale references the new id, and the Evolution Log carries a 2026-04-26 entry referencing #65.
7. **Existing receipt still passes.** `receipts/issue-63-receipts-replace-plans.md` carries `## What changed`, `## Out of scope`, and `## Verification` (the heading rename completes this).
8. **This commit itself satisfies `commit-issue-receipt-match`.** The commit's `(#65)` anchor matches the `issue-65` token on this very file.
9. **Smoke test passes.** `bash tests/governance/run.sh` exits 0 on this branch.

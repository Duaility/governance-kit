# issue-124 — file-level waiver for repo-hygiene file-size-limit

Closes [#124](https://github.com/Duaility/governance-kit/issues/124).

## Checklist

- [x] `has_file_waiver` helper in `lib.sh`
- [x] Wire the helper into the `file-size-limit` block
- [x] Constitution snippet documents the waiver
- [x] Pack eval covers fail-without-waiver and pass-with-waiver
- [x] Runtime test covers the helper's scoping
- [x] Root `CONSTITUTION.md` and Evolution Log updated
- [x] `DIRECTIVES_CATALOG.md` row updated

## What changed

- **`has_file_waiver` helper in `lib.sh`.** Added alongside the existing `has_waiver`, in both the asset source (`governance/assets/dot-governance/lib.sh`) and the dogfood runtime (`.governance/lib.sh`). Signature: `has_file_waiver <file> <directive> <sub-check>`. It scans the first 10 lines of the file and matches `governance: allow-<directive> <sub-check>` (any comment syntax — the token is just a substring grep). Sub-check name is required (not optional) so future file-level sub-checks under the same directive can share the `allow-<directive>` prefix without colliding. The sibling line-level `has_waiver` is unchanged.
- **Wire the helper into the `file-size-limit` block.** `packs/core/directives/repo-hygiene/check.sh` (and the gitignored dogfood mirror at `.governance/packs/governance-kit/core/directives/repo-hygiene/check.sh`) now call `has_file_waiver "$file" "repo-hygiene" "file-size-limit" && continue` before the `wc -l` line count, so a tagged file is skipped before the threshold is even checked.
- **Constitution snippet documents the waiver.** The directive's `constitution.md` (pack source + dogfood mirror) names the new file-level waiver in both the `file-size-limit` sub-check bullet and the Exceptions clause, alongside the existing line-level waiver for `debug-statements`.
- **Pack eval covers fail-without-waiver and pass-with-waiver.** `packs/core/directives/repo-hygiene/evals/test.sh` gains two paired cases driven by `GOVERNANCE_FILE_SIZE_LIMIT=5` against a 12-line `.ts` fixture: first without a head-of-file token (must fail), then with `// governance: allow-repo-hygiene file-size-limit ISSUE-124 ...` (must pass). The same fixture is reused so the only differentiator is the waiver line.
- **Runtime test covers the helper's scoping.** `scripts/test-runtime.sh` gains six new assertions (`44` total, was `38`): empty-file no-token → no waiver; line-1 token → waiver; line-10 token (boundary) → waiver; line-11 token (just past the head window) → no waiver; correct directive id but wrong sub-check → no waiver; correct sub-check but wrong directive id → no waiver. The header docstring is updated to enumerate the new helper.
- **Root `CONSTITUTION.md` and Evolution Log updated.** Line 74 (the `file-size-limit` sub-check description) names the file-level waiver. Line 77's Exceptions clause names both waivers in parallel form. A new Evolution Log entry under 2026-05-08 explains the change, names the new helper signature, and closes #124.
- **`DIRECTIVES_CATALOG.md` row updated.** The `repo-hygiene` row's `file-size-limit` sub-check description names the file-level waiver and clarifies the `debug-statements` waiver as line-level.

## Out of scope

- Adding head-of-file waivers to `large-files`, `build-artifacts`, or `merge-markers`. `large-files` is binary-blob-shaped (LFS / external host is the right answer); `build-artifacts` is filename-pattern-shaped (`.gitignore` is the right answer); `merge-markers` is a transient bug, not a pattern that ever wants a waiver. Only `file-size-limit` had a real "this entry-point file is legitimately large and we know it" use case (downstream report: [srikanth235/centraid#8](https://github.com/srikanth235/centraid/issues/8)).
- Repo-config waiver schema (`.governance/exceptions.yaml` proposed in option 2 of #124). The in-file token is reviewable in `git blame` and avoids a new schema; the proposal section in #124 picks option 1 as the chosen shape.
- Backfilling waivers in downstream consumers (centraid `apps/desktop/src/renderer/app.ts` / `builder.ts`). That's a downstream concern — once this PR lands and centraid consumes a kit version that ships the helper, they replace `--no-verify` with the head-of-file token at their leisure.
- Changing the 10-line head window. Long enough to clear shebang + license header + a few imports; short enough to stay near the file's identity block. No knob until a real use case shows up.

## Verification

- `bash .governance/run.sh` → ✓ all 14 directives passed (`pre-commit-test-gate`, `agent-steering-accounting`, `agent-token-accounting`, `commit-issue-receipt-match`, `commit-message-format`, `doc-freshness`, `issue-templates`, `issues-tracked`, `no-broken-internal-doc-links`, `receipt-per-issue`, `repo-hygiene`, `required-docs`, `secrets-hygiene`, `workflows-hardened`).
- `bash scripts/test.sh` → ✓ all kit-internal test layers passed. `test-runtime`: 44 assertions (6 new for `has_file_waiver`). `test-packs`: 1 pack, 14 directives, 14 evals — including the two new `repo-hygiene file-size-limit` and `repo-hygiene file-size-limit waiver` cases.
- `bash scripts/test-runtime.sh` standalone → ✓ 44/44 assertions, including the line-10 / line-11 boundary cases that pin the 10-line head window contract.

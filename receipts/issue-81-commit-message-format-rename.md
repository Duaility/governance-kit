# Receipt: rename core directive conventional-commits → commit-message-format

Issue: [#81](https://github.com/Duaility/governance-kit/issues/81)

## Checklist

- [x] Folder rename completed at both layers
- [x] Pack source and dogfood twin agree
- [x] Eval still exercises the renamed directive
- [x] Dogfood suite picks up the renamed directive
- [x] Manifest is consistent
- [x] Constitution captures the change
- [x] Cross-directive `required-docs` check still gates the commit-msg hook on the right directive
- [x] No live references to `conventional-commits` remain
- [x] This commit itself satisfies `commit-issue-receipt-match`
- [x] Smoke test passes

## What changed

The core directive id `conventional-commits` is renamed to `commit-message-format`. The old id understated what the regex actually enforced: a Conventional Commits prefix **plus** a trailing `(#N)` GitHub issue suffix — the issue suffix is a governance-kit-specific extension, not part of the published Conventional Commits spec. A reader scanning the directive list would reasonably expect the directive to enforce only the spec.

The new id describes the surface (the commit message) without locking any particular spec into the name, leaving headroom for further format rules without a second rename. The constitution snippet text was expanded in the same change to call out the Conventional-Commits-plus-issue-suffix coupling explicitly, so future readers don't need to chase the regex to understand the rule.

Pre-1.0 breaking change with no alias period — consistent with the project's V0 stance: no installed-base migration arguments are load-bearing while the kit is pre-stable.

Edits land at every layer that names the directive id, in lockstep:

- **Pack source** (`governance/assets/packs/core/directives/`): `conventional-commits/` renamed to `commit-message-format/` via `git mv`. `check.sh` `directive_start` id and the file header (which referenced the old script name) updated; `evals/test.sh` `EVAL_ID` updated; `directive.yaml` header comment updated; `constitution.md` heading rewritten and the directive paragraph expanded to surface the issue-suffix coupling explicitly.
- **Dogfood install** (`tests/governance/directives/`): same folder rename via `git mv` and same content updates synced from the pack source (no drift).
- **`core` pack manifest** (`governance/assets/packs/core/pack.yaml`): `standard` preset directive list updated.
- **Dogfood manifest** (`.governance-kit/installed-packs.yaml`): id and `installed_path` updated under the `core` block.
- **CONSTITUTION.md**: `### conventional-commits` subsection renamed to `### commit-message-format` with the expanded directive text; the `required-docs` `hooks` sub-check (line 39) and the `commit-issue-receipt-match` rationale (line 121) and exception clause (line 123) updated to reference the new id; Evolution Log entry appended (2026-04-28, closes #81).
- **Cross-directive prose refs**: `required-docs` `check.sh` (the file-existence check that decides whether `.githooks/commit-msg` is required) and its `constitution.md` `hooks` sub-check; `commit-issue-receipt-match` `check.sh` (rationale comment + the inline comment near the no-issue-anchor branch) and its `constitution.md` (rationale + exception clause) — all updated at both pack and dogfood layers.
- **Reference docs**: `README.md` (the demo-failure block on line 74 and the core-pack table row on line 146), `governance/references/DIRECTIVES_CATALOG.md` (catalog row + `standard` preset row), `RESET_FLOW.md`, `DIRECTIVE_AMEND_FLOW.md`, and `AGENT_TOKEN_ACCOUNTING.md` updated.

## Out of scope

- **Rewriting historical evolution-log entries** in CONSTITUTION.md that reference `conventional-commits` (lines 176, 183, 184) — they describe what was true at the time the directive carried that id. The Evolution Log carries the rename forward.
- **Splitting the directive** into a Conventional-Commits-only check + a separate issue-suffix check — discussed and rejected. The two halves are enforced as one rule because a CC message without the issue anchor is still a hole in the audit trail this kit cares about.
- **An alias period** that accepted both old and new ids during a deprecation window — explicitly skipped per the project's V0 stance.
- **Touching past commit messages or branch history** — past commits remain valid against the rule they were authored under (the regex itself is unchanged).
- **Waiver tokens** — none defined for this directive, so no waiver-string migration is needed.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Folder rename completed at both layers.** `governance/assets/packs/core/directives/commit-message-format/` and `tests/governance/directives/commit-message-format/` exist; the old `conventional-commits/` paths do not. `git log --diff-filter=R` shows the rename pair (the worktree-level edits I made are pure renames at the file level — git tracks them via `git mv`).
2. **Pack source and dogfood twin agree.** `diff -r governance/assets/packs/core/directives/commit-message-format tests/governance/directives/commit-message-format` reports `Only in governance/assets/packs/core/directives/commit-message-format: evals` (eval fixtures live only in the pack source — same divergence as every other directive in the repo).
3. **Eval still exercises the renamed directive.** `bash governance/assets/packs/core/directives/commit-message-format/evals/test.sh` shows three checks (`commit-message-format well-formed` pass, `commit-message-format no-issue` fail, `commit-message-format bad-type` fail) and exits 0. `bash scripts/test-packs.sh` exits 0 across both packs (16 directives, 16 evals).
4. **Dogfood suite picks up the renamed directive.** `bash tests/governance/run.sh` lists `commit-message-format` (not `conventional-commits`) in its output and reports it passing. The remaining `pr-required-when-checklist-complete` failure is a pre-existing post-commit advisory on this branch unrelated to this rename, and quiets once a PR is opened.
5. **Manifest is consistent.** `.governance-kit/installed-packs.yaml` lists `commit-message-format` under the `core` block. `governance/assets/packs/core/pack.yaml` `standard` preset names `commit-message-format`.
6. **No live references to `conventional-commits` remain** outside the historical evolution-log entries (CONSTITUTION.md lines 176, 183, 184) and the new entry on line 201 documenting this rename. Search: `grep -rn 'conventional-commits' --include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml' --include='*.json'`. Receipts and plans under `receipts/` and `plans/` are intentionally untouched (point-in-time records).
7. **Constitution captures the change.** `CONSTITUTION.md` has the `### commit-message-format` subsection (the old `### conventional-commits` subsection is gone), the `required-docs` `hooks` sub-check and the `commit-issue-receipt-match` rationale and exception clause reference the new id, and the Evolution Log carries a 2026-04-28 entry referencing #81.
8. **Cross-directive `required-docs` check still gates the commit-msg hook on the right directive.** `tests/governance/directives/required-docs/check.sh` looks for `tests/governance/directives/commit-message-format/check.sh` (not the old path) when deciding whether to require `.githooks/commit-msg`.
9. **This commit itself satisfies `commit-issue-receipt-match`.** The commit's `(#81)` anchor matches the `issue-81` token on this very file.
10. **Smoke test passes.** `bash tests/governance/run.sh` exits 0 on this branch (modulo the pre-existing PR-required advisory noted in #4).

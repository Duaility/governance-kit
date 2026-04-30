# issue-101 — husky populator parity + mandatory steering

Closes [#101](https://github.com/Duaility/governance-kit/issues/101).

## Checklist

- [x] Strategy-aware dispatcher generator
- [x] Test coverage for the husky path
- [x] Doc updates
- [x] Mandatory `agent-steering-accounting`
- [x] Evolution log entry

## What changed

- **Strategy-aware dispatcher generator.** Added `generate_hooks_for_strategy <repo-root> <strategy> <version> <spec>` to `governance/assets/packs/lib/hooks.sh` as the single entry point used by `governance init`, `governance pack add`, and `governance reset` for hook materialization. The wrapper picks the install dir per `hook_strategy` (`githooks → .githooks/`, `husky → .husky/`, `pre-commit → .governance/hooks/`) and emits identical dispatcher bodies in every case. The dispatcher discovers `directives/<id>/hooks/<kind>.sh` populators on the filesystem and chains them ahead of `check.sh`, so populator coverage is uniform across host frameworks. Pre-issue-101 husky installs landed only a `bash .governance/run.sh` shim that ignored `hook:` filtering and skipped populators — token-accounting / steering-accounting trailers had no populator coverage on husky, breaking commits at the validator. The wrapper closes that gap.
- **Test coverage for the husky path.** Extended `scripts/test-hooks-sh.sh` with a `generate_hooks_for_strategy` block (~36 new assertions): per-strategy install dirs are honored (`githooks`, `husky`, `pre-commit`); generated husky dispatchers carry the line-2 ownership marker; populator-loop wiring (`directive_dirs_for_hook <kind> helper`) appears in husky `pre-commit` and `prepare-commit-msg` exactly as it does in the `.githooks/` path; regen-on-marker bumps `pack-version=` silently; an unmarked pre-existing husky hook is preserved with its content intact and the wrapper returns non-zero; an unknown strategy is rejected loudly. Total `test-hooks-sh.sh` is now 83 assertions, all green.
- **Doc updates.** `governance/references/INIT_FLOW.md` Step 6 directs callers to `generate_hooks_for_strategy` (not bare `generate_hooks`), and Path B's husky / pre-commit.com paragraphs now route through the same generator with the framework-specific strategy. `governance/references/NATIVE_TESTS.md` husky and pre-commit.com sections replace the "add `bash .governance/run.sh`" shim snippet with the `generate_hooks_for_strategy` invocation and explain why the shim was wrong. `governance/references/PACK_VERBS.md` and `RESET_FLOW.md` regen-the-hook-dispatcher steps point at the strategy-aware wrapper. `hooks.sh`'s top-of-file contract block documents the new function.
- **Mandatory `agent-steering-accounting`.** `directive.yaml` flips `recommended: false` → `recommended: true` and gains `always_install: true` (matching `repo-hygiene`'s "bypasses the menu" stance) — both the source pack template and the dogfood mirror under `.governance/packs/governance-kit/core/`. `governance/assets/packs/core/pack.yaml` adds the directive to the `standard` preset and rewrites the explanatory comment to reflect the new mandatory framing. The directive's `constitution.md` (source + dogfood) and the kit's own `CONSTITUTION.md` mirror replace the "opt-in only, never in any preset" sentence with mandatory-with-classifier-redaction guidance — public-repo operators redact verbatim text inside the classifier hook rather than skip the directive. `DIRECTIVES_CATALOG.md` updates the directive row, the pack-summary cell, and the preset table to match. The directive's `check.sh` is unchanged — behaviour is identical, install gating is what shifted.
- **Evolution log entry** added to `CONSTITUTION.md` describing the husky-parity refactor and the steering-accounting promotion together (they shipped as one issue).

## Out of scope

- A husky-side install-time sanity check that verifies every directive's `hooks/<kind>.sh` populator resolves to a wired entry. The runtime-discovery loop in the generated dispatcher already does this implicitly (it iterates the filesystem), and the test suite asserts the wiring text appears in every generated husky dispatcher. A separate validator would duplicate the contract without adding signal.
- A `populator_hooks:` field on `directive.yaml` (Option B from the issue's "Suggested fix" section). The filesystem convention `directives/<id>/hooks/<kind>.sh` is already the manifest — adding a redundant YAML declaration would force every directive author to keep two sources of truth in sync. The runtime discovery loop walks the filesystem and finds populators directly.
- Backporting populator wiring to existing husky-installed repos. V0 stance applies — operators re-run `governance pack add` / `governance reset` to regenerate dispatchers via the new wrapper.
- Renaming `agent-steering-accounting`'s id now that it sits in `core` rather than the retired `agent-governance` pack. Its name is referenced from `STEERING.md` ledger rows and prior receipts; renaming would churn historical content for no signal gain.

## Verification

- `bash scripts/test-hooks-sh.sh` → ✓ 83 assertions passed (47 prior + 36 new for `generate_hooks_for_strategy`).
- `bash scripts/test.sh` → ✓ all 7 kit-internal test layers passed (`test-packctl.py`, `test-packctl-validate.py`, `test-packverb.py`, `test-install-sh.sh`, `test-hooks-sh.sh`, `test-runtime.sh`, `test-packs.sh`).
- `bash .governance/run.sh` → ✓ all 14 directives passed (`pre-commit-test-gate`, `agent-steering-accounting`, `agent-token-accounting`, `commit-issue-receipt-match`, `commit-message-format`, `doc-freshness`, `issue-templates`, `issues-tracked`, `no-broken-internal-doc-links`, `receipt-per-issue`, `repo-hygiene`, `required-docs`, `secrets-hygiene`, `workflows-hardened`).
- `grep -rn "bash .governance/run.sh" governance/references/NATIVE_TESTS.md governance/references/INIT_FLOW.md` → no remaining hand-rolled husky shim guidance.

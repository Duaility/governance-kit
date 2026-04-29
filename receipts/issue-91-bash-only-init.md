# Issue 91: Bash-Only Init; Drop Stack Classification

## Checklist

- [x] Drop stack-classification step from INIT_FLOW.md.
- [x] Drop stack-related interaction policy row, native-test scaffolding paragraph, and Stack lines in Step 8.
- [x] Reword bash-only design principle.
- [x] Drop --stack flag and stack field from install.sh manifest writer.
- [x] Drop stack field from MANIFEST_SCHEMA.md, reset eval fixture, and dogfood manifest.
- [x] Simplify governance.yml CI template to bash-only.
- [x] Reframe NATIVE_TESTS.md as post-init opt-in.
- [x] Drop --stack arg from scripts/test-packs.sh.

## What changed

Governance is a meta-layer that sits on top of the project's code. Coupling its directive suite to the project's own test runner (pytest / jest / go test / cargo test) inverts the dependency: a python repo's governance suite would go red whenever pytest itself broke.

**Drop stack-classification step from INIT_FLOW.md.** The "Classify the project stack" section was removed wholesale; init no longer asks the user to pick a primary stack from `pyproject.toml` / `package.json` / `go.mod` / `Cargo.toml` markers.

**Drop stack-related interaction policy row, native-test scaffolding paragraph, and Stack lines in Step 8.** The "Multiple plausible primary stacks exist" row was removed from the interaction policy table. Step 5's paragraph about generating per-stack native test files was replaced with a paragraph explaining why init installs only the bash runner. Step 8's `Stack detected.` summary line and the corresponding `Stack:` entry in the required-final-output list were removed.

**Reword bash-only design principle.** The principle previously labeled "Bash-first, native as enhancement" is now "Bash-only at bootstrap; native is post-init", and explains that the directive suite must not depend on the project's own toolchain. The "infer preset, stack, or hook strategy" wording in the assumptions principle was tightened to "preset or hook strategy".

**Drop --stack flag and stack field from install.sh manifest writer.** The `write_installed_manifest` helper no longer accepts `--stack` and no longer emits the `stack:` line; no consumer was reading the field.

**Drop stack field from MANIFEST_SCHEMA.md, reset eval fixture, and dogfood manifest.** The v1 schema example in `MANIFEST_SCHEMA.md` no longer carries `stack: bash`. The reset eval fixture at `governance/evals/reset/files/bootstrapped-repo/.governance/installed-packs.yaml` and this repo's own `.governance/installed-packs.yaml` were updated to match.

**Simplify governance.yml CI template to bash-only.** Both the shipped template at `governance/assets/governance.yml` and this repo's `.github/workflows/governance.yml` collapse to a single bash step plus a comment pointing at `NATIVE_TESTS.md` for users who later opt into native tests.

**Reframe NATIVE_TESTS.md as post-init opt-in.** The lead paragraph now opens with "`governance init` only installs the universal bash runner. Native test wrappers are a post-init opt-in — never scaffolded at bootstrap." A trailing note calls out the toolchain-coupling tradeoff so users pick native deliberately, not by default.

**Drop --stack arg from scripts/test-packs.sh.** The fresh-repo install contract test no longer passes `--stack bash` to `write_installed_manifest`, matching the new helper signature.

## Out of scope

No legacy-fallback path was added for v1 manifests that still carry `stack: bash` — `governance-kit` is V0 and uninstall already ignores unknown fields. No tooling was added to migrate existing repos' manifests; the field is simply dropped going forward.

## Verification

- `bash .governance/run.sh` — all 15 directives pass on the post-change tree.
- `bash scripts/test-packs.sh` — fresh-repo install contract, hook generation smoke, packverb contract, and 15 pack evals pass.
- Final stack-reference sweep (`grep -rn -i "stack" governance/ scripts/ .governance/`) returns only "application stack" (test-packs.sh comment) and "stack of PRs" (README.md), both unrelated.

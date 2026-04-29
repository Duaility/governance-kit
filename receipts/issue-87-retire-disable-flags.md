# Receipt: retire GOVERNANCE_*_DISABLE env-var sub-check toggles

Issue: [#87](https://github.com/Duaility/governance-kit/issues/87)

## Checklist

- [x] Zero references to the three flags remain
- [x] No leftover `_DISABLED` / `is_enabled` plumbing
- [x] Pack source and dogfood install are consistent
- [x] `CONSTITUTION.md` matches the pack constitution snippets
- [x] Suite passes
- [x] Evolution log carries one new entry

## What changed

Three customization surfaces existed for the rolled-up directives — `directive {modify,remove}`, line-level waivers, and `GOVERNANCE_*_DISABLE` env vars. The first two have well-defined scopes and reviewable trails; the env vars were a backdoor that let users disable a sub-check in CI with no constitution edit, no review surface, and no `git blame` entry. They predated the unified `directive` verbs (`directive remove` is the right path for "this directive doesn't apply to my repo"; `directive modify` is the right path for "this sub-check doesn't apply to my repo"). Retiring them collapses customization onto the two paths that leave a paper trail.

Removed surfaces:

- `_DISABLED=",${GOVERNANCE_*_DISABLE:-},"` and the `is_enabled() { ... }` helper in each of the three `check.sh` files (pack source under `governance/assets/packs/core/directives/<id>/` and dogfood mirror under `.governance/local/directives/<id>/`); each `if is_enabled X; then ... fi` guard unwrapped to its body.
- The env-var paragraphs in each directive's `constitution.md` (Directive intro, Rationale, Exceptions) and the `required-docs` `directive.yaml` summary line.
- The `# verify DISABLE suppresses the fail` block in `governance/assets/packs/core/directives/repo-hygiene/evals/test.sh`; the analogous blocks in the `required-docs` and `secrets-hygiene` pack evals (the `required-docs` cleanup also removed a now-redundant `cat > ARCHITECTURE.md` rewrite that only existed because the deleted DISABLE block had `rm`'d it earlier).

Updated surfaces:

- `CONSTITUTION.md` — three Directive subsections (`required-docs`, `secrets-hygiene`, `repo-hygiene`) edited in lockstep with their pack-source `constitution.md` counterparts; one evolution-log entry appended.
- `governance/references/DIRECTIVES_CATALOG.md` — three catalog rows rewritten to drop the `keys for GOVERNANCE_*_DISABLE` qualifier and add a "use `governance directive modify`" pointer.
- `governance/references/INIT_FLOW.md` — the `AGENTS.md` stub-creation step no longer references `GOVERNANCE_REQUIRED_DOCS_DISABLE` as a "skip the stub" signal (the directive is either installed or it isn't).

What stays:

- Threshold tunables (`GOVERNANCE_FRESHNESS_DAYS`, `GOVERNANCE_FILE_SIZE_LIMIT`, `GOVERNANCE_MAX_FILE_SIZE_MB`, `GOVERNANCE_AGENTS_MD_MIN/MAX/MIN_LINKS`, `GOVERNANCE_ARCHITECTURE_MIN`, `GOVERNANCE_CC_EXTRA_TYPES`) — they're parameters, not policy on/off, and they let users keep tracking the upstream `check.sh` instead of forking it.
- Line-level waivers (`# governance: allow-<id> <reason>`) — different scope from amend; per-occurrence, blameable, reason-required.
- `GOVERNANCE_KIT_HOME` — path config, not policy.
- `SKIP_GOVERNANCE` — emergency hook bypass, with CI as the backstop. Documented as a feature, not a bug.

## Out of scope

- **Migrating existing `.governance/installed-packs.yaml` manifests** in target repos. The directive ids and installed paths are unchanged; only the script bodies and the constitution snippets shipped by `directive install`/`pack update` change. A `governance pack update` will pick up the new shape.
- **Adding a deprecation alias** that prints a one-time warning when the old env vars are set. Pre-1.0 removal per the V0 stance — the silently-bypassed-sub-check failure mode is exactly what the change is meant to surface, and a warning in the same channel is easy to miss in CI logs.
- **Rewriting historical receipts or evolution-log entries** that mention the retired flags by name. They describe what was true at the time, per the project's append-only ledger convention.
- **Auditing third-party packs** (anything outside the `core` pack at `governance/assets/packs/core/`) for similar env-var backdoors. Community packs author their own customization surfaces; the catalog is not part of this change.
- **Updating user CI configs** that currently set one of the three flags. After this lands, those env-vars become inert; users will start seeing the sub-check enforced and can either amend the directive or remove it.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Zero references to the three flags remain.** `grep -rn 'GOVERNANCE_\(REPO_HYGIENE_DISABLE\|REQUIRED_DOCS_DISABLE\|SECRETS_HYGIENE_DISABLE\)' tests/ extensions/ governance/ CONSTITUTION.md` returns nothing.
2. **No leftover `_DISABLED` / `is_enabled` plumbing.** `grep -n '_DISABLED\|is_enabled' .governance/local/directives/{repo-hygiene,required-docs,secrets-hygiene}/check.sh governance/assets/packs/core/directives/{repo-hygiene,required-docs,secrets-hygiene}/check.sh` returns nothing.
3. **Pack source and dogfood install are consistent.** `diff -q .governance/local/directives/<id>/<file> governance/assets/packs/core/directives/<id>/<file>` returns no differences for `check.sh`, `constitution.md`, and `directive.yaml` across the three directives — except the pre-existing extra exclude line in `secrets-hygiene/check.sh` (the pack copy ignores `extensions/packs/*/directives/*/evals/**`, the dogfood doesn't).
4. **`CONSTITUTION.md` matches the pack constitution snippets.** The three Directive subsections in the constitution use the same Directive / Rationale / Exceptions wording as the corresponding `governance/assets/packs/core/directives/<id>/constitution.md` files.
5. **Suite passes.** `bash .governance/run.sh` reports `all 15 directive(s) passed`. `bash scripts/test-packs.sh` reports `2 pack(s), 15 directive(s), 15 eval(s) passed`.
6. **Evolution log carries one new entry.** `CONSTITUTION.md` has a 2026-04-29 entry naming the three directives and pointing at `directive {modify,remove}` and waivers as the surviving customization paths.
7. **This commit satisfies `commit-issue-receipt-match`.** The commit's `(#87)` anchor matches the `issue-87` token on this receipt file.

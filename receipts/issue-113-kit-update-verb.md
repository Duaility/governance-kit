# issue-113 — kit update verb

Closes [#113](https://github.com/Duaility/governance-kit/issues/113). Also
closes the run-time gap from [#118](https://github.com/Duaility/governance-kit/issues/118)
where post-clone / CI lacked an entry point that materialized gh-source pack
trees before `.governance/run.sh` walked them.

## Checklist

- [x] Verb scaffolding
- [x] Manifest schema — `kit_version` field
- [x] Init records `kit_version`
- [x] Marker stamping on runtime templates + dogfood mirrors
- [x] Eval fixtures and `evals.json`
- [x] Reconcile wired into CI workflow + setup-clone
- [x] Dogfood `install.yaml` records its kit version
- [x] Tests

## What changed

- **Verb scaffolding.** New file [governance/references/UPDATE_FLOW.md](../governance/references/UPDATE_FLOW.md) — authoritative 8-step flow for `governance kit update`. Per-file diff-before-exec, line-2 marker ownership check, no silent downgrades, optional `--with-packs` to chain `pack update` for every gh entry. Modeled after [RESET_FLOW.md](../governance/references/RESET_FLOW.md). Surfaced in the verb table + dispatch routing in [governance/SKILL.md](../governance/SKILL.md), and per-verb reference entry in [governance/references/VERBS.md](../governance/references/VERBS.md).
- **Manifest schema — `kit_version` field.** Added the `kit_version` field to `.governance/install.yaml` v3 — optional within v3 (back-compat: missing = pre-tracking install, the verb offers to record on first run). Documented in [INSTALL_SCHEMA.md](../governance/references/INSTALL_SCHEMA.md) with a new "Fields kit update relies on" section. The `write_installed_manifest` helper in [governance/assets/packs/lib/install.sh](../governance/assets/packs/lib/install.sh) accepts `--kit-version` and emits `kit_version: "<v>"` when set; field omitted otherwise.
- **Init records `kit_version`.** Updated [INIT_FLOW.md](../governance/references/INIT_FLOW.md) Step 3 — `governance init` now resolves `KIT_VERSION` via `packctl.py kit-version` and passes `--kit-version` to `write_installed_manifest`, so future `kit update` runs can detect the version delta.
- **Marker stamping on runtime templates + dogfood mirrors.** Stamped `# governance-kit:managed` into the four runtime templates ([governance/assets/dot-governance/run.sh](../governance/assets/dot-governance/run.sh), [lib.sh](../governance/assets/dot-governance/lib.sh), [governance/assets/setup-clone.sh](../governance/assets/enable-governance.sh), [governance/assets/governance.yml](../governance/assets/governance.yml)) and their dogfood-installed copies ([.governance/run.sh](../.governance/run.sh), [.governance/lib.sh](../.governance/lib.sh), [scripts/setup-clone.sh](../scripts/enable-governance.sh), [.github/workflows/governance.yml](../.github/workflows/governance.yml)). Marker on line 2 (after shebang) for shell scripts; line 1 for YAML. UPDATE_FLOW.md docs the "first-3-lines" detection rule and explicit pre-marker handling (no auto-stamp; user opts in via `overwrite-with-backup`).
- **Eval fixtures and `evals.json`.** New eval surface under [governance/evals/kit-update/](../governance/evals/kit-update/) — `evals.json` with 5 cases (30 assertions) covering forward update, no-op short-circuit, missing-manifest refusal, no-downgrade refusal, and pre-tracking-install opt-in. Five fixtures (`stale-repo/`, `up-to-date-repo/`, `no-manifest-repo/`, `future-kit-repo/`, `pre-tracking-repo/`) each minimal bootstrapped repos with the right install.yaml shape to drive the relevant Step-2 branch. Fixture README documents which fixture exercises which branching point.
- **Reconcile wired into CI workflow + setup-clone.** Closes the gap from #118 where the gh-source pack trees were gitignored but no entry point materialized them on clone or in CI. Added `astral-sh/setup-uv` + a `bash governance/assets/packs/lib/reconcile.sh "$PWD"` step before the runner in [.github/workflows/governance.yml](../.github/workflows/governance.yml). Same reconcile call appended to [scripts/setup-clone.sh](../scripts/enable-governance.sh) so fresh clones populate gh-source packs after the hooks-path step. Verified by simulating a clean clone (`rm -rf .governance/packs/governance-kit/ && bash scripts/setup-clone.sh`) — the `governance-kit/core` tree rebuilds via the working-tree resolver and `bash .governance/run.sh` goes from 1 directive to 14.
- **Dogfood `install.yaml` records its kit version.** Added `kit_version: "0.2"` to [.governance/install.yaml](../.governance/install.yaml) so the dogfood reflects the new schema field rather than acting as a perpetual pre-tracking install.
- **Tests.** Two new assertions in [scripts/test-install-sh.sh](../scripts/test-install-sh.sh) — `kit_version` absent on the minimum-flag invocation, `kit_version: "0.2"` emitted under `--kit-version 0.2`. Total install.sh assertions: 55 → 57.

## Out of scope

- Implementing `kit update` end-to-end as a runnable command. The verb is agent-orchestrated like every other verb in this codebase (`init`, `reset`, `pack add`) — the flow doc tells an agent how to execute and existing helpers (`generate_hooks_for_strategy`, `write_installed_manifest`, the `pack update` chain) do the writes. No new monolithic shell script.
- Auto-stamping markers into pre-marker repos. The verb deliberately surfaces unmarked files as `Skipped (unmanaged)` and asks per-file — silently overwriting hand-edited copies would be the exact failure mode the marker discipline exists to prevent.
- Changing `pack update`'s scope. `kit update` is disjoint from `pack update`. Combined runs are explicit via `kit update --with-packs`.
- Implementing the `--allow-downgrade` flag mentioned in UPDATE_FLOW.md. Not needed for v1; the no-downgrade refusal is the right default and the escape hatch is "upgrade the kit on PATH".
- Modifying `.governance/run.sh` to call reconcile inline. The runner stays shell-only and packverb-free for consumers without the kit installed locally — reconcile is invoked from `setup-clone.sh` (post-clone) and `governance.yml` (CI) instead.

## Verification

- `bash .governance/run.sh` → ✓ all 14 directives passed (`pre-commit-test-gate`, `agent-steering-accounting`, `agent-token-accounting`, `commit-issue-receipt-match`, `commit-message-format`, `doc-freshness`, `issue-templates`, `issues-tracked`, `no-broken-internal-doc-links`, `receipt-per-issue`, `repo-hygiene`, `required-docs`, `secrets-hygiene`, `workflows-hardened`).
- `bash scripts/test.sh` → ✓ all kit-internal test layers passed (`test-packctl`, `test-packctl-validate`, `test-packverb`, `test-install-sh` 57/57, `test-hooks-sh`, `test-runtime`, `test-packs`: 1 pack, 14 directives, 14 evals).
- `bash scripts/eval-report.sh` → picks up `kit-update | ready | 5 cases | 30 assertions | 0 missing | 0 placeholder`. Skill-wide totals 34 cases / 233 assertions.
- Clean-clone simulation: `rm -rf .governance/packs/governance-kit/ && bash scripts/setup-clone.sh && bash .governance/run.sh` → reconcile materializes 13 directives from the working-tree resolver; runner reports `all 14 directive(s) passed`.

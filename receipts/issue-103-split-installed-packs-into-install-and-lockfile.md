# issue-103 — split `installed-packs.yaml` into `install.yaml` + `packs.lock`

Closes [#103](https://github.com/Duaility/governance-kit/issues/103).

## Checklist

- [x] Lockfile schema bumped to v2
- [x] Install manifest schema bumped to v3
- [x] Required-docs reader follows the rename
- [x] Test scripts updated
- [x] Reset eval fixture reshaped
- [x] Dogfood files reshaped
- [x] Docs split + updated
- [x] test-schema-split.sh end-to-end

## What changed

- **Lockfile schema bumped to v2.** `governance/assets/packs/lib/packverb.py` now records `version`, `source` (one of `builtin` / `gh` / `local`), and `directives` on every entry. `gh` entries additionally carry `ref` / `sha` / `subpath` / `min_governance_kit` / `installed_at`; `builtin` and `local` entries drop those fields entirely (no upstream pin). `lock-add` rewires to all-keyword args (`--source {builtin|gh|local} --version <v> [--ref --sha --subpath --min-kit] --directive ...`); validates that `gh` requires `--ref`/`--sha` and that `builtin`/`local` reject them. `lock-list --long` adds `id\tsource\tversion\tsha\tref` columns; the default 3-column form is preserved for callers that consume `<id>\t<sha>\t<ref>`. `governance-kit/core` is now recorded in the lockfile (previously absent — its directives were owned by the install manifest), so `reset` can restore it on the same path it restores community packs. Repo-local packs appear with `source: local` so reset's hand-authored set is computed by walking the lockfile rather than diffing two files.
- **Install manifest schema bumped to v3, renamed `installed-packs.yaml` → `install.yaml`.** `governance/assets/packs/lib/install.sh::write_installed_manifest` drops the entire `packs[]` block (moved to packs.lock) and rejects positional `<pack_dir> <directive>` pairs. The function now writes only the init receipt: `owner`, `repo`, `hook_strategy`, `constitution`, `ci_workflow`, `tests_dir`, `agents_md_*`, `setup_clone_script`, `install_assets_seeded`, `collisions`, optional `path_b`. Output path is `.governance/install.yaml`. The rename is honest about scope — after the split there are zero packs in the file.
- **Required-docs reader follows the rename.** `governance/assets/packs/core/directives/required-docs/check.sh` reads `hook_strategy` from `.governance/install.yaml` (source pack), and the dogfood install copy at `.governance/packs/governance-kit/core/directives/required-docs/check.sh` mirrors the change.
- **Test scripts updated.** `scripts/test-install-sh.sh` rewrites the writer matrix for v3 (no packs[], rejects positional pairs); `scripts/test-packverb.py` exercises the new lock-add CLI for all three source kinds, the source/ref/sha validation paths, and the `--long` listing format; `scripts/test-packs.sh` drives the fresh-install contract by calling `packverb lock-add` to record `governance-kit/core` with `source: builtin` after `install_directive_folder` runs, and asserts both `install.yaml` and `packs.lock` exist post-install. New `scripts/test-schema-split.sh` end-to-end (26 assertions) covers the cross-file invariants: install.yaml v3 with no packs[] block, packs.lock v2 with all three source kinds, source-specific field presence/absence, lock-list --long column format, lock-remove preserves siblings, and v1 lockfile rejection (no migration shim). Wired into `scripts/test.sh` between the runtime layer and the pack smoke layer.
- **Reset eval fixture reshaped.** `governance/evals/reset/files/bootstrapped-repo/.governance/installed-packs.yaml` renamed to `install.yaml` with the `packs:` block stripped; new sibling `packs.lock` carries the one-pack `acme/bootstrapped-repo` entry as `source: local`. `governance/evals/reset/evals.json` updates the eval-1 expected_output and assertions to mention both files.
- **Dogfood files reshaped.** `.governance/installed-packs.yaml` → `.governance/install.yaml` (packs[] dropped). New `.governance/packs.lock` records `governance-kit/core` (source=builtin, version 0.2, all 13 installed directives) and `duaility/governance-kit` (source=local, version 0.1, 1 directive — `pre-commit-test-gate`).
- **Docs split + updated.** `governance/references/MANIFEST_SCHEMA.md` deleted; replaced by `INSTALL_SCHEMA.md` (init receipt: shape, fields uninstall reads, fields reset reads, legacy fallback, AGENTS.md heuristic) and `LOCK_SCHEMA.md` (pin record: source discriminator table, field reference, packverb CLI). `PACK_VERBS.md`, `RESET_FLOW.md`, `UNINSTALL_FLOW.md`, `UNINSTALL_MATRIX.md`, `INIT_FLOW.md`, `DIRECTIVE_VERBS.md`, `VERBS.md`, `AUTHORING_PACKS.md`, plus root `AGENTS.md` / `ARCHITECTURE.md` / `governance/SKILL.md` / `governance/evals/reset/files/README.md` updated end-to-end to reference the new file pair, the new schema versions (`install.yaml` v3, `packs.lock` v2), and the new lock-add CLI.

## Out of scope

- **No migration shim.** V0 stance — repos carrying the old `installed-packs.yaml` (v2) or `packs.lock` (v1) re-run `governance init`. The legacy-fallback path in `INSTALL_SCHEMA.md` documents how `uninstall` still works on older shapes (heuristic detection + a one-line warning), but `reset` refuses on a version mismatch and routes to uninstall+init.
- **`pack list` switching to long-format-only.** The default `lock-list <lockfile>` still emits 3 columns (`<id>\t<sha>\t<ref>`) for backward compat; the new `--long` flag opts into the 5-column form. Switching the default would churn external consumers we don't control.
- **A pack-version field on lockfile entries that diverges from `pack.yaml::version`.** The lockfile copies the value from the pack's `pack.yaml` at install time. If a community pack ships a new `version: "0.4"` on the same SHA (without bumping the SHA), `pack update` will pick it up. Tracking version separately from SHA-driven drift is not a concern at V0.
- **Renaming the file pair to `governance.lock` / similar.** The chosen names (`packs.lock`, `install.yaml`) are honest about contents — the lockfile is exactly what npm/cargo/poetry call a lockfile; the install.yaml is exactly the init receipt with no packs[] in it. A "governance.lock" name would mix install config with pin state in one file, which is the shape we just escaped.
- **Recording pre-existing repos' lockfiles automatically.** A repo that initted under v2 and never re-runs init will still have `installed-packs.yaml`. CI re-enforces every directive on every PR; there is no developer-side bypass — operators noticing `reset` failures take the documented uninstall+init path.

## Verification

- `bash scripts/test.sh` → ✓ all 7 kit-internal test layers passed (test-packctl.py, test-packctl-validate.py, test-packverb.py, test-install-sh.sh, test-hooks-sh.sh, test-runtime.sh, test-schema-split.sh, test-packs.sh).
- `bash scripts/test-schema-split.sh` → ✓ 26 assertions passed (install.yaml v3 shape; packs.lock v2 shape with builtin/gh/local entries; lock-list --long columns; lock-remove preserves siblings; v1 lockfile rejected).
- `bash scripts/test-install-sh.sh` → ✓ 55 assertions passed (writer emits install.yaml not installed-packs.yaml; version "3"; no packs: block; rejects positional pack/directive pairs).
- `uv run python scripts/test-packverb.py` → ✓ 28 tests passed (load_lockfile defaults to v2; lock-add for all three sources; lock-add validation rejects bad combinations; lock-list --long format; sort-on-write).
- `bash .governance/run.sh` → ✓ all 14 directives passed against the renamed/reshaped dogfood files.
- `grep -rln "installed-packs.yaml" --include="*.md" --include="*.sh" --include="*.py" governance/ AGENTS.md ARCHITECTURE.md scripts/` → only the negative-path assertion in test-install-sh.sh remains (intentional — proves the writer no longer emits the old name) and INSTALL_SCHEMA.md's legacy-fallback section (intentional — documents the rename history).

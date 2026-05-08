# issue-122 — unify managed-file marker format with kit-version pin

Closes [#122](https://github.com/Duaility/governance-kit/issues/122).

The kit-owned files in a target repo previously carried two different
marker forms: runtime templates carried the bare
`# governance-kit:managed`, while hook dispatchers carried the richer
`# governance-kit:managed pack-version=<v> generated=<date>`. The
asymmetry was the root cause of `kit update` being a hard failure on
missing `install.yaml` — the manifest was the only place the version
pin lived. This change unifies the marker on every kit-owned file and
demotes `install.yaml.kit_version` to a cache reconstructable from
per-file markers.

## Checklist

- [x] Add `stamp_managed_marker` and `read_marker_kit_version` helpers in `governance/assets/packs/lib/install.sh`
- [x] Rename `pack-version=` to `kit-version=` in `governance/assets/packs/lib/hooks.sh` (`_write_marker`)
- [x] Update `UPDATE_FLOW.md` interaction policy + Step 1 to reconstruct the pin from per-file markers when `install.yaml` is missing
- [x] Update `UPDATE_FLOW.md` Step 3 to describe the unified marker shape and per-file `kit-version=` reads
- [x] Update `UPDATE_FLOW.md` Step 5 to call `stamp_managed_marker` after copy
- [x] Update `UPDATE_FLOW.md` key design principles to reframe "manifest-driven" as "marker is the pin; manifest is a cache"
- [x] Update `INIT_FLOW.md` Steps 5/6/7 to stamp on copy and update the hook marker example
- [x] Update `INSTALL_SCHEMA.md` to flag `kit_version` as a cache reconstructable from markers
- [x] Update `VERBS.md` to soften `kit update` precondition
- [x] Update `UNINSTALL_FLOW.md`, `UNINSTALL_MATRIX.md`, `AUTHORING_PACKS.md` hook marker examples
- [x] Update `scripts/test-hooks-sh.sh` assertions for `kit-version=`
- [x] Add unit tests for the new helpers in `scripts/test-install-sh.sh`
- [x] Re-stamp every dogfood file (`.governance/run.sh`, `.governance/lib.sh`, `.github/workflows/governance.yml`, `scripts/setup-clone.sh`, `.githooks/*`)
- [x] Update kit-update eval case 3 (no-manifest-repo) to assert reconstruction-then-refuse
- [x] Add kit-update eval case 6 + `reconstructable-repo/` fixture for the reconstruction-then-proceed path
- [x] Update `governance/evals/kit-update/files/README.md` to reflect the 6-fixture set

## What changed

- **Add `stamp_managed_marker` and `read_marker_kit_version` helpers in `governance/assets/packs/lib/install.sh`.** New idempotent helper that scans the first 3 lines of a kit-owned file for `# governance-kit:managed` and rewrites it to the versioned form `# governance-kit:managed kit-version=<v> generated=<YYYY-MM-DD>`. Works for both shebang scripts (line 2) and YAML (line 1). `read_marker_kit_version` extracts the `kit-version=<v>` token, returning empty for bare markers (pre-versioning) and exit-non-zero for unmarked files. See [governance/assets/packs/lib/install.sh](../governance/assets/packs/lib/install.sh).
- **Rename `pack-version=` to `kit-version=` in `governance/assets/packs/lib/hooks.sh` (`_write_marker`).** The hook-dispatcher generator is part of the kit, not any individual pack — `pack-version=` was a misnomer. The rename makes hook markers and runtime-template markers share one shape so `kit update` reads a single token from every kit-owned file. See [governance/assets/packs/lib/hooks.sh](../governance/assets/packs/lib/hooks.sh).
- **Update `UPDATE_FLOW.md` interaction policy + Step 1 to reconstruct the pin from per-file markers when `install.yaml` is missing.** The verb now scans `run.sh`, `lib.sh`, `governance.yml`, `setup-clone.sh`, and the hook dispatcher for `kit-version=<v>`, takes the min, and proceeds — only refusing when neither the manifest nor any versioned marker is found. See [governance/references/UPDATE_FLOW.md](../governance/references/UPDATE_FLOW.md).
- **Update `UPDATE_FLOW.md` Step 3 to describe the unified marker shape and per-file `kit-version=` reads.** Three sub-cases by what the marker scan finds: versioned → compare `<v>` to new `KIT_VERSION` (equal=skip, older=re-stamp+diff); bare → version-unknown but kit-owned, apply forward; absent → user-owned, surface as `Skipped (unmanaged)`.
- **Update `UPDATE_FLOW.md` Step 5 to call `stamp_managed_marker` after copy.** Each rewritten runtime file is re-stamped with the new `kit-version=` and today's date in place.
- **Update `UPDATE_FLOW.md` key design principles to reframe "manifest-driven" as "marker is the pin; manifest is a cache".** The principle now reads "Marker is the version pin; manifest is a cache" — every kit-owned file carries a `kit-version=<v>` marker; `install.yaml.kit_version` mirrors it; manifest absence is recoverable as long as any versioned marker survives.
- **Update `INIT_FLOW.md` Steps 5/6/7 to stamp on copy and update the hook marker example.** Init now invokes `stamp_managed_marker` after copying `run.sh`, `lib.sh`, `setup-clone.sh`, and `governance.yml`. Step 6's hook marker example shows `kit-version=<v>` instead of `pack-version=<v>`.
- **Update `INSTALL_SCHEMA.md` to flag `kit_version` as a cache reconstructable from markers.** Documented the new contract in the field description, the "Fields kit update relies on" table, and the "When the manifest is missing entirely" section — `kit update` is now conditionally legitimate without the manifest.
- **Update `VERBS.md` to soften `kit update` precondition.** Precondition now reads "reads the version pin from `install.yaml.kit_version`; if the manifest is missing or the field is absent, scans per-file `kit-version=` markers and takes the min."
- **Update `UNINSTALL_FLOW.md`, `UNINSTALL_MATRIX.md`, `AUTHORING_PACKS.md` hook marker examples.** All three docs reflect the unified `kit-version=<v>` form on hook dispatchers.
- **Update `scripts/test-hooks-sh.sh` assertions for `kit-version=`.** Three replacements (`pack-version=test-version`, `pack-version=v2`, `pack-version=v-regen`) plus the inline marker fixtures (`# governance-kit:managed pack-version=test ...`). Suite passes 83/83.
- **Add unit tests for the new helpers in `scripts/test-install-sh.sh`.** 11 new assertions cover round-trip stamping, idempotency, YAML vs shebang line detection, bare-marker reads returning empty, missing-file errors, and refusal when the marker sits past line 3. Suite goes 57 → 68.
- **Re-stamp every dogfood file (`.governance/run.sh`, `.governance/lib.sh`, `.github/workflows/governance.yml`, `scripts/setup-clone.sh`, `.githooks/*`).** All eight files now carry `# governance-kit:managed kit-version=0.2 generated=2026-05-08`. The dogfood passes governance: all 14 directives pass.
- **Update kit-update eval case 3 (no-manifest-repo) to assert reconstruction-then-refuse.** The `expected_output` and assertions in [governance/evals/kit-update/evals.json](../governance/evals/kit-update/evals.json) now require the skill to *attempt* marker reconstruction before refusing — outcome unchanged (refuse), reasoning updated.
- **Add kit-update eval case 6 + `reconstructable-repo/` fixture for the reconstruction-then-proceed path.** New fixture at [governance/evals/kit-update/files/reconstructable-repo/README.md](../governance/evals/kit-update/files/reconstructable-repo/README.md) — `install.yaml` deleted; `run.sh`/`lib.sh` carry `kit-version=0.1` markers; eval expects the skill to reconstruct the pin, run the forward-update flow, write a fresh manifest, and commit. 9 assertions covering attempt-before-prompt, scan scope, min-version semantics, normal forward-flow discipline, re-stamping, fresh manifest population, commit subject, assumptions surfacing, and explicit non-routing to uninstall+init.
- **Update `governance/evals/kit-update/files/README.md` to reflect the 6-fixture set.** New row for `reconstructable-repo/`, new `Markers` column distinguishing bare / versioned / none, and a paragraph explaining the marker-as-source-of-truth contract.

## Out of scope

- Implementing semver-aware `min()` for the reconstructed pin in code. UPDATE_FLOW.md prescribes "take the min (semver-aware)"; the agent executes that ordering at runtime against the scanned `kit-version=` set. No helper is added because a future kit may grow a richer `KIT_VERSION` shape.
- Stamping the kit's own in-tree templates at `governance/assets/dot-governance/`. Those carry the bare `# governance-kit:managed` form on disk by design — the stamp happens at install/update time. A consumer who reads the source-tree template directly should see a valid template, not a mid-stamp placeholder.
- Auto-promoting bare-marker files to versioned form during `kit update` without user confirmation. The diff-before-exec contract still applies — the version line changing is part of the diff the user accepts.
- Migrating the eval fixtures themselves to versioned markers. The bare-marker fixtures (`stale-repo/`, `up-to-date-repo/`, `future-kit-repo/`, `no-manifest-repo/`) deliberately exercise the bare-marker path, which remains a real production case for repos init'd before this change. Only the new `reconstructable-repo/` carries versioned markers.
- A historical-templates checksum table (option #3 from the original design discussion) for auto-promoting unedited pre-marker installs to managed status. Out of scope for this issue; tracked separately if the cliff turns out to bite real users.

## Verification

- `bash .governance/run.sh` → ✓ all 14 directive(s) passed.
- `bash scripts/test.sh` → ✓ all kit-internal test layers passed (`test-install-sh` 68/68, `test-hooks-sh` 83/83, `test-packs` 1/14/14).
- `python3 -c 'import json; json.load(open("governance/evals/kit-update/evals.json"))'` → 6 cases, ids `[1, 2, 3, 4, 5, 6]`.
- New helper round-trip: `stamp_managed_marker` followed by `read_marker_kit_version` returns the version that was just written; re-stamping with a different version updates the field in place; bare markers read empty; missing markers exit non-zero; markers past line 3 are refused. All 11 new assertions in `test-install-sh.sh` pass.
- Hook generator emits the new form: regenerating dispatchers under any strategy (`githooks` / `husky` / `pre-commit`) carries `kit-version=<v>` on line 2, and re-running with a different version updates the field. Verified by `test-hooks-sh.sh` 83/83.
- Dogfood files carry the new form on line 1 (YAML) or line 2 (shebang scripts): `.governance/run.sh`, `.governance/lib.sh`, `.github/workflows/governance.yml`, `scripts/setup-clone.sh`, and `.githooks/{pre-commit,commit-msg,prepare-commit-msg,post-commit,pre-push}` all show `# governance-kit:managed kit-version=0.2 generated=2026-05-08`.
- Reconstructable-repo fixture is well-formed: `find governance/evals/kit-update/files/reconstructable-repo -type f` lists the 9 expected files (constitution, README, run.sh, lib.sh, packs.lock, pack.yaml, directive.yaml, constitution.md, check.sh), with `run.sh` and `check.sh` executable and both runtime stubs carrying `kit-version=0.1` markers.

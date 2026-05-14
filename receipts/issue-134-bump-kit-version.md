# issue-134 — bump kit version 0.2 → 0.3

Closes [#134](https://github.com/Duaility/governance-kit/issues/134).

`KIT_VERSION` has been pinned at `0.2` since the 2026-04-29 fold of `duaility/agent-governance` into `governance-kit/core`. Since then the kit has shipped `kit update`, bootstrap-recovery, the unified `kit-version=` marker format, the install/lock schema split, and several other feat changes. A fresh `governance init` today still stamps `kit_version: "0.2"` into the new repo's manifest, which understates the runtime that's actually being installed. This bumps the constant to `0.3` and re-stamps everything in the dogfood that carries the pin.

## Checklist

- [x] Bump `KIT_VERSION` to `0.3` in `packctl.py`
- [x] Bump bundled `governance-kit/core` pack pin to `0.3`
- [x] Bump dogfood pack pins and `install.yaml`
- [x] Re-stamp 9 managed-file markers
- [x] Realign `kit-update` eval fixtures
- [x] Bump `INSTALL_SCHEMA.md` example
- [x] Dogfood `bash .governance/run.sh` clean

## What changed

- **Bump `KIT_VERSION` to `0.3` in `packctl.py`.** [governance/assets/packs/lib/packctl.py](../governance/assets/packs/lib/packctl.py) is the single source of truth read by every verb that has to decide what the kit on PATH reports. Pack manifests with `min_governance_kit > KIT_VERSION` are rejected; the version-tuple comparison is unchanged.
- **Bump bundled `governance-kit/core` pack pin to `0.3`.** Both `version` and `min_governance_kit` move together in [packs/core/pack.yaml](../packs/core/pack.yaml) — the kit's own core pack matches the kit's own constant, the same pattern used at the 0.1 → 0.2 cut. Community packs that pinned `min_governance_kit: "0.2"` still resolve cleanly (0.2 ≤ 0.3).
- **Bump dogfood pack pins and `install.yaml`.** [.governance/install.yaml](../.governance/install.yaml) stamps `kit_version: "0.3"`; [.governance/packs/duaility/governance-kit/pack.yaml](../.governance/packs/duaility/governance-kit/pack.yaml) bumps its `min_governance_kit` to `"0.3"` (its own `version: "0.1"` is separate from the kit version and is not touched). The runtime-materialized `.governance/packs/governance-kit/core/pack.yaml` is gitignored but was kept consistent locally.
- **Re-stamp 9 managed-file markers** on the kit-owned files in this repo's tree. `.governance/run.sh`, `.governance/lib.sh`, `.github/workflows/governance.yml`, `scripts/enable-governance.sh`, and `.githooks/{commit-msg,post-commit,pre-commit,pre-push,prepare-commit-msg}` now all carry `# governance-kit:managed kit-version=0.3 generated=2026-05-14` on line 1 (YAML) or line 2 (shebang scripts). Marker-reconstruction in `kit update` would now read `0.3` from every file, matching `install.yaml`.
- **Realign `kit-update` eval fixtures.** [up-to-date-repo/.governance/install.yaml](../governance/evals/kit-update/files/up-to-date-repo/.governance/install.yaml) moves to `kit_version: "0.3"` (this fixture is semantically "matches the kit on PATH"). [files/README.md](../governance/evals/kit-update/files/README.md) updates the KIT_VERSION sentence + the `up-to-date-repo/` table row. [evals.json](../governance/evals/kit-update/evals.json) cases 2, 4, and 6 rewrite the four `"0.2"` narrative mentions that referred to the kit-on-PATH's reported version. The `stale-repo/` (`0.1`), `future-kit-repo/` (`9.9`), and `reconstructable-repo/` (markers at `0.1`) fixtures are left alone — their semantics (older / future / pre-update) survive the bump.
- **Bump `INSTALL_SCHEMA.md` example.** [governance/references/INSTALL_SCHEMA.md:16](../governance/references/INSTALL_SCHEMA.md) bumps the illustrative `kit_version: "0.2"` in the v3 manifest example to `"0.3"` so the schema sample reflects what a fresh `governance init` will now write.

## Out of scope

- **Parametric `"0.2"` literals in tests** — `scripts/test-install-sh.sh:301,319` (passes `--kit-version 0.2` to test flag passthrough), `scripts/test-schema-split.sh:93,94,117,143,145` (uses `0.2` as a fixture pack version in lock-add assertions), `scripts/test-packverb.py:62,103,442,449` (fixture `min_governance_kit: "0.2"`, still ≤ KIT_VERSION so the validator still accepts), and `scripts/test-packctl.py` (version-parser unit tests using `"0.2"` as a comparison literal). None of these are tied to the KIT_VERSION constant.
- **`PACK_VERBS.md` / `LOCK_SCHEMA.md` lockfile examples** where two packs intentionally show different versions (`0.2` core + `0.3` community pack) — the example would lose its point if both were unified.
- **Eval fixtures under `governance/evals/{pack,directive,reset,uninstall,init}/files/**`** that bundle a `governance-kit/core` pack at `version: "0.2"` inside a target repo. They now represent "target repo has a stale core pack installed", which is a valid fixture state for the verbs they back (pack add/update, directive add/modify, reset, uninstall).
- **`CONSTITUTION.md` evolution-log entries, `receipts/*`, `plans/*`** — these are historical records and describe what was true at the time. Rewriting them would falsify the audit trail.

## Verification

- Dogfood `bash .governance/run.sh` clean — all 14 directives pass on the working tree.

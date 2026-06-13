# issue-253 — offline managed-tree-integrity directive replaces kit-version-sync

Closes [#253](https://github.com/Duaility/governance-kit/issues/253).

## Checklist

- [x] Shared digestlib + apply-engine digest recording (all paths)
- [x] managed-tree-integrity directive + evals (match, marker, modified, deleted, orphan, runtime, legacy, waiver)
- [x] kit-version-sync removed; Lane-2 dogfood-smoke removed
- [x] Schema docs, catalog, AGENTS, README updated
- [x] Suite green

## What changed

- **Shared digestlib + apply-engine digest recording (all paths).** New `kit/assets/packs/lib/digestlib.py` is the single source of how a managed unit is hashed (`file_digest`, `directory_digest` over git-relevant files excluding `evals/`/`install-assets/`/`__pycache__`/`*.pyc`; `managed_runtime_files`/`managed_digests` for runtime files; `write_managed_digests_block` for the manifest). Every materializer records digests through it: `packapply.py` writes a per-directive `digest:` map into each lock entry and re-stamps runtime `managed_digests` in `_finish` (covering add/update/remove, after hook regen); `initapply.py` writes both at init; `kitapply.py` re-stamps runtime `managed_digests` after a `kit update`. `install.sh`'s `copy_tree_without_evals` now also prunes any stray `__pycache__`/`*.pyc` so bytecode is never vendored.
- **managed-tree-integrity directive + evals (match, marker, modified, deleted, orphan, runtime, legacy, waiver).** New bundled directive `packs/foundation/directives/managed-tree-integrity/` (in the `minimal` preset): `check.sh` → stdlib `lib/integrity.py` recomputes each recorded digest on disk and compares — for vendored directive folders (`packs.lock` `digest:`) and kit-runtime files (`install.yaml` `managed_digests:`), plus a marker-vs-manifest `kit_version` check that **subsumes the former kit-version-sync** (a hand-edited manifest version leaves files matching their digests, so the marker check is still needed). Works offline in any repo — it compares recorded digests, not upstream git objects, which is what `consumed-tree-integrity` structurally could not do. A missing `digest`/`managed_digests` is skipped (back-compat). The digest routine is a byte-identical copy of `digestlib`, pinned by `scripts/test-digestlib.py`; the eval drives all listed cases.
- **kit-version-sync removed; Lane-2 dogfood-smoke removed.** Deleted `packs/foundation/directives/kit-version-sync/` (subsumed) and dropped it from the `standard` preset; `managed-tree-integrity` joins `minimal`. Deleted `scripts/dogfood-smoke.sh` and `.github/workflows/dogfood-smoke.yml` (Lane 2) — the directive's own evals give the same HEAD signal. The three kit-author checks from item B plus this directive's eval and `test-digestlib.py` are the test coverage; `governance.yml`'s stale Lane-2 comment was updated.
- **Schema docs, catalog, AGENTS, README updated.** `LOCK_SCHEMA.md` (+`digest`), `INSTALL_SCHEMA.md` (+`managed_digests`), `DIRECTIVES_CATALOG.md` + `docs/reference/directive-catalog.mdx` (swap the row + presets), `docs/concepts/versioning.mdx` / `VERSIONING.md` / `RELEASE_FLOW.md` / `INIT_FLOW.md` / `ARCHITECTURE.md` (kit-version-sync → managed-tree-integrity / the `test-kit-version-consistency` layer where the axis-floor was meant), and `AGENTS.md` (the "two-lane dogfood" section rewritten as "a protected consumer" — Lane 1/Lane 2 framing dissolved). README: Proof bullets, bundled-pack + directive tables, dogfood-smoke badge removed, the version-drift note repointed.
- **Suite green.** Both the kit umbrella and the dogfood suite pass; `digestlib` parity and the directive eval are wired into `scripts/test.sh`.

## Out of scope

- Retiring `consumed-tree-integrity` (work item C, post-release) — kept this PR so the dogfood's vendored tree stays guarded until `managed-tree-integrity` reaches it at the next foundation release + `pack update` (the accepted one-release lag). No part of this PR touches `.governance/`.
- Moving the three author-checks to test layers (work item B, #251, already on this branch).
- Genericizing the illustrative `pre-commit-test-gate` lock-shape samples (noted in #251).

## Decisions

- **One digest per directive folder, not per file.** A single `sha256` over the folder names the drifted *directive* (the same-commit diff shows the exact file); it keeps the lock schema and the directive's stdlib parser simple — no nested-map YAML parsing, the riskiest part avoided.
- **Folded the kit-version-marker check into the directive.** A pure content-digest check is *not* a strict superset of kit-version-sync: a hand-edited manifest `kit_version` leaves every file matching its recorded digest. Adding the marker-vs-manifest assertion makes the removal of kit-version-sync honest (no lost coverage) — caught in review before claiming "subsumed".
- **All digest work in Python; `install.sh` left almost untouched.** The engines build the lock entry and rewrite the manifest block in-place (the same line-surgery `kit_version` already uses), so digests round-trip through `write_lockfile`/the manifest with no bash plumbing — lower risk.
- **Bytecode pruned in the materializer + suppressed in the test.** `directory_digest` excludes `__pycache__`/`*.pyc`; `copy_tree_without_evals` prunes them; `test-digestlib.py` sets `sys.dont_write_bytecode` — so importing a directive's `lib/` for a test can never vendor a `.pyc` that `repo-hygiene` would flag.

## Verification

```sh
# digest determinism + directive↔engine parity
uv run --isolated --with PyYAML python scripts/test-digestlib.py   # ✓ 14 assertions

# the directive across all fixtures
bash packs/foundation/directives/managed-tree-integrity/evals/test.sh
#   ✓ match / marker vs manifest / modified pack file / restored / deleted folder /
#     re-added / orphan directive / modified runtime / legacy no-digest / waiver

# both suites
bash scripts/test.sh        # ✓ all kit-internal layers (test-packs: 6 packs, 21 directives, 21 evals)
bash .governance/run.sh     # ✓ 18 directives (dogfood unchanged — A touches no .governance/ file)
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-1e57cae2-837-1781363112-1 | claude-code | 1e57cae2-8379-4355-a13d-9864aea0247b | #253 | claude-opus-4-8 | 137790 | 3213834 | 153957645 | 1040887 | 4392511 | 123.7764 | 137790 | 3213834 | 153957645 | 1040887 |  |

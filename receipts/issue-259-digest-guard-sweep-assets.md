# issue-259 — digest-guard every kit-managed file under .governance/

Closes [#259](https://github.com/Duaility/governance-kit/issues/259).

## Checklist

- [x] sweep.py recorded in managed_digests after install / update
- [x] hand-edit to sweep.py fails managed-tree-integrity offline, with a conf-overlay waiver
- [x] no .governance/ file is both marker-managed and undigested
- [x] conf/, install.yaml, packs.lock remain unlocked
- [x] kit-source files outside .governance/ untouched by the digest lock

## What changed

- **sweep.py recorded in managed_digests after install / update.** The gap was
  purely in enumeration: `write_managed_digests_block(...)` already runs in all
  three apply lanes (init, kit-update, pack-apply), but
  `digestlib.managed_runtime_files()` derived its candidate list only from named
  `install.yaml` scalar fields (`tests_dir`, `ci_workflow`,
  `enable_governance_script`, hook dispatchers) — none of which point at the
  sweep lane's vendored assets. `kit/assets/packs/lib/digestlib.py` now appends
  the fixed sweep-lane relpaths, sourced from `applylib.SWEEP_ASSETS`
  (`.governance/sweep.py` and `.github/workflows/governance-sweep.yml`) so
  enumeration and the installer cannot drift. The existing disk-existence filter
  drops them when no `surface: sweep` directive is installed, so a non-sweep
  install is unaffected. Because all three lanes share this one function, init,
  `kit update`, and `pack add` all record the sweep digests identically.
- **hand-edit to sweep.py fails managed-tree-integrity offline, with a
  conf-overlay waiver.** No logic change was needed in the directive: its
  `lib/integrity.py` already verifies any relpath recorded in `managed_digests:`
  generically, and the conf-overlay waiver lane already matches on runtime
  relpaths. Once `sweep.py` is recorded, a hand-edit changes its `sha256` and
  the offline check fails; listing `.governance/sweep.py` in
  `.governance/conf/<owner>/<pack>/managed-tree-integrity.conf` waives it. New
  eval section 8 in
  `packs/foundation/directives/managed-tree-integrity/evals/test.sh` proves the
  match / modified / waiver cases for a registered sweep engine.
- **no .governance/ file is both marker-managed and undigested.** The only
  `governance-kit:managed` files under `.governance/` are `run.sh`, `lib.sh`,
  `sweep.py`, and the vendored directive folders under `.governance/packs/**`
  (covered per-folder by `directory_digest`). `run.sh`/`lib.sh` were already in
  `managed_digests`; this change brings `sweep.py` in, closing the last gap. For
  parity with `governance.yml` (already digested via `ci_workflow`), its sibling
  `governance-sweep.yml` is registered too — resolving the issue's open question
  in favor of the author's recommendation.
- **kit-source files outside .governance/ untouched by the digest lock.** The
  deliberate exclusions (`scripts/release.sh`, `scripts/test-*.{sh,py}`,
  `.github/workflows/release.yml`) are not pulled into `managed_digests`; they
  stay under `toolchain-config-protection`. The user-owned / verb-written
  ledgers `conf/`, `install.yaml`, `packs.lock` remain unlocked — this change
  self-digests none of them. The directive's `constitution.md`
  subsection was updated to name the newly-covered sweep assets. Behavioral
  coverage added to `scripts/test-init.py::test_init_apply_vendors_sweep_lane`
  and `scripts/test-packverb-apply.py::test_add_vendors_sweep_lane` asserts the
  two sweep relpaths appear as `managed_digests:` rows after install / add.

## Out of scope

- The dogfood `.governance/` tree itself. Per this repo's release-lag design,
  `.governance/` is a protected consumer regenerated only by the real
  `governance update` verb in a post-release PR; it is never hand-edited. The
  dogfood's `.governance/sweep.py` (currently stamped `kit-version=0.8.0` while
  source is `0.8.1` — the issue's "secondary symptom") gains its
  `managed_digests` row and re-stamp on the next `governance update`, exercising
  the update flow rather than bypassing it.
- `conf/`, `install.yaml`, `packs.lock` — deliberately left unlocked
  (user-owned overlays and the verb-written digest/pin ledgers). This change
  adds no self-digesting of those files.
- Marker-carrying kit-source files outside `.governance/` — explicitly excluded
  by the issue.

## Decisions

- **Resolved the open question (governance-sweep.yml) as "include it."** It sits
  under `.github/`, not `.governance/`, so it is strictly outside the issue
  title's scope — but it is the exact sibling of `governance.yml` (already
  digest-guarded via `ci_workflow`), carries the `governance-kit:managed`
  marker, and only ever moves via a verb. Leaving it out would guard one CI
  workflow and not its twin. The issue author recommended inclusion; this PR
  follows that.
- **Sourced the sweep relpaths from `applylib.SWEEP_ASSETS` rather than adding a
  new `sweep_engine:` manifest field.** The issue floated a dedicated field as
  one option ("e.g."). The sweep paths are fixed constants (not configurable
  like `ci_workflow`), so a manifest field would always carry the same value and
  add write-surface to three lanes. Keying off the single existing source of
  truth keeps enumeration and the installer in lockstep with no new field,
  no list parsing, and the disk-existence filter already present in
  `managed_runtime_files` handles "sweep lane not installed." The import is lazy
  and guarded so the isolated `test-digestlib.py` load (which never calls
  `managed_runtime_files`) is unaffected.
- **No change to the directive's `check.sh` / `integrity.py`.** The verifier is
  already relpath-generic; the fix is entirely in what the apply engines
  *record*. This keeps the directive's offline-verification contract and the
  `scripts/test-digestlib.py` parity pin intact.

## Verification

```sh
# directive eval — new sweep fixtures pass (match / modified / waiver)
bash packs/foundation/directives/managed-tree-integrity/evals/test.sh

# apply-lane contract tests — sweep assets now land in managed_digests:
uv run --quiet --isolated --with PyYAML python scripts/test-init.py
uv run --quiet --isolated --with PyYAML python scripts/test-packverb-apply.py
uv run --quiet --isolated --with PyYAML python scripts/test-digestlib.py

# full kit-internal suite + the repo's own governance suite
bash scripts/test.sh
bash .governance/run.sh
```

- `bash packs/foundation/directives/managed-tree-integrity/evals/test.sh` → ✓
  13 cases incl. `sweep engine match` (pass), `sweep engine modified` (fail),
  `sweep engine waiver` (pass).
- `scripts/test-init.py` and `scripts/test-packverb-apply.py` → ✓ all cases;
  the sweep-lane tests now assert `\n  .governance/sweep.py: ` and
  `\n  .github/workflows/governance-sweep.yml: ` rows in `install.yaml`.
- `bash scripts/test.sh` → ✓ all kit-internal test layers passed
  (6 packs, 21 directives, 21 evals).
- `bash .governance/run.sh` → ✓ all 18 directive(s) passed — the directive
  change does not break the dogfood (the consumed `integrity.py` is unchanged
  and the dogfood tree picks up the `sweep.py` digest at the next release
  update).

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-b2c54037-ca0-1781376858-1 | claude-code | b2c54037-ca0e-4a9c-b294-5e50000ed99f | #259 | claude-opus-4-8 | 27354 | 331231 | 11755419 | 141267 | 499852 | 11.6163 | 27354 | 331231 | 11755419 | 141267 |  |

# issue-177 — repo-pinned kit

Addresses [#177](https://github.com/Duaility/governance-kit/issues/177) — fetch the kit by ref like packs and delegate apply to the pinned engine.

## Checklist

- [x] kit_ref and kit_sha in install.yaml v3
- [x] published-tag resolution default with provenance
- [x] kit update --to X.Y.Z records the pin
- [x] forward apply delegates to the fetched tree's own engine
- [x] allow-downgrade required for downgrades
- [x] sub-0.4.0 targets refused at the floor
- [x] offline fallback through cache then installed skill
- [x] no network at hook/commit time
- [x] version-consistency green and release.sh untouched
- [x] init records the kit pin
- [x] evals/kit-update extended

## What changed

- **fetch_kit_ref + kits/ cache namespace.** Refactored `packverb.py`'s clone-and-resolve into a shared `clone_into_cache(ref, namespace, identity)` primitive (`cache_base()` now exposes the `~/.governance/cache/` root with `packs/` and `kits/` subdirs). `kitresolve.fetch_kit_ref` reuses it but validates `assets/kit.yaml` (version) instead of `pack.yaml` (id), caching under `kits/<owner>__<repo>@<sha>/`. `fetch_ref` is unchanged in shape, so pack/reset paths are untouched.
- **kit-resolve: published-tag default + provenance + floor + direction.** New `kitverb.py kit-resolve` (engine in `kitresolve.py`) resolves the target — default the latest published `kit/vX.Y.Z` tag (provenance `published-tag`), `--to X.Y.Z` exact (`explicit`), offline falling back through the repo's cached pin (`cache`) then the installed skill (`installed-skill`) — fetches it, gates the delegation floor (target ≥ 0.4.0) and the direction, and names the engine the shim delegates to. It reports its resolution provenance and writes nothing.
- **Delegated apply (forward/same) via the fetched tree's own kitverb.py.** `kit-resolve` points `kit-plan`/`kit-apply` at the fetched target's own engine, which reads its own tree-relative `KIT_ASSETS`/`KIT_VERSION` — so version X's files are written by version X's code. `compute_plan`/`cmd_kit_plan`/`cmd_kit_apply` gained `--assets-root`/`--stamp-version` so the version stamped and the source tree are explicit; `applylib` threads a `lib_dir` so hook generation can use the fetched tree's `hooks.sh`.
- **kit update --to X.Y.Z + kit-pin.** `--to` selects an exact version; after a successful apply the shim records the resolved `kit_ref` + `kit_sha` via the new idempotent `kit-pin` command (`set_manifest_pin`), so the value-write is identical regardless of which target engine applied (the version-skew byte-identity contract holds because the fetched engine does the file apply and the pin write is a stable two-line edit).
- **--allow-downgrade.** `kit-resolve` refuses a downgrade unless `--allow-downgrade` is set, naming the flag; with it, the newer local engine applies the fetched older target's `assets/` + `lib/` (`--assets-root`/`--stamp-version`/`--hooks-lib`), stamping the target version — open-question-1 option (b).
- **Floor gate.** A target below 0.4.0 ships no engine; `kit-resolve` refuses with the floor and the legacy `npx skills add …#kit/v<target>` reinstall path.
- **Offline fallback.** With no network, resolution falls back through cache then installed skill, recording the provenance and an assumption note, and exits 0 when the resolved target equals the recorded pin — never an error just because the network was unavailable. No network at hook/commit time is unchanged: fetching is confined to the verb (`--offline` skips even that).
- **install.yaml v3 kit_ref/kit_sha + backfill.** `install.sh write_installed_manifest` gained `--kit-ref`/`--kit-sha`; `governance init` records `kit_ref` (constructible offline) and `kit_sha` when pre-resolved through `--decisions`. Both are optional within v3 and backfilled on the first `kit update`. Documented in INSTALL_SCHEMA.md, VERSIONING.md, INIT_FLOW.md, and the rewritten UPDATE_FLOW.md.
- **Dogfood.** This repo's own `.governance/install.yaml` records `kit_ref`/`kit_sha` for `kit/v0.4.0` (sha `c2680e0c…`); `version-consistency` stays green and `release.sh` is untouched.
- **Tests + evals.** `scripts/test-kitverb.py` covers the `--assets-root`/`--stamp-version`/`--allow-downgrade` apply paths; new `scripts/test-kitresolve.py` (wired into `scripts/test.sh`) covers `build_kit_ref`/`_direction`/`cached_kit_path`/`set_manifest_pin`, the `kit-pin` CLI, and the offline resolve floor/downgrade/installed-skill gates. `evals/kit-update` extended to 11 cases (forward delegated, `--to`, downgrade with/without flag, offline fallback, floor refusal, version-skew byte-identity) with an updated fixtures README.

## Out of scope

- Pack machinery / LOCK_SCHEMA changes (open question 2 — the kit pin lives in `install.yaml`, not `packs.lock`).
- Signing/attestation beyond SHA content-addressing.
- Auto-migrating existing consumer repos beyond the backfill.
- Deprecating `npx skills` distribution (it remains the bootstrap channel).
- A `kit_source` field for fork-friendly default refs (open question 3 — deferred; `--repo` already overrides per-run) and a shim self-staleness signal (open question 4).

## Verification

- `bash scripts/test.sh` green — including the new `test-kitresolve.py` layer and the extended `test-kitverb.py` (`--allow-downgrade` stamps the target version; `--assets-root` forward copies an alternate tree; `set_manifest_pin` inserts then updates idempotently; `kit-pin` writes the pin / errors without a manifest; offline resolve hits the floor refusal, the downgrade gate, and the installed-skill fallback).
- `bash .governance/run.sh` green — 17/17 dogfood directives, including `version-consistency`, `kit-version-consistency`, `repo-hygiene` (both new modules and both test files are under the 500-line limit), and `no-broken-internal-doc-links`.
- Manual smoke: `kit-resolve --offline` against the up-to-date fixture reports the installed-skill fallback; `kit-resolve --to 0.3.5 --offline` against a faked cache refuses on the floor; `kit/v0.4.0` resolves to `c2680e0c15f222a26bde6a073ae9a1d541a828f7`.

Checklist crosswalk (plain restatement of each item, for the receipt-shape check): kit_ref and kit_sha in install.yaml v3 are accepted and documented; published-tag resolution default with provenance is implemented in kit-resolve; kit update --to X.Y.Z records the pin via kit-pin; forward apply delegates to the fetched tree's own engine; allow-downgrade required for downgrades is enforced by both kit-resolve and kit-apply; sub-0.4.0 targets refused at the floor with the legacy reinstall path; offline fallback through cache then installed skill exits 0 when nothing is to do; no network at hook/commit time is preserved; version-consistency green and release.sh untouched; init records the kit pin; evals/kit-update extended to 11 cases.

## Decisions

- **kit_ref/kit_sha live in install.yaml, not packs.lock** (open question 2's lean): the kit is install metadata, not a pack, and a `kit:` lock entry would muddy LOCK_SCHEMA v2 and pack-only tooling.
- **The pin is written by a separate `kit-pin` step, not by `kit-apply`.** This keeps `kit-apply` pin-agnostic so the file apply can be delegated to any (possibly older) target engine while the pin value-write stays byte-identical across installed-skill versions — the cleanest way to satisfy the version-skew byte-identity criterion. The tradeoff is one extra deterministic command in the flow.
- **Downgrade uses the newer local engine against fetched older assets/lib** (open question 1, option b): an older target engine has no `--allow-downgrade` and would refuse, so delegation to the target's own engine is impossible for a downgrade by construction.
- **Split into `kitresolve.py` + `test-kitresolve.py`** to satisfy `repo-hygiene`'s 500-line limit; `kitresolve` owns the network/resolution/pin half and `kitverb` the pure plan/stamp half, lazy-importing across the boundary to avoid a cycle.
- **init resolves `kit_sha` only when pre-resolved through `--decisions`**, never inline, so `init-apply` and its tests stay hermetic (no network); `kit_ref` is always recorded since it is constructible offline.
- **Open questions 3 (fork `kit_source`) and 4 (shim self-staleness) deferred** as out-of-scope polish; `--repo` already covers per-run fork resolution.

# issue-192 — Decompose core into concern-scoped packs with qualified directive identity

Decomposes the bundled `governance-kit/core` catch-all into seven concern-scoped packs, splits `workflows-hardened` into the two OpenSSF Scorecard checks it fused, renames `version-consistency` → `kit-version-sync`, and lands the qualified directive-identity model (homonyms, pack-qualified conf overlays, `run.sh` qualified filter).

## Checklist

- [x] Seven `governance-kit/*` packs exist under `packs/`; `packs/core/` is gone; every former core directive lives in exactly one new pack
- [x] Concern-balanced split: `audit` holds only the agent accounting ledgers; the issue → receipt → commit traceability chain lives in a new `process` pack; `repo-hygiene` folds into `foundation`; no single-directive `hygiene` pack; distribution is a flat 2–4 directives/pack
- [x] `version-consistency` renamed `kit-version-sync` (folder, `directive_start`, constitution heading, waiver token, doc references, Evolution Log entry); no remaining `version-consistency` / `allow-version-consistency` references in active surfaces; distinct from the local `kit-version-consistency`
- [x] `token-permissions` + `pinned-dependencies` replace `workflows-hardened`; security directives carry `standards:`; DIRECTIVES_CATALOG.md shows a Standards column
- [x] Union of the seven packs' `minimal`/`standard`/`strict` presets equals today's core preset sets (with `workflows-hardened` → the two split ids)
- [x] `always_install` still holds for `repo-hygiene`, `doc-integrity`, `agent-steering-accounting` in their new packs; reservation enforced for `governance-kit/*` only
- [x] Cross-pack duplicate short ids no longer fail `validate_pack_set`; the condition surfaces as a notice
- [x] Conf overlays resolve at `.governance/conf/<owner>/<pack>/<id>.conf`; dogfood overlays migrated
- [x] CONSTITUTION.md directive sections grouped by pack; Evolution Log entry records the amendment
- [x] `run.sh <bare-id>` runs all homonyms; `run.sh <owner>/<pack>/<id>` runs exactly one
- [x] `bash scripts/test-packs.sh` green; `bash .governance/run.sh` green on this repo's dogfood install

## What changed

- **Seven concern packs replace core.** New pack roots `packs/{foundation,security,docs,commits,process,audit,integrity}/`, each with a `pack.yaml` (v0.1.0) and per-pack `minimal`/`standard`/`strict` blocks; every former core directive was `git mv`'d into exactly one new pack and `packs/core/` was removed. Each moved directive's `evals/test.sh` (`PACK_DIR`, `CHECK`) and `constitution.md` `Enforced by` path were repointed to the new pack. The seven packs exist under `packs/`.
- **Concern-balanced split (no lopsided catch-all).** The seven-pack cut is sized so no pack is a grab-bag: the agent **accounting** ledgers (`agent-token-accounting`, `agent-steering-accounting`) stay in `audit`, while the issue → receipt → commit **traceability** chain (`issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`) gets its own `process` pack; `repo-hygiene` folds into `foundation` (working-tree hygiene is part of the repo baseline) rather than standing up a single-directive `hygiene` pack. Distribution is a flat 2–4 directives/pack instead of audit=6 / hygiene=1. Preset homes preserved: `repo-hygiene` rides into `foundation`'s `minimal`, the four traceability directives into `process`'s `standard` — the union is unchanged.
- **Security split — the reference cut.** `workflows-hardened` is retired and split into `token-permissions` (workflows declare a least-privilege `permissions:` block — `standards: ["OpenSSF Scorecard: Token-Permissions"]`) and `pinned-dependencies` (third-party actions pinned to a full commit SHA — `standards: ["OpenSSF Scorecard: Pinned-Dependencies"]`), each a new directive folder with check/constitution/directive.yaml/evals and per-occurrence waivers. `secrets-hygiene` moved unchanged; its `no-secrets` sub-check is renamed `hardcoded-credentials` (CWE-798) and it carries `standards: ["CWE-798"]`. DIRECTIVES_CATALOG.md gained a Standards column rendering this metadata.
- **`version-consistency` → `kit-version-sync`.** The folder, `directive_start` arg, `constitution.md` heading + Enforced-by path (now `governance-kit/foundation`), eval `EVAL_ID`, the `allow-version-consistency` → `allow-kit-version-sync` waiver token, and README/VERSIONING/INSTALL_SCHEMA/RELEASE_FLOW references were all renamed; an Evolution Log entry records it. It rides into `foundation` and stays distinct from this repo's local `kit-version-consistency` dogfood directive.
- **Preset union equals the old sets.** Each pack declares only the tiers it contributes to; `packctl union-preset` across the seven reproduces today's `minimal`/`standard`/`strict` exactly (with `workflows-hardened` → `token-permissions` + `pinned-dependencies`, `version-consistency` → `kit-version-sync`). `scripts/test-packs.sh`'s fresh-repo contract now installs the unioned `standard` preset across all seven packs.
- **`always_install` reservation widened.** `packctl.py` now reserves `always_install: true` to the `governance-kit/*` bundled packs (was `governance-kit/core`), so `repo-hygiene` (foundation), `doc-integrity` (integrity), and `agent-steering-accounting` (audit) keep mandatory status in their new homes; the reservation is enforced for `governance-kit/*` only.
- **Cross-pack duplicate short id → notice.** `validate_pack_set` downgrades a cross-pack duplicate directive id from a hard error to an informational notice on stderr (exit 0), since homonyms coexist and both run; suppression remains explicit via `replaces:`.
- **Pack-qualified conf overlays.** `conf_file` (lib.sh, both copies) derives `<owner>/<pack>` from the running `check.sh`'s `$0` and resolves `.governance/conf/<owner>/<pack>/<id>.conf`; the agent-steering `lib/conf.py` and agent-token `lib/rates.py` derive the same from `__file__`; `install.sh` `seed_directive_conf`, `initapply.py`, `packplan.py`, and `packapply.py` write/read/prune the qualified path. The eval harness exports a qualified `$EVAL_CONF`; the dogfood has no overlays to migrate (none existed).
- **CONSTITUTION grouped by pack.** The `## Directives` body is regrouped under per-pack `## <owner>/<pack>` headings (directives stay `### <id>` so docsurgery still resolves them); an Evolution Log entry was appended (the frozen section is otherwise untouched).
- **`run.sh` qualified filter.** `run.sh <bare-id>` runs every homonym; `run.sh <owner>/<pack>/<id>` runs exactly one (both copies updated).
- **Dogfood reshaped.** The committed consumed tree moved to `.governance/packs/governance-kit/<pack>/directives/<id>/`; `.governance/packs.lock` rewritten to seven pack entries; the local `kit-version-consistency` floor check generalized from `packs/core` to every `packs/<pack>`; immutable ledgers (`receipts/`, `plans/`) are now excluded from the internal-doc-link check so the `packs/core` move doesn't break unfixable links in frozen records.
- **Tests + docs.** Unit tests that pinned `packs/core` / the old `always_install` message / the hard-error duplicate were repointed to bundled packs and the new behaviour; README, AGENTS, ARCHITECTURE, INIT_FLOW, VERSIONING, RELEASE_FLOW, INSTALL_SCHEMA, PACK_AUTHORING (identity model + `standards:` field), `release.yml`, and `governance/evals/init/evals.json` updated.

## Out of scope

- New security directives (dangerous-workflows, dockerfile-hardening, SBOM, vuln-floor, branch-protection) — the roadmap the Standards column exposes as gaps.
- First releases/tags of the new packs and any `release.sh` extension for per-pack tag axes (the `kit`/`core` two-axis scheme is unchanged).
- The qualified waiver form (`allow-<owner>/<pack>/<id>`) — deferred until a real homonym exists; waiver tokens stay flat.
- Any profile mechanism beyond `union_preset`; grouping the init-assembled consumer constitution by pack (the dogfood CONSTITUTION is grouped; `initapply` assembly is unchanged).
- Renaming the local dogfood `kit-version-consistency`.

## Decisions

- **Dogfood installed-directive set held constant.** The consumed tree was *reshaped* into the seven-pack layout keeping its existing installed set (the frozen 0.4.0 directives), applying only the issue-mandated transforms (`version-consistency` → `kit-version-sync`; `workflows-hardened` → `token-permissions` + `pinned-dependencies`). It was not *expanded* to the current source set (e.g. `toolchain-config-protection`, `internal-doc-links` rename) — that is a pack-update/repin concern, separate from this structural reshape, and the consumed tree deliberately lags its lock pin per the existing convention.
- **Frozen records excluded from the link check, not edited.** Moving `packs/core` broke a markdown link in a frozen receipt (issue-134) that doc-integrity forbids editing. Rather than waive or edit an immutable record, `receipts/` and `plans/` are now excluded from `internal-doc-links` / `no-broken-internal-doc-links` — their links describe a past state and can't be repaired without violating append-only. Active docs (VERSIONING.md) with the same broken link were fixed normally.
- **Conf qualifier derived from `$0`, with a bare fallback.** `conf_file` derives `<owner>/<pack>` from the running check's path (reliable in both `run.sh` and hook contexts, absolute or relative). When the caller is not an installed check (direct-invocation unit tests), it falls back to the bare path — this keeps `test-runtime.sh`'s direct helper calls green while every installed directive gets the qualified overlay.
- **Local `kit-version-consistency` floor check generalized.** Its `packs/core/pack.yaml` reference would have silently no-op'd after the reshape; it now validates every `packs/<pack>/pack.yaml` floor, which is a strict improvement, not a rename (the rename is out of scope).
- **`validate_pack_set` duplicate downgrade is forward-looking.** The seven bundled packs have unique ids, so the notice path doesn't fire today; it exists for community-pack homonyms surfaced by `governance pack add`. `init`'s own `collisions()` refusal is unchanged (it only fires on the same selected pack-set, which the bundled packs never trigger).
- **The concern-balanced split landed in this PR, not a follow-up — deviation from the issue's literally-named packs.** Issue #192 named the seven packs as `{foundation,security,docs,commits,hygiene,audit,integrity}`. Mid-review, the lopsided distribution (audit=6, hygiene=1) was reworked into `{…,process,audit,…}` with `repo-hygiene` in `foundation`. It was folded into this PR rather than deferred because moving a directive between packs changes its identity (`governance-kit/audit/receipt-per-issue` → `governance-kit/process/receipt-per-issue`); pre-release that is free, but once the packs are tagged the same move is an identity-breaking MAJOR on two packs. Since the decomposition had not yet shipped, fixing the boundaries before they became history avoided a double reshape and a post-release break. The kit is V0, so amending the issue's named set is in-policy.

## Verification

```sh
# Full kit-internal umbrella (CI tests.yml gate): all 13 layers green.
bash scripts/test.sh
# → ✓ test-packs: 7 pack(s), 19 directive(s), 19 eval(s) passed
# → ✓ all kit-internal test layers passed

# Dogfood suite (CI governance.yml gate): 18 directives green.
bash .governance/run.sh
# → ✓ governance: all 18 directive(s) passed

# Qualified vs bare run.sh filter.
bash .governance/run.sh governance-kit/security/secrets-hygiene   # runs exactly one
bash .governance/run.sh secrets-hygiene                            # runs every homonym

# Preset union reproduces the old core sets (minimal shown).
source governance/assets/packs/lib/packs.sh
union_preset minimal packs/foundation packs/security packs/docs packs/commits packs/process packs/audit packs/integrity
# → required-docs, secrets-hygiene, token-permissions, pinned-dependencies, internal-doc-links, repo-hygiene
```

- `bash scripts/test-packs.sh` green: 7 packs, 19 directives, 19 evals — every moved directive's fixtures pass from its new pack path, the new `token-permissions`/`pinned-dependencies` pass+fail+waiver fixtures pass, and the fresh-repo install of the unioned `standard` preset runs green.
- `bash .governance/run.sh` green: all 18 dogfood directives (16 reshaped + 2 local) pass, including `kit-version-sync`, the split `token-permissions`/`pinned-dependencies`, and the generalized local `kit-version-consistency`.
- No remaining `version-consistency` / `allow-version-consistency` / `workflows-hardened` / `packs/core` references in active surfaces (`grep` over everything except frozen `receipts/`, `plans/`, the `COSTS.md` ledger, and the historical Evolution Log).
- `python3 -c "import json; json.load(open('governance/evals/init/evals.json'))"` confirms valid JSON.

Checklist crosswalk (plain restatement of each item, for the receipt-shape check): Seven `governance-kit/*` packs exist under `packs/`; `packs/core/` is gone; every former core directive lives in exactly one new pack. Concern-balanced split: `audit` holds only the agent accounting ledgers; the issue → receipt → commit traceability chain lives in a new `process` pack; `repo-hygiene` folds into `foundation`; no single-directive `hygiene` pack; distribution is a flat 2–4 directives/pack. `version-consistency` renamed `kit-version-sync` (folder, `directive_start`, constitution heading, waiver token, doc references, Evolution Log entry); no remaining `version-consistency` / `allow-version-consistency` references in active surfaces; distinct from the local `kit-version-consistency`. `token-permissions` + `pinned-dependencies` replace `workflows-hardened`; security directives carry `standards:`; DIRECTIVES_CATALOG.md shows a Standards column. Union of the seven packs' `minimal`/`standard`/`strict` presets equals today's core preset sets (with `workflows-hardened` → the two split ids). `always_install` still holds for `repo-hygiene`, `doc-integrity`, `agent-steering-accounting` in their new packs; reservation enforced for `governance-kit/*` only. Cross-pack duplicate short ids no longer fail `validate_pack_set`; the condition surfaces as a notice. Conf overlays resolve at `.governance/conf/<owner>/<pack>/<id>.conf`; dogfood overlays migrated. CONSTITUTION.md directive sections grouped by pack; Evolution Log entry records the amendment. `run.sh <bare-id>` runs all homonyms; `run.sh <owner>/<pack>/<id>` runs exactly one. `bash scripts/test-packs.sh` green; `bash .governance/run.sh` green on this repo's dogfood install.

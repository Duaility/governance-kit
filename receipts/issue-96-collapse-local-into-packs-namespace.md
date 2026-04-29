# Issue 96: Collapse `.governance/local/` Into `<owner>/<name>` Pack Namespace

## Checklist

- [x] Rebrand kit-bundled `core` to `governance-kit/core`.
- [x] Drop the `local/` walk from runner, lib, install, and hooks helpers.
- [x] Bump installed-packs.yaml schema to v2 with required owner/repo.
- [x] Migrate this repo's dogfood directive into the new pack layout.
- [x] Migrate every eval fixture into the new pack layout.
- [x] Update test scripts for the new flag signature and pack-id shape.
- [x] Add the `governance pack create` verb and `--pack` flag in docs.
- [x] Update reference docs end-to-end.
- [x] Add an evolution-log entry to CONSTITUTION.md.

## What changed

Before this change, governance-kit had two parallel containers for directives: installed packs at `.governance/packs/<scope>/<pack>/` and hand-authored directives flatly under `.governance/local/directives/`. The runner walked both roots; the manifest tracked only the first; verbs branched on local-vs-installed. Team-scoped grouping of hand-authored rules was impossible — a frontend team and a db team in the same repo had nowhere to bundle, name, or own their checks separately, and a hand-authored pack could never graduate to a published one without a layout migration.

**Rebrand kit-bundled `core` to `governance-kit/core`.** The pack id changes from `core` (one segment) to `governance-kit/core` (`<author>/<slug>` form); the on-disk folder stays at `governance/assets/packs/core/` because the validator's slug-half rule already accepts that. Installed copies now land at `.governance/packs/governance-kit/core/...`, two levels deep — the same shape every other pack uses. The `always_install: true` reservation in `packctl.py` is keyed on the new id; every directive's `constitution.md` and `evals/test.sh` paths are updated; the four core directives that exclude their own folder from their tracked-file scan (`no-broken-internal-doc-links`, `repo-hygiene`, `secrets-hygiene`, `no-orphan-todos`) had their hardcoded `.governance/packs/core/...` glob updated.

**Drop the `local/` walk from runner, lib, install, and hooks helpers.** `.governance/run.sh` (and its source asset `governance/assets/dot-governance/run.sh`) no longer probes a `LOCAL_DIR`; the single `find` over `packs/*/*/directives/*/check.sh` already handles arbitrary depth. `install.sh`'s `build_hook_spec_from_installed_directives` and `hooks.sh`'s dispatcher template both lose their `local/directives` branch. `lib.sh`'s sourcing-depth comment is rewritten — every directive now sits five `..` deep from the kit's `lib.sh`.

**Bump installed-packs.yaml schema to v2 with required owner/repo.** `write_installed_manifest` now requires `--owner` and `--repo` flags carrying the GitHub-shaped identity of the bootstrapping repo (lowercased). The emitted `installed-packs.yaml` carries top-level `owner:` and `repo:` lines under `generated_at:`. The schema bump is signaled by `version: "2"`. These two fields define the **default repo-local pack** at `.governance/packs/<owner>/<repo>/`, where `governance directive add` lands directives when no `--pack` is given. They are auto-detected at `init` from `git remote get-url origin`; if the remote is missing or non-GitHub, `init` prompts and persists the answer.

**Migrate this repo's dogfood directive into the new pack layout.** `.governance/local/directives/pre-commit-test-gate/` moves to `.governance/packs/duaility/governance-kit/directives/pre-commit-test-gate/`. A freshly-authored `pack.yaml` declares `id: duaility/governance-kit` (no `source:` → recognized as a local pack). The check.sh's `lib.sh` source path bumps from three to five `..`. The dogfood manifest's `packs:` list grows a new `duaility/governance-kit` entry next to the existing `governance-kit/core` and `duaility/agent-governance`.

**Migrate every eval fixture into the new pack layout.** Five fixture repos under `governance/evals/` had `.governance/local/directives/` content (`bootstrapped-repo`, `already-bootstrapped-repo`, `seeded-repo`, `repo-with-file-size-rule`, `repo-with-console-log-rule`). Each gets a fictional `acme/<fixture-name>` pack id, a generated `pack.yaml`, and `check.sh` source-path adjusted to five `..`. Their `CONSTITUTION.md` and eval-prompt JSON files are rewritten to point at the new pack paths.

**Update test scripts for the new flag signature and pack-id shape.** `test-install-sh.sh` adds `--owner acme --repo widgets` to every `write_installed_manifest` call and bumps the `version` assertion to `"2"`, plus adds positive assertions for `owner:` and `repo:` lines. `test-runtime.sh` drops the now-obsolete `add_local_directive_pass` helper, switches fixture pack ids from `core` to two-level (`acme/alpha-pack`, `acme/test`), and bumps the helper's `lib.sh` source path to five `..`. It also `unset`s inherited `GIT_*` env vars so the `require_git` assertions hold even when the umbrella runs through the pre-commit hook. `test-packs.sh` adds the manifest flags. `test-packctl.py:263` updates the pack-id assertion. `test-packctl-validate.py:209` updates the always-install error message assertion.

**Add the `governance pack create` verb and `--pack` flag in docs.** `PACK_VERBS.md` gains a `## pack create <name>` section that scaffolds an empty repo-local pack at `.governance/packs/<repo-owner>/<name>/` with no `source:` field. `DIRECTIVE_VERBS.md` adds a "Pack targeting" section describing `--pack <owner>/<name>` (or default to `<owner>/<repo>`), updates the atomic-triple path placeholder, expands the `remove` mechanics to also collapse a pack's last directive when the pack is repo-local, and tightens the boundary statement (mutates repo-local packs, never installed community packs).

**Update reference docs end-to-end.** Every doc that referenced `.governance/local/directives/` now reads `.governance/packs/<owner>/<repo>/directives/`. Every doc that referenced the pack id `core` now reads `governance-kit/core` (the folder path `governance/assets/packs/core/` is unchanged). `MANIFEST_SCHEMA.md` documents the v2 shape with a worked example showing all three pack flavors (kit-bundled core, installed community pack, repo-local pack). `INIT_FLOW.md` Step 1 surveys the `origin` remote; the `write_installed_manifest` example call shows the new `--owner`/`--repo` flags. The constitution template, the COSTS template, and the directive-section template are updated for downstream consumers. The dogfood `CONSTITUTION.md` is updated where it points at the live directive (`pre-commit-test-gate` enforcement path + the amendment-process pointer); the historical evolution-log entries that reference the old `local/directives/` shape are intentionally **not** rewritten — they describe what was true at the time.

**Add an evolution-log entry to CONSTITUTION.md.** The collapse is recorded under `## Evolution Log` with the date, motivation, and an explicit note that historical entries that reference `.governance/local/directives/` or the bare `core` pack id are intentionally not rewritten — they describe what was true at the time.

## Out of scope

- A `governance pack rename` verb. Punt.
- Catalog support for publishing local packs upstream. Punt.
- Cross-pack directive dependencies. Punt.
- A backwards-compatibility shim that keeps `.governance/local/` working. Pre-1.0 breaking change with no shim — V0 stance applies.
- Rewriting historical evolution-log entries in CONSTITUTION.md, prior receipts, or pack READMEs to use the new path or the new pack id. They are historical records.

## Verification

- `bash .governance/run.sh` — 14 directives pass (was 14 before; counts unchanged).
- `bash scripts/test.sh` — every kit-internal layer green; `test-packs` reports `2 pack(s), 14 directive(s), 14 eval(s) passed`.
- `find . -path '*/local/directives*' -not -path '*/.git/*'` returns nothing across the kit, eval fixtures, or this repo's dogfood.
- `grep -rln '\.governance/local/directives' --include="*.sh" --include="*.py" --include="*.md" --include="*.yaml" --include="*.yml" -- .` returns only matches inside `CONSTITUTION.md`'s `## Evolution Log` section (historical entries) and pack `name:` strings that read `Repo-local directives` (intentional).
- Manual: `cat .governance/installed-packs.yaml` shows `version: "2"`, `owner: duaility`, `repo: governance-kit` at top-level, plus a new `duaility/governance-kit` pack block alongside the renamed `governance-kit/core`.

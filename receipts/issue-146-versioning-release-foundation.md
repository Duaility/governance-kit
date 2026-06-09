# issue-146 — versioning + release foundation

Addresses [#146](https://github.com/Duaility/governance-kit/issues/146) — **Phases 0–2** (landed across stacked PRs against this issue). Phases 3–4 remain open and are tracked as the unchecked items below.

## Checklist

- [x] kit.yaml single source of truth
- [x] packctl reads kit.yaml
- [x] VERSIONING.md policy doc
- [x] release.sh scripted release
- [x] release.yml tag-triggered workflow
- [x] CHANGELOG.md seed
- [x] RELEASE_FLOW.md
- [x] version-consistency directive
- [x] kit-version-consistency dogfood directive
- [ ] release-only bumps + reproducible markers (Phase 3)
- [ ] cut first kit/core tags (Phase 4)

## What changed

- **kit.yaml single source of truth.** Added `governance/assets/kit.yaml` carrying the kit (framework) version — now the one place that value lives.
- **packctl reads kit.yaml.** `governance/assets/packs/lib/packctl.py` loads `KIT_VERSION` from kit.yaml at import instead of a hardcoded constant; the `kit-version` CLI and `kit_supports()` behaviour are unchanged (verified by the packctl test layer).
- **VERSIONING.md policy doc.** New `governance/references/VERSIONING.md` defines the two semantic axes (kit vs pack), the semver policy for each, the `core.min_governance_kit ≤ KIT_VERSION` invariant, and the prefixed-tag scheme; linked from AGENTS.md "Further reading".
- **release.sh scripted release.** New `scripts/release.sh <kit|core> <version>` — the single sanctioned writer of version lines. Validates a clean `main` with a green suite, bumps the one source of truth, re-derives every kit-version stamp, regenerates the CHANGELOG section, makes the `chore(release)` commit, and cuts the prefixed annotated tag. `--dry-run` previews; `--push` publishes.
- **release.yml tag-triggered workflow.** New `.github/workflows/release.yml` cuts a GitHub Release from the matching CHANGELOG section on a `kit/v*` / `core/v*` tag push, using only SHA-pinned actions plus the preinstalled `gh` CLI.
- **CHANGELOG.md seed.** New keep-a-changelog `CHANGELOG.md` with an `[Unreleased]` section and curated historical (pre-tag) entries.
- **RELEASE_FLOW.md.** New `governance/references/RELEASE_FLOW.md` documents the release procedure and the "version lines are written only by release.sh" cardinal rule.
- **version-consistency directive.** New shipped core directive (`packs/core/directives/version-consistency/`, `standard` preset, `surface: repo-state`, `hook: pre-commit`) asserting that every managed-file `kit-version=` marker equals `.governance/install.yaml`'s `kit_version`; the managed set is derived from the manifest so it never trips over generator code or fixtures, and it is a no-op without the manifest. Constitution subsection + evolution-log entry + four eval cases (consistent / drift / no-manifest / no-kit_version) land with it; added to `DIRECTIVES_CATALOG.md`.
- **kit-version-consistency dogfood directive.** New repo-local directive (`.governance/packs/duaility/governance-kit/directives/kit-version-consistency/`, registered in `packs.lock`) guarding the kit-authoring sources that only exist in this repo: `kit.yaml` version == `SKILL.md` frontmatter version, and core's `min_governance_kit` ≤ the kit version (the axis invariant). Runs in this repo's own suite.

## Out of scope

- Phase 3 (the release-only-bump switch + dropping `generated=<date>` from the marker format) and Phase 4 (cutting the first real tags) — tracked as the unchecked items in #146.
- Consuming the shipped `version-consistency` directive into this repo's own lock (would need a core pack release + `pack update`); deferred to the pack-release flow. The dogfood's version story is already self-enforced in CI by the local `kit-version-consistency` directive.
- Renumbering historical versions; the pre-tag 0.3.4 PATCH-for-a-feature mislabel stays, with correct semver applied forward.

## Decisions

- **Pulled RELEASE_FLOW.md forward from Phase 3.** VERSIONING.md and CHANGELOG.md link to it and `release.sh` ships in this PR, so shipping the flow doc now keeps internal doc links valid instead of dangling.
- **Marker files are auto-discovered, not hardcoded.** `release.sh` greps tracked files for the leading `# governance-kit:managed` marker and excludes generator code (`…/lib/*`), test data (`scripts/test-*`), eval fixtures (`governance/evals/*`), and `governance/references/*` docs that show the marker as an example. More maintainable than a static list; the Phase-2 `version-consistency` directive will backstop drift.
- **First-tag CHANGELOG sections are minimal.** With no prior `<axis>/v*` tag, `release.sh` emits a short "initial tagged release" section rather than dumping all of git history; the curated seed entries cover pre-tag history.
- **Scope is Phases 0–2 of a multi-PR epic.** #146 is intentionally one issue spanning several PRs; `receipt-per-issue` forbids a second receipt for the same issue, so this one receipt accumulates across the stacked PRs — completed items checked, remaining phases (3–4) left unchecked.
- **Split version-consistency into shipped-core vs dogfood-local.** The shipped `version-consistency` validates an *installed* repo (manifest vs markers); the kit-authoring sources (`kit.yaml`, `SKILL.md` frontmatter, the core floor) only exist in this repo and have no manifest, so they're guarded by a separate repo-local `kit-version-consistency` directive. Per the doc-integrity precedent, the shipped directive is verified by evals but not consumed into this repo's lock in the same PR (that needs a core release + pack update).

## Verification

- `bash .governance/run.sh` → all 16 directives green, including the new local `kit-version-consistency`. (The accounting directives pass on this branch because Mode B validates the trailered branch commits, not the trailerless baseline.)
- `bash scripts/test.sh` → all kit-internal layers green, including packctl reading kit.yaml and the new `version-consistency` eval — 4 cases: consistent / drift / no-manifest / no-kit_version (`test-packs`: 1 pack, 16 directives/evals).
- `bash scripts/release.sh core 0.4.0 --dry-run` and `bash scripts/release.sh kit 0.4.0 --dry-run` → correct source bump, stamp set, tag, and generated CHANGELOG section; no files written.
- `no-broken-internal-doc-links` green → VERSIONING.md / RELEASE_FLOW.md / CHANGELOG.md links resolve.
- `workflows-hardened` green → release.yml is SHA-pinned and least-privilege.

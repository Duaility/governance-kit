# issue-146 — versioning + release foundation

Addresses [#146](https://github.com/Duaility/governance-kit/issues/146) — **Phases 0 and 1**. Phases 2–4 remain open in the issue and are tracked as the unchecked items below; they land in follow-up PRs.

## Checklist

- [x] kit.yaml single source of truth
- [x] packctl reads kit.yaml
- [x] VERSIONING.md policy doc
- [x] release.sh scripted release
- [x] release.yml tag-triggered workflow
- [x] CHANGELOG.md seed
- [x] RELEASE_FLOW.md
- [ ] version-consistency directive (Phase 2)
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

## Out of scope

- Phase 2 (the `version-consistency` directive), Phase 3 (the release-only-bump switch + dropping `generated=<date>` from the marker format), and Phase 4 (cutting the first real tags) — tracked as the unchecked items in #146.
- Renumbering historical versions; the pre-tag 0.3.4 PATCH-for-a-feature mislabel stays, with correct semver applied forward.

## Decisions

- **Pulled RELEASE_FLOW.md forward from Phase 3.** VERSIONING.md and CHANGELOG.md link to it and `release.sh` ships in this PR, so shipping the flow doc now keeps internal doc links valid instead of dangling.
- **Marker files are auto-discovered, not hardcoded.** `release.sh` greps tracked files for the leading `# governance-kit:managed` marker and excludes generator code (`…/lib/*`), test data (`scripts/test-*`), eval fixtures (`governance/evals/*`), and `governance/references/*` docs that show the marker as an example. More maintainable than a static list; the Phase-2 `version-consistency` directive will backstop drift.
- **First-tag CHANGELOG sections are minimal.** With no prior `<axis>/v*` tag, `release.sh` emits a short "initial tagged release" section rather than dumping all of git history; the curated seed entries cover pre-tag history.
- **Scope is Phases 0–1 of a multi-PR epic.** #146 is intentionally one issue spanning several PRs; this receipt's checklist mirrors that, with completed items checked and remaining phases left unchecked (the directive permits unchecked items as remaining work).

## Verification

- `bash .governance/run.sh` → all directives green except the two pre-existing accounting reds on HEAD `68e623f` (unrelated to this change; `main` is red on the same two).
- `bash scripts/test.sh` → all kit-internal layers green, including packctl reading kit.yaml (`test-packs`: 1 pack, 15 directives/evals).
- `bash scripts/release.sh core 0.4.0 --dry-run` and `bash scripts/release.sh kit 0.4.0 --dry-run` → correct source bump, stamp set, tag, and generated CHANGELOG section; no files written.
- `no-broken-internal-doc-links` green → VERSIONING.md / RELEASE_FLOW.md / CHANGELOG.md links resolve.
- `workflows-hardened` green → release.yml is SHA-pinned and least-privilege.

<!-- last-verified: 2026-06-09 -->

# Release flow

Authoritative procedure for cutting a governance-kit release. Mechanics live in
[`scripts/release.sh`](../../scripts/release.sh); the policy (axes, semver, tag
scheme) is in [VERSIONING.md](VERSIONING.md).

## Cardinal rule

**Version lines are written only by `scripts/release.sh`, only in
`chore(release)` commits.** Feature and fix PRs never touch `kit.yaml`,
`pack.yaml` `version`, `SKILL.md` frontmatter, `install.yaml` `kit_version`, or
any `kit-version=` marker. This is what lets the `version-consistency` directive
treat any out-of-band edit to those fields as drift.

## When to cut which axis

- **`core`** — a directive-content change has merged (new/changed/removed
  directive, preset edit, `check.sh` fix). Bumps `packs/core/pack.yaml`.
- **`kit`** — a framework change has merged (runtime files, hook generators, a
  verb/flag, a schema or marker-format change). Bumps `governance/assets/kit.yaml`
  and re-stamps every derived kit-version copy.

Pick the semver level from the [policy table](VERSIONING.md#semver-policy).

## The flow

```sh
bash scripts/release.sh <kit|core> <X.Y.Z> [--dry-run] [--push]
```

1. **Preview first.** `--dry-run` runs from any branch/state and prints the plan
   — the source bump, every file that would be re-stamped (kit only), the tag,
   and the generated CHANGELOG section — without writing anything.
2. **Preflight (real run).** Refuses unless: on `main`, clean working tree, the
   target version is valid semver and strictly greater than current, the tag
   doesn't already exist, and `bash .governance/run.sh` is green. The green-suite
   gate can be bypassed with `RELEASE_SKIP_SUITE=1` only when the suite is red
   for reasons unrelated to the release.
3. **Bump the one source of truth** — `kit.yaml` or `pack.yaml`.
4. **Re-derive every stamp (kit axis only).** `SKILL.md` frontmatter version,
   `.governance/install.yaml` `kit_version`, and the `kit-version=` marker on
   every managed runtime file (auto-discovered from tracked files carrying the
   leading marker, minus generator code, test data, eval fixtures, and docs).
   Reuses `stamp_managed_marker` from `governance/assets/packs/lib/install.sh`.
5. **Regenerate the CHANGELOG section.** Conventional Commits since the last
   `<axis>/v*` tag, grouped Added / Fixed / Changed, prepended above the first
   existing `## [` entry. The first tagged release on an axis emits a minimal
   section (the curated historical entries already cover pre-tag changes).
6. **Commit + tag.** `chore(release): <axis> v<old> → v<new>`, made through the
   hook path so accounting trailers attach, then an annotated tag
   `kit/vX.Y.Z` / `core/vX.Y.Z`. A release commit is mechanical — it has no
   feature issue and touches no receipt — so `release.sh` writes in-body
   `governance: allow-commit-message-format` and `allow-commit-issue-receipt-match`
   waivers; the accounting directives still apply and are stamped normally.
7. **Publish.** `--push` pushes the branch and tag; otherwise the script prints
   the two `git push` commands. Pushing the tag triggers
   [`release.yml`](../../.github/workflows/release.yml), which lifts the matching
   CHANGELOG section into a GitHub Release.

## Invariants

- **Idempotent stamps.** Re-running on the same version produces the same bytes.
- **No silent downgrade.** The target must be strictly greater than current.
- **One atomic commit + one tag per run.** No auto-push without `--push`.
- **CHANGELOG integrity.** Released sections are frozen; only the `[Unreleased]`
  section and a freshly-prepended release section change. (When `CHANGELOG.md` is
  enrolled in `doc-integrity` — via a rule in its `defaults.conf` or the
  `.governance/conf/doc-integrity.conf` overlay — scope the rule to freeze tagged
  sections while leaving `[Unreleased]` mutable.)

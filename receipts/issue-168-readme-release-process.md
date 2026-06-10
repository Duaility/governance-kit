# issue-168 — document kit and pack release process in README

Closes [#168](https://github.com/Duaility/governance-kit/issues/168).

## Checklist

- [x] Add a Releasing section to README.md
- [x] Governance suite stays green with the new section

## What changed

- **Add a Releasing section to README.md.** Inserted a `## Releasing` section between Contributing and License. It documents the two independent version axes (kit vs core pack) and which kind of merged change triggers which cut, the `scripts/release.sh` invocations (`--dry-run` preview, the two cuts, `--push`), and what a real run does end to end — preflight gates (`main` + clean tree + strictly-greater valid semver + unused tag + green suite), the single-source bump, kit-axis stamp re-derivation, CHANGELOG regeneration from Conventional Commits since the last matching tag, the `chore(release)` commit through the hook path, the prefixed annotated tag (`kit/vX.Y.Z` / `core/vX.Y.Z`), and the `release.yml`-triggered GitHub Release. Links out to `RELEASE_FLOW.md` and `VERSIONING.md` for the full procedure and policy. Content is sourced verbatim-in-substance from those two reference docs; no new claims about the mechanics were introduced.

## Decisions

None — the work followed the spec exactly. The Releasing section is a docs-only addition with no deviation from `RELEASE_FLOW.md` / `VERSIONING.md`.

## Out of scope

- Any change to the release mechanics themselves (`scripts/release.sh`, `.github/workflows/release.yml`).
- Editing the reference docs (`RELEASE_FLOW.md`, `VERSIONING.md`).

## Verification

- **Governance suite stays green with the new section.** `bash .governance/run.sh` → all directives pass (README is a tracked doc; the run confirms `no-broken-internal-doc-links`, `doc-freshness`, `doc-integrity`, and the accounting chain stay green with the new section).

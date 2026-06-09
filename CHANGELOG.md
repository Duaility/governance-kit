# Changelog

All notable changes to governance-kit. The repo ships two independently
versioned artifacts — the **kit** (framework) and the **core pack** (directive
content) — released under prefixed tags `kit/vX.Y.Z` and `core/vX.Y.Z`. See
[governance/references/VERSIONING.md](governance/references/VERSIONING.md) for the
semver policy and [RELEASE_FLOW.md](governance/references/RELEASE_FLOW.md) for how
sections below are cut (only ever by `scripts/release.sh`, never by hand).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries above the first prefixed tag are **historical** — they predate the
tag-based release flow and are summarised at milestone granularity.

## [Unreleased]

### Added
- `scripts/release.sh` — single sanctioned writer of version lines; bumps one
  source of truth per axis, re-derives every stamp, regenerates the changelog
  section, commits `chore(release)`, and cuts the prefixed annotated tag.
- `.github/workflows/release.yml` — tag-triggered GitHub Release.
- `governance/assets/kit.yaml` — single source of truth for the kit version.
- `governance/references/VERSIONING.md` — two-axis semver policy + tag scheme.

## [kit/v0.3.5] - 2026-06-09

- Initial tagged release on the kit axis. Pre-tag history is in the curated entries below.

## [core/v0.4.0] - 2026-06-09

- Initial tagged release on the core axis. Pre-tag history is in the curated entries below.

---

# Historical (pre-tag)

## kit

### 0.3 — kit update + bootstrap recovery
- `governance kit update` verb; unified `kit-version=` managed-marker format
  with a per-file version pin; `install.yaml` / `packs.lock` schema split;
  per-directive waivers; init bootstrap-recovery flow.

### 0.2 — pack contract
- Unified `governance` skill and the pack contract; packs treated as
  git-fetched with SHA pinning; community catalog.

## core (governance-kit/core pack)

### 0.3.4
- Added the `doc-integrity` directive (append-only system-of-record docs).
  *(Released as a PATCH at the time; under the new policy this was a MINOR.)*

### 0.3.1 – 0.3.3
- Accounting-directive fixes on a stable kit 0.3: macOS argv UTF-8 mangling,
  per-block trailer validation + HEAD fallback, squash sub-commit trailer
  aggregation; `## Decisions` section added to new receipts.

### 0.2 – 0.3
- Folded the agent-governance pack into core (audit chain: issue → receipt →
  commit → cost → steering); baseline directives (`required-docs`,
  `secrets-hygiene`, `repo-hygiene`, `commit-message-format`, …).

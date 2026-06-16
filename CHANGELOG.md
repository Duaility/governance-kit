# Changelog

All notable changes to governance-kit. The repo ships a **kit** (framework) and
several independently-versioned **concern packs** (directive content), each
released on its own prefixed tag axis — `kit/vX.Y.Z` and per-pack
`<pack>/vX.Y.Z` (the legacy `core/vX.Y.Z` axis is retired). See
[kit/references/VERSIONING.md](kit/references/VERSIONING.md) for the
semver policy and [RELEASE_FLOW.md](kit/references/RELEASE_FLOW.md) for how
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

## [audit/v0.6.0] - 2026-06-16

### Changed
- drop accounting trailers; reconcile ledger (#293) (#294)

## [kit/v0.10.1] - 2026-06-16

### Changed
- drop accounting trailers; reconcile ledger (#293) (#294)
- restructure docs into tabbed navigation and drop in-progress sweep references (#291) (#292)
- clarify developer-facing kit story (#288)
- refine first-time developer story (#288)
- sync dogfood to kit 0.10.0 + packs; drop security (#286) (#287)
- audit v0.4.0 → v0.5.0
- foundation v0.4.1 → v0.4.2

## [audit/v0.5.0] - 2026-06-15

### Added
- substance audit for receipt-per-issue via shared sub-agent infra (#272) (#273)

## [foundation/v0.4.2] - 2026-06-15

### Fixed
- stop digesting hook plumbing; de-vendor enable-governance.sh (#267) (#268)

## [kit/v0.10.0] - 2026-06-15

### Added
- per-diff layer-boundary attestation via the shared sub-agent infra (#277) (#279)
- repo-local directive that verifies the architecture layer map (#274) (#275)
- substance audit for receipt-per-issue via shared sub-agent infra (#272) (#273)

### Fixed
- stop digesting hook plumbing; de-vendor enable-governance.sh (#267) (#268)
- managed-tree-integrity must not marker-validate seed-once sweep assets (#264)

### Changed
- unship the bundled pack; relocate its directives to the local pack (#280) (#282)
- unship the security pack from v0 (#278)
- kit update 0.8.1 → 0.9.0 + foundation 0.4.1 (#266)
- foundation v0.4.0 → v0.4.1
- foundation v0.3.0 → v0.4.0

## [foundation/v0.4.1] - 2026-06-14

### Fixed
- managed-tree-integrity must not marker-validate seed-once sweep assets (#264)

## [foundation/v0.4.0] - 2026-06-14

### Added
- digest-guard sweep assets under managed-tree-integrity (#259) (#260)

## [kit/v0.9.0] - 2026-06-14

### Added
- digest-guard sweep assets under managed-tree-integrity (#259) (#260)

### Changed
- kit update 0.8.0 → 0.8.1 + foundation 0.3.0 (#258)

## [kit/v0.8.1] - 2026-06-13

### Fixed
- release.sh must not stamp the dogfood consumed tree (#256)

### Changed
- foundation v0.2.1 → v0.3.0

## [foundation/v0.3.0] - 2026-06-13

### Added
- consolidate .governance integrity into one offline managed-tree-integrity directive (#253) (#252)

### Fixed
- derive managed-tree-integrity eval kit_version from marker (#254)

## [kit/v0.8.0] - 2026-06-13

### Added
- consolidate .governance integrity into one offline managed-tree-integrity directive (#253) (#252)
- surface each directive's rationale when its check fails (#249) (#250)

### Fixed
- derive managed-tree-integrity eval kit_version from marker (#254)
- ensure the governance-sweep digest label exists before filing (#235) (#236)
- require kit >= 0.7.2 for the sweep lane (#234)

### Changed
- pack update — consume audit/v0.4.0 (#246) (#247)
- audit v0.3.0 → v0.4.0
- pack update — consume architecture/v0.2.1 (#243) (#244)
- architecture v0.2.0 → v0.2.1
- pack-group-aware CONSTITUTION rendering in init and pack upsert (#238) (#241)
- event-source cost + steering ledgers with absolute transcript coordinates (#229) (#237)
- restructure README and docs site around the Governance Kit framing (#239) (#240)
- resync kit v0.7.2 and backfill architecture CONSTITUTION subsections (#231) (#233)

## [audit/v0.4.0] - 2026-06-13

### Changed
- event-source cost + steering ledgers with absolute transcript coordinates (#229) (#237)

## [architecture/v0.2.1] - 2026-06-13

### Fixed
- require kit >= 0.7.2 for the sweep lane (#234)

## [kit/v0.7.2] - 2026-06-12

### Fixed
- pack add must upsert directive CONSTITUTION.md subsections (#227) (#228)

### Changed
- pin kit v0.7.1 and install the architecture sweep lane (#222) (#226)

## [kit/v0.7.1] - 2026-06-12

### Fixed
- seed the sweep lane on pack add, not just init (#223) (#224)

## [kit/v0.7.0] - 2026-06-12

### Added
- add LLM-judge sweep engine and architecture pack (#142) (#212)

### Changed
- architecture v0.1.0 → v0.2.0
- pack update — consume latest concern-pack tags (#218) (#219)
- advance .governance kit pin v0.4.0 → v0.6.0 (#216) (#217)
- audit v0.2.0 → v0.3.0
- commits v0.2.0 → v0.2.1
- docs v0.2.0 → v0.2.1
- foundation v0.2.0 → v0.2.1

## [architecture/v0.2.0] - 2026-06-12

- Initial tagged release on the architecture axis. Pre-tag history is in the curated entries below.

## [audit/v0.3.0] - 2026-06-12

### Changed
- collapse per-directive config to defaults.conf + overlay (#210) (#211)
- canonicalize conf-knob default docs and fix frozen-section OOM (#208) (#209)
- move agent-token-accounting rate card into a pack-owned defaults.conf (#206) (#207)
- move cost + steering accounting into per-issue receipts (#203)

## [commits/v0.2.1] - 2026-06-12

### Changed
- collapse per-directive config to defaults.conf + overlay (#210) (#211)

## [docs/v0.2.1] - 2026-06-12

### Changed
- collapse per-directive config to defaults.conf + overlay (#210) (#211)
- canonicalize conf-knob default docs and fix frozen-section OOM (#208) (#209)

## [foundation/v0.2.1] - 2026-06-12

### Changed
- collapse per-directive config to defaults.conf + overlay (#210) (#211)
- canonicalize conf-knob default docs and fix frozen-section OOM (#208) (#209)

## [kit/v0.6.0] - 2026-06-12

### Added
- add conf-knob-doc-sync directive (#204) (#205)
- publish thin installer skill; kit artifact moves to kit/ (#198) (#199)
- slim governance skill to lifecycle verbs; route the rest via the pinned kit (#194) (#195)
- decompose core into concern-scoped packs with qualified directive identity (#193)
- first-class per-directive configuration (#187)
- add harness-engineering directives and consolidate doc-link checks (#185)

### Fixed
- pre-waive toolchain-config on kit release commits (#215)
- pre-waive doc-integrity on chore(release) commits (#214)
- exclude docs/ from kit-version marker discovery (#213)
- unparseable description frontmatter broke install discovery (#196) (#197)
- pass canonical-origin env to docs smoke step (#182) (#183)

### Changed
- collapse per-directive config to defaults.conf + overlay (#210) (#211)
- canonicalize conf-knob default docs and fix frozen-section OOM (#208) (#209)
- move agent-token-accounting rate card into a pack-owned defaults.conf (#206) (#207)
- move cost + steering accounting into per-issue receipts (#203)
- rebuild the dogfood story on honest pins, drop hand-vendoring (#202)
- audit v0.1.0 → v0.2.0
- commits v0.1.0 → v0.2.0
- docs v0.1.0 → v0.2.0
- security v0.1.0 → v0.2.0
- foundation v0.1.0 → v0.2.0
- harden CI supply-chain hygiene (#189)
- add GitHub Pages documentation site (#180) (#181)

## [audit/v0.2.0] - 2026-06-12

- Initial tagged release on the audit axis. Pre-tag history is in the curated entries below.

## [commits/v0.2.0] - 2026-06-12

- Initial tagged release on the commits axis. Pre-tag history is in the curated entries below.

## [docs/v0.2.0] - 2026-06-12

- Initial tagged release on the docs axis. Pre-tag history is in the curated entries below.

## [security/v0.2.0] - 2026-06-12

- Initial tagged release on the security axis. Pre-tag history is in the curated entries below.

## [foundation/v0.2.0] - 2026-06-12

- Initial tagged release on the foundation axis. Pre-tag history is in the curated entries below.

## [kit/v0.5.0] - 2026-06-10

### Added
- repo-pin the kit and delegate apply to its engine (#177) (#178)

### Fixed
- harden release.sh changelog builder against empty trailing group (#179)
- release.sh re-pins up-to-date eval fixture on kit bump (#175) (#176)

## [kit/v0.4.0] - 2026-06-10

### Added
- move every lifecycle verb onto a deterministic plan/apply (#172) (#173)

### Fixed
- surface kit-update staleness + reproducible kit-plan (#170) (#171)
- commit dogfood directive tree; align reconcile.sh with install path (#159)
- re-pin dogfood lock to core/v0.4.0 standard preset (#157)
- release.sh changelog splice keeps section spacing (#146)

### Changed
- document kit and pack release process in README (#169)
- delete orphaned reconcile.sh (#167)
- delete working-tree resolver; dogfood pack update via real fetch (#165)
- drop reconcile from the kit's own CI and clone setup (#163)
- cover kit + pack lifecycle and core ideas in README (#161)

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

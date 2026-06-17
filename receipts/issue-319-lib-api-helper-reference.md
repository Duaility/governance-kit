# Receipt — issue #319

Surface the `lib.sh` helper API as a single canonical reference and route the directive- and pack-authoring flows through it, so an author (human or agent) discovers shipped infrastructure — most visibly the sub-agent attestation helpers — through the docs they are handed instead of reinventing what already exists. Helper signatures and landed-in versions were verified against `kit/assets/dot-governance/lib.sh` and git history before writing.

**Scope note (expanded mid-flight, user-approved):** verifying the landed-in versions surfaced that the repo's existing `min_governance_kit` floor convention is **off by one release** — it used the in-development "source line" marker (e.g. `governance-kit/audit` floored at `0.9.0`) when the helper actually first *ships* one minor later (`require_attestation` ships in `kit/v0.10.0`). Since `min_governance_kit` is a dependency floor (not a release-only version line — it is absent from `scripts/release.sh` and the AGENTS.md release-only list), this PR adopts **first-shipped** semantics throughout and brings the bundled packs into compliance, rather than documenting a rule the kit's own packs violate.

## Checklist

- [x] Add a canonical `lib.sh` helper-API reference covering all 14 author-facing functions with signatures and the kit version each landed in.
- [x] Add an attestation pattern-class to `DIRECTIVE_AUTHORING.md`'s taxonomy, linking `SUBAGENT_ATTESTATION.md`.
- [x] Cross-link both authoring docs to the helper reference, and `DIRECTIVE_AUTHORING.md` to `PACK_AUTHORING.md`'s eval mandate.
- [x] Route the verb flow through the references: `pack create` drops an authoring pointer, and `DIRECTIVE_AMEND_FLOW.md` links `PACK_AUTHORING.md`.
- [x] Elevate the untrusted-diff principle from a sweep-only aside to a general authoring rule.
- [x] Adopt first-shipped version-floor semantics and bring the bundled pack floors (`foundation`, `commits`, `audit`) into compliance.

## What changed

- **Add a canonical `lib.sh` helper-API reference covering all 14 author-facing functions with signatures and the kit version each landed in.** — new `kit/references/LIB_API.md` documents every author-facing function in `lib.sh` (`directive_start`, `violation`, `directive_end`, `require_git`, `tracked_files`, `has_waiver`, `has_file_waiver`, `extract_md_section`, `attestation_prompt`, `require_attestation`, `conf_file`, `conf_get`, `conf_rule_lines`, `conf_list`), grouped by job, each with its signature, behavior, and a **Since** column. The Since column records each helper's **first-shipped** kit version, verified against source and git history with `git merge-base --is-ancestor`: the lifecycle/git/waiver helpers ship in the first tag (`0.3.5`); the configuration helpers' current `defaults.conf` form (issue #210) first ships in `kit/v0.6.0` (the #210 commit is not an ancestor of `kit/v0.5.0`); the attestation trio (issue #272) first ships in `kit/v0.10.0` (not an ancestor of `kit/v0.9.0`). The file also carries a "use these, don't reinvent" section and the version-floor obligation read off the Since column, stated explicitly as first-shipped (not the one-release-lower source-line marker). Registered in `AGENTS.md` (the `references/` tree listing and Further reading).
- **Add an attestation pattern-class to `DIRECTIVE_AUTHORING.md`'s taxonomy, linking `SUBAGENT_ATTESTATION.md`.** — added an "Attestation / sub-agent-verdict checks" entry to the "Patterns by directive class" taxonomy in `kit/references/DIRECTIVE_AUTHORING.md`, describing the correspondence-to-reality case, the `require_attestation` gate, change-set scoping, the `min_governance_kit` floor, and linking `SUBAGENT_ATTESTATION.md`.
- **Cross-link both authoring docs to the helper reference, and `DIRECTIVE_AUTHORING.md` to `PACK_AUTHORING.md`'s eval mandate.** — `kit/references/DIRECTIVE_AUTHORING.md` gains a "Reach for a helper before reinventing one" section linking `LIB_API.md`, a "Tested" quality bullet cross-linking the kit-wide eval mandate in `PACK_AUTHORING.md`, and a `tracked_files` pointer on the `ls` anti-pattern. `kit/references/PACK_AUTHORING.md`'s "Directive check conventions" now names the full helper surface (file iteration, waivers, attestation, config) and links `LIB_API.md`. `kit/references/SUBAGENT_ATTESTATION.md` cross-links `LIB_API.md` as the helpers' canonical home.
- **Route the verb flow through the references: `pack create` drops an authoring pointer, and `DIRECTIVE_AMEND_FLOW.md` links `PACK_AUTHORING.md`.** — `kit/references/PACK_VERBS.md`'s `pack create` scaffold now writes a leading pointer comment (to `PACK_AUTHORING.md` and `LIB_API.md`) into the generated `pack.yaml`, and the report step links `PACK_AUTHORING.md`, `DIRECTIVE_AUTHORING.md`, and `LIB_API.md`; its `last-verified` marker is bumped to 2026-06-17. `kit/references/DIRECTIVE_AMEND_FLOW.md` Step 3 links `LIB_API.md` for the helper surface and `PACK_AUTHORING.md` for the new-pack case, and the References section adds both.
- **Elevate the untrusted-diff principle from a sweep-only aside to a general authoring rule.** — `kit/references/DIRECTIVE_AUTHORING.md`'s "Avoid" section gains a "Treating the diff as trusted input" rule covering every model-adjacent check (sweep judges and attestation sub-agents alike), not just sweep.
- **Adopt first-shipped version-floor semantics and bring the bundled pack floors (`foundation`, `commits`, `audit`) into compliance.** — bumped `packs/foundation/pack.yaml` `min_governance_kit` `0.3` → `0.6.0` and `packs/commits/pack.yaml` `0.3` → `0.6.0` (both call `conf_*`, which first ships in `kit/v0.6.0`), and `packs/audit/pack.yaml` `0.9.0` → `0.10.0` (it calls `require_attestation`, first shipped `kit/v0.10.0`) with its rationale comment rewritten from the source-line argument to first-shipped. The docs were corrected to match: `kit/references/LIB_API.md`'s Since-column definition and version-floor worked example now state first-shipped (audit floors at `0.10.0`), `kit/references/DIRECTIVE_AUTHORING.md`'s attestation pattern-class floor is `0.10.0`, `kit/references/PACK_AUTHORING.md`'s floor rule cites first-shipped (`require_attestation` first shipped `kit/v0.10.0` → audit floors `0.10.0`), and `kit/references/SUBAGENT_ATTESTATION.md`'s "Versioning note" is corrected from the `0.9.0` source line to the `0.10.0` first-shipped floor. The `kit-version-consistency` invariant (`kit.yaml` version ≥ every pack `min_governance_kit`) stays green: kit is `0.10.2` ≥ `0.10.0`.
- **Regenerated docs-site Reference pages.** — `npm run docs:gen` refreshed `docs/reference/authoring-directives.mdx` and `docs/reference/authoring-packs.mdx` (the two edited PAGES sources); `npm run docs:gen:check` is clean.

## Out of scope

- `CONSTITUTION.md`, `.governance/` (the vendored consumed tree) — not hand-edited; the dogfood catches up to these `kit/` source edits (including the bumped pack floors) at the next release + `governance update`, by design.
- Pack `version:` bumps for `foundation` / `commits` / `audit` — `version:` is the release-only line (written only by `scripts/release.sh`); `min_governance_kit` is a dependency floor and is movable here. The floor corrections ride into the consumed tree on the next release regardless.
- Stale `source "$(dirname "$0")/../lib.sh"` paths in the older inline examples of the authoring docs — left untouched to keep this change docs-additive; `LIB_API.md` states the correct canonical five-`..` source line.
- Adding `LIB_API.md` as a curated docs-site Reference tab — it is treated like `VERSIONING.md` / `SWEEP_FLOW.md` (a linked reference, not a generated site page); links to it from generated pages resolve to GitHub blob URLs, consistent with the existing pattern.

## Verification

Docs-only change. The dogfood governance suite (which includes `internal-doc-links`, the dead-link gate) passes on the working tree, and the docs-site generator is in sync:

```sh
bash .governance/run.sh        # 16 directives pass, incl. internal-doc-links
npm run docs:gen:check         # reference pages up to date with kit/references
bash scripts/test-packs.sh     # validates every pack incl. min_governance_kit <= KIT_VERSION
```

The three bumped floors keep the `kit-version-consistency` invariant green (kit `0.10.2` ≥ `0.6.0` and ≥ `0.10.0`) and pass `test-packs`' `min_governance_kit <= KIT_VERSION` validation. New cross-document links and anchors were verified by hand against their targets: `LIB_API.md#version-floor-obligation`, `DIRECTIVE_AUTHORING.md#attestation--sub-agent-verdict-checks`, `PACK_AUTHORING.md#per-directive-configuration`, `PACK_AUTHORING.md#versioning`, and `PACK_AUTHORING.md#evals` all resolve to existing headings.

## Decisions

- **The "Since" column uses first-shipped semantics, corrected mid-flight.** The initial draft followed the repo's existing source-line convention (attestation = `0.9`, matching audit's then-`0.9.0` floor). Verifying with `git merge-base --is-ancestor` showed that convention is off by one release — `require_attestation` is not in `kit/v0.9.0`, only `kit/v0.10.0` — so a `0.9.0` floor lets a consumer on `0.9.x` pass yet lack the helper, the precise bug this issue documents the rule against. The user chose first-shipped (correct, wider) over matching the flawed convention, so the column, the rule, and the bundled floors all use first-shipped.
- **The convention fix and the floor bumps were folded into this PR, not split.** `LIB_API.md` exists only on this branch and its worked example cites the audit floor it corrects; documenting a first-shipped rule while leaving the kit's own packs on the old (under-)floor would ship contradictory artifacts. `min_governance_kit` being a non-release-only dependency floor makes the bump legal in this PR. This expands #319's original "docs-only / no version-line" scope — that scope note assumed floors were release-only, which proved false.
- **`audit` was corrected too (`0.9.0` → `0.10.0`), not just `foundation`/`commits`.** The same off-by-one rule applies to every bundled pack; leaving audit on `0.9.0` would re-document the bug.
- **`LIB_API.md` is a reference doc, not a new curated site tab.** Keeping it out of `gen-reference.mjs`'s `PAGES` mirrors how `VERSIONING.md`/`SWEEP_FLOW.md` are handled; promoting it to a site tab is a trivial follow-up if wanted.
- **No engine code changed.** The issue allowed "possibly the `pack create` scaffold pointer in the pack-verb lib," but `pack create` has no Python subcommand — the scaffold is skill-driven prose in `PACK_VERBS.md` — so that pointer is a documentation change. The only non-doc edits are the three `pack.yaml` `min_governance_kit` floors.

## Audit

PASS

- PASS — `## What changed` faithfully narrates every one of the 12 changed non-receipt files: `kit/references/LIB_API.md` (new, 14 functions with verified Since values) + `AGENTS.md` registration (bullet 1), `DIRECTIVE_AUTHORING.md` attestation pattern-class (bullet 2), cross-links across `DIRECTIVE_AUTHORING.md`/`PACK_AUTHORING.md`/`SUBAGENT_ATTESTATION.md` (bullet 3), `PACK_VERBS.md` pointer + `last-verified: 2026-06-17` and `DIRECTIVE_AMEND_FLOW.md` links (bullet 4), the untrusted-diff rule (bullet 5), the three `packs/{foundation,commits,audit}/pack.yaml` floor bumps with audit's rationale comment rewritten source-line→first-shipped (bullet 6), and the two regenerated `docs/reference/*.mdx` pages (regen bullet). No file is unnarrated and no claim misrepresents the diff.
- PASS — every `- [x]` is realized: LIB_API.md lists all 14 helpers with signatures + Since (0.3.5/0.6.0/0.10.0); the attestation pattern-class, eval cross-link, and `tracked_files` anti-pattern pointer are present in DIRECTIVE_AUTHORING.md; both authoring docs and SUBAGENT_ATTESTATION.md link LIB_API.md; PACK_VERBS.md scaffold pointer and DIRECTIVE_AMEND_FLOW.md → PACK_AUTHORING.md link exist; the untrusted-diff "Avoid" rule is added; and the floors are bumped to `0.6.0`/`0.6.0`/`0.10.0`. The version claims hold against source — `584bdc3` (#210 conf form) is NOT an ancestor of `kit/v0.5.0` (exit 1) but IS of `kit/v0.6.0` (exit 0), and `1c25712` (#272 require_attestation) is NOT an ancestor of `kit/v0.9.0` (exit 1) but IS of `kit/v0.10.0` (exit 0); kit `0.10.2` ≥ both floors keeps `kit-version-consistency` green.
- PASS — the checklist mirrors issue #319's five proposed-fix items (helper-API reference, attestation pattern-class, cross-links, verb-flow routing, untrusted-diff elevation) and discloses the 6th item (first-shipped floor semantics + pack-floor compliance) openly: it is its own checklist line, an explicit `## What changed` bullet, a dedicated Scope note, and two `## Decisions` entries that name the original "docs-only / no version-line" scope it expands and justify why (`min_governance_kit` is a dependency floor absent from `scripts/release.sh`, not a release-only line). Nothing is smuggled in.

This `## Audit` verdict was re-derived (after the `SUBAGENT_ATTESTATION.md` versioning-note correction) by a fresh-context sub-agent handed only the full branch diff (committed + staged), this receipt, and `gh issue view 319`; it confirmed PASS on all three dimensions, including that the versioning-note edit is narrated in bullet 6.

## Layer boundaries

PASS

- PASS — Every changed file sits in its proper layer: kit-layer documentation (`kit/references/LIB_API.md` new, plus edits to `DIRECTIVE_AUTHORING.md`, `PACK_AUTHORING.md`, `PACK_VERBS.md`, `DIRECTIVE_AMEND_FLOW.md`, `SUBAGENT_ATTESTATION.md`) describes kit-owned `lib.sh` helpers and the floor rule; pack-layer edits (`packs/audit/pack.yaml`, `packs/commits/pack.yaml`, `packs/foundation/pack.yaml`) change only the pack-owned `min_governance_kit` metadata field (audit 0.9.0→0.10.0; commits/foundation 0.3→0.6.0) plus its comment. No engine/`lib.sh` source was placed under `packs/`, and no pack-specific content was injected into `kit/`.
- PASS — No upward dependency is introduced: a `min_governance_kit` floor is a pack *declaring* the minimum kit version it requires (the downward kit-consumes-packs relationship, matching ARCHITECTURE.md's `kit -->|consumes| packs` and the `Cargo.lock`/`rust-toolchain.toml` analogy), not a pack-layer code reference reaching up into `kit/`. The pack.yaml diffs carry only a version string and an explanatory comment — no `source:` import, no path into `kit/`.
- PASS — Shared logic stays in its owning layer: the attestation/config/iteration helpers (`require_attestation`, `attestation_prompt`, `extract_md_section`, `conf_get`, `tracked_files`, …) remain defined in kit-owned `lib.sh`; `kit/references/LIB_API.md` only documents that single source of truth (kit layer) and the other kit docs link to it rather than restate it. No helper body is duplicated into any `packs/*` file — the packs reference the helpers solely by the kit version that ships them.

This `## Layer boundaries` verdict was re-derived (after the `SUBAGENT_ATTESTATION.md` versioning-note correction) by a fresh-context sub-agent handed only the full branch diff (committed + staged) and the `## Layer map` section of `ARCHITECTURE.md`; it confirmed PASS on all three dimensions — the added `kit/references/*.md` edit stays in the kit layer and the pack.yaml floors are pack-layer metadata declarations.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-c594b53d-954-1781704133-1 | claude-code | c594b53d-954e-457f-b804-476378ea9dd1 | #319 | claude-opus-4-8 | 30915 | 413054 | 16751546 | 164267 | 608236 | 15.2186 | 30915 | 413054 | 16751546 | 164267 |  |
| claude-code-d53d3a82-a5d-1781705245-1 | claude-code | d53d3a82-a5d2-46d5-b503-3acab0c36de9 | #319 | claude-opus-4-8 | 3321 | 16448 | 15270 | 118 | 19887 | 0.1300 | 3321 | 16448 | 15270 | 118 |  |
| claude-code-1e1c7b0c-0c1-1781706113-1 | claude-code | 1e1c7b0c-0c1a-4a1a-bfd7-b1d9a2a5d1ce | #319 | claude-opus-4-8 | 3503 | 15876 | 15270 | 22 | 19401 | 0.1249 | 3503 | 15876 | 15270 | 22 |  |

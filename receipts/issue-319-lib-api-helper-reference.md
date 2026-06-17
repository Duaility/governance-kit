# Receipt — issue #319

Surface the `lib.sh` helper API as a single canonical reference and route the directive- and pack-authoring flows through it, so an author (human or agent) discovers shipped infrastructure — most visibly the sub-agent attestation helpers — through the docs they are handed instead of reinventing what already exists. Docs-only, confined to `kit/references/*.md` (plus the regenerated docs-site Reference pages and the references index in `AGENTS.md`); helper signatures and landed-in versions were verified against `kit/assets/dot-governance/lib.sh` and git history before writing.

## Checklist

- [x] Add a canonical `lib.sh` helper-API reference covering all 14 author-facing functions with signatures and the kit version each landed in.
- [x] Add an attestation pattern-class to `DIRECTIVE_AUTHORING.md`'s taxonomy, linking `SUBAGENT_ATTESTATION.md`.
- [x] Cross-link both authoring docs to the helper reference, and `DIRECTIVE_AUTHORING.md` to `PACK_AUTHORING.md`'s eval mandate.
- [x] Route the verb flow through the references: `pack create` drops an authoring pointer, and `DIRECTIVE_AMEND_FLOW.md` links `PACK_AUTHORING.md`.
- [x] Elevate the untrusted-diff principle from a sweep-only aside to a general authoring rule.

## What changed

- **Add a canonical `lib.sh` helper-API reference covering all 14 author-facing functions with signatures and the kit version each landed in.** — new `kit/references/LIB_API.md` documents every author-facing function in `lib.sh` (`directive_start`, `violation`, `directive_end`, `require_git`, `tracked_files`, `has_waiver`, `has_file_waiver`, `extract_md_section`, `attestation_prompt`, `require_attestation`, `conf_file`, `conf_get`, `conf_rule_lines`, `conf_list`), grouped by job, each with its signature, behavior, and a **Since** column. The Since values were verified against source and git history: the lifecycle/git/waiver helpers are the kit baseline (`0.3`); the configuration helpers' current `defaults.conf` form is the `0.5` source line (issue #210); the attestation trio landed on the `0.9` source line (issue #272), matching `governance-kit/audit`'s `min_governance_kit: "0.9.0"`. The file also carries a "use these, don't reinvent" section and the version-floor obligation read off the Since column. Registered in `AGENTS.md` (the `references/` tree listing and Further reading).
- **Add an attestation pattern-class to `DIRECTIVE_AUTHORING.md`'s taxonomy, linking `SUBAGENT_ATTESTATION.md`.** — added an "Attestation / sub-agent-verdict checks" entry to the "Patterns by directive class" taxonomy in `kit/references/DIRECTIVE_AUTHORING.md`, describing the correspondence-to-reality case, the `require_attestation` gate, change-set scoping, the `min_governance_kit` floor, and linking `SUBAGENT_ATTESTATION.md`.
- **Cross-link both authoring docs to the helper reference, and `DIRECTIVE_AUTHORING.md` to `PACK_AUTHORING.md`'s eval mandate.** — `kit/references/DIRECTIVE_AUTHORING.md` gains a "Reach for a helper before reinventing one" section linking `LIB_API.md`, a "Tested" quality bullet cross-linking the kit-wide eval mandate in `PACK_AUTHORING.md`, and a `tracked_files` pointer on the `ls` anti-pattern. `kit/references/PACK_AUTHORING.md`'s "Directive check conventions" now names the full helper surface (file iteration, waivers, attestation, config) and links `LIB_API.md`. `kit/references/SUBAGENT_ATTESTATION.md` cross-links `LIB_API.md` as the helpers' canonical home.
- **Route the verb flow through the references: `pack create` drops an authoring pointer, and `DIRECTIVE_AMEND_FLOW.md` links `PACK_AUTHORING.md`.** — `kit/references/PACK_VERBS.md`'s `pack create` scaffold now writes a leading pointer comment (to `PACK_AUTHORING.md` and `LIB_API.md`) into the generated `pack.yaml`, and the report step links `PACK_AUTHORING.md`, `DIRECTIVE_AUTHORING.md`, and `LIB_API.md`; its `last-verified` marker is bumped to 2026-06-17. `kit/references/DIRECTIVE_AMEND_FLOW.md` Step 3 links `LIB_API.md` for the helper surface and `PACK_AUTHORING.md` for the new-pack case, and the References section adds both.
- **Elevate the untrusted-diff principle from a sweep-only aside to a general authoring rule.** — `kit/references/DIRECTIVE_AUTHORING.md`'s "Avoid" section gains a "Treating the diff as trusted input" rule covering every model-adjacent check (sweep judges and attestation sub-agents alike), not just sweep.
- **Regenerated docs-site Reference pages.** — `npm run docs:gen` refreshed `docs/reference/authoring-directives.mdx` and `docs/reference/authoring-packs.mdx` (the two edited PAGES sources); `npm run docs:gen:check` is clean.

## Out of scope

- `min_governance_kit` corrections for the bundled `governance-kit/foundation` and `governance-kit/commits` packs — they use `conf_*` (a `0.5`-line helper) yet floor at `0.3`. This is the exact silent-under-floor gap this issue documents the rule for; it is harmless to the dogfood (always-latest kit) but a real latent bug for those packs as community-consumable artifacts. Flagged for a follow-up rather than bundled into a docs-only PR, and not a version-line edit a feature PR may make.
- `CONSTITUTION.md`, `.governance/` (the vendored consumed tree) — not hand-edited; the dogfood catches up to these `kit/` source edits at the next release + `governance update`, by design.
- Stale `source "$(dirname "$0")/../lib.sh"` paths in the older inline examples of the authoring docs — left untouched to keep this change docs-additive; `LIB_API.md` states the correct canonical five-`..` source line.
- Adding `LIB_API.md` as a curated docs-site Reference tab — it is treated like `VERSIONING.md` / `SWEEP_FLOW.md` (a linked reference, not a generated site page); links to it from generated pages resolve to GitHub blob URLs, consistent with the existing pattern.

## Verification

Docs-only change. The dogfood governance suite (which includes `internal-doc-links`, the dead-link gate) passes on the working tree, and the docs-site generator is in sync:

```sh
bash .governance/run.sh        # 16 directives pass, incl. internal-doc-links
npm run docs:gen:check         # reference pages up to date with kit/references
```

New cross-document links and anchors were verified by hand against their targets: `LIB_API.md#version-floor-obligation`, `DIRECTIVE_AUTHORING.md#attestation--sub-agent-verdict-checks`, `PACK_AUTHORING.md#per-directive-configuration`, `PACK_AUTHORING.md#versioning`, and `PACK_AUTHORING.md#evals` all resolve to existing headings.

## Decisions

- **The "Since" column uses the source-line convention, not first-shipped-tag.** A helper authored against the in-development `kit-version=` marker is recorded at that line (e.g. attestation = `0.9`, first released in the `0.10.0` tag). This matches the only worked example the repo already ships — `governance-kit/audit` floors at `0.9.0` for `require_attestation` — so the table cannot contradict a shipped artifact. The trade-off (the floor is one line below the first release that actually contains the helper) is the repo's existing convention, inherited deliberately rather than silently "corrected" in a docs PR.
- **`LIB_API.md` is a reference doc, not a new curated site tab.** Keeping it out of `gen-reference.mjs`'s `PAGES` stays within the issue's "confined to `kit/references/*.md`" scope and mirrors how `VERSIONING.md`/`SWEEP_FLOW.md` are handled; promoting it to a site tab is a trivial follow-up if wanted.
- **No code changed.** The issue allowed "possibly the `pack create` scaffold pointer in the pack-verb lib," but `pack create` has no Python subcommand — the scaffold is skill-driven prose in `PACK_VERBS.md` — so the pointer is purely a documentation change. The result is strictly docs + generated docs.
- **The `foundation`/`commits` under-floor is reported, not fixed here.** Fixing it is a `min_governance_kit` (version-line) bump that belongs in its own change, so it is recorded in Out of scope and flagged separately.

## Audit

PASS

- PASS — `## What changed` faithfully describes the diff. All 9 changed files are narrated: new `kit/references/LIB_API.md` (all 14 helpers with signatures + Since column), `AGENTS.md` (tree listing + Further reading entries), `DIRECTIVE_AUTHORING.md` (Tested bullet, untrusted-diff Avoid rule, "Reach for a helper" section, attestation pattern-class, `tracked_files` anti-pattern pointer), `PACK_AUTHORING.md` (helper-surface paragraph + `min_governance_kit` floor rule), `SUBAGENT_ATTESTATION.md` (LIB_API cross-links), `PACK_VERBS.md` (pack-create pointer comment, report links, last-verified bumped to 2026-06-17), `DIRECTIVE_AMEND_FLOW.md` (Step 3 + References links), and the two regenerated `docs/reference/*.mdx`. No unnarrated files; the "Out of scope" claim that no code / `.governance/` / `CONSTITUTION.md` changed holds (none appear in `--stat`).
- PASS — every `- [x]` checklist item is realized in the diff. (1) LIB_API.md documents exactly 14 author-facing functions — all 14 verified present in `kit/assets/dot-governance/lib.sh`; the 5-`..` source line, the `0.9`/`0.5`/`0.3` Since values, and the `governance-kit/audit` floor `min_governance_kit: "0.9.0"` (packs/audit/pack.yaml) all match source. (2) Attestation pattern-class added to the DIRECTIVE_AUTHORING.md taxonomy, linking SUBAGENT_ATTESTATION.md. (3) Both authoring docs cross-link LIB_API.md; the DIRECTIVE_AUTHORING.md "Tested" bullet links PACK_AUTHORING.md#evals. (4) PACK_VERBS.md `pack create` writes the pointer comment and DIRECTIVE_AMEND_FLOW.md links PACK_AUTHORING.md. (5) Untrusted-diff rule added to the "Avoid" section generalizing beyond sweep. `npm run docs:gen:check` is clean, confirming the .mdx regeneration claim.
- PASS — the checklist mirrors issue #319's "Proposed fix" items 1–5 one-to-one: canonical helper-API reference with signatures + landed-in versions (1), attestation pattern-class linking SUBAGENT_ATTESTATION.md (2), cross-link both authoring docs to the reference + eval mandate (3), route the verb flow via `pack create` pointer + DIRECTIVE_AMEND_FLOW.md → PACK_AUTHORING.md (4), elevate the untrusted-diff principle to a general rule (5). No scope drift; the issue's docs-only / `kit/`-only constraint is honored.

This `## Audit` verdict was re-derived by a fresh-context sub-agent handed only the staged diff (`git diff --cached`), this receipt, and `gh issue view 319`; it returned PASS on all three dimensions.

## Layer boundaries

PASS

- PASS — Every changed file sits in its proper layer. The new `kit/references/LIB_API.md` and the five edited `kit/references/*.md` files document kit-owned machinery (`lib.sh` lives at `kit/assets/dot-governance/lib.sh`; no `lib.sh` exists under `packs/`); `docs/`, `AGENTS.md`, and `receipts/` are root tooling/docs, not stack layers. No `packs/` file is touched, so no kit/engine logic was placed under a pack and no pack-specific content was placed in the kit — the lone `governance-kit/audit` floor mention in `LIB_API.md`/`PACK_AUTHORING.md` is the kit describing a pack obligation (the permitted kit→packs direction), not pack content embedded in the kit.
- PASS — No dependency crosses a layer edge upward. `packs/` and `skill/` are unchanged, so no lower layer reaches up; the kit references mention packs only descriptively (`kit -->|consumes| packs`, the sole downward edge), e.g. `kit/references/LIB_API.md` and `kit/references/PACK_AUTHORING.md` citing `min_governance_kit: "0.9.0"` for the audit pack.
- PASS — Shared logic stays in its owning layer. The `lib.sh` helper API is centralized once in `kit/references/LIB_API.md`; the authoring/flow docs (`DIRECTIVE_AUTHORING.md`, `PACK_AUTHORING.md`, `DIRECTIVE_AMEND_FLOW.md`, `SUBAGENT_ATTESTATION.md`, `PACK_VERBS.md`) link to it rather than re-listing signatures, and this receipt explicitly leaves duplicate inline source-path examples untouched in favor of the single canonical line in `LIB_API.md` — no duplication into a consumer layer.

This `## Layer boundaries` verdict was re-derived by a fresh-context sub-agent handed only the staged diff (`git diff --cached`) and the `## Layer map` section of `ARCHITECTURE.md`; it returned PASS on all three dimensions.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-c594b53d-954-1781704133-1 | claude-code | c594b53d-954e-457f-b804-476378ea9dd1 | #319 | claude-opus-4-8 | 30915 | 413054 | 16751546 | 164267 | 608236 | 15.2186 | 30915 | 413054 | 16751546 | 164267 |  |

# Receipt: unify doc surfaces and fold docs pack into foundation

## Checklist

- [x] Remove the doc-freshness directive
- [x] Fold internal-doc-links into the foundation pack
- [x] Slim the README to a browsing-developer overview
- [x] Establish the kit/references vs docs-site division and fix site drift
- [x] Governance checks pass

## What changed

This is a source-`packs/` + documentation change; the dogfood `.governance/` consumed tree is untouched and catches up at the next release via the real verbs.

**Remove the doc-freshness directive.** Deleted the whole `packs/docs/directives/doc-freshness/` folder (`check.sh`, `constitution.md`, `defaults.conf`, `directive.yaml`, `evals/test.sh`) and dropped it from every preset and reference doc.

**Fold internal-doc-links into the foundation pack.** `git mv`'d the directive to `packs/foundation/directives/internal-doc-links/`, rewrote its hardcoded pack qualifier from `governance-kit/docs` to `governance-kit/foundation` (in `packs/foundation/directives/internal-doc-links/check.sh`, `packs/foundation/directives/internal-doc-links/constitution.md`, `packs/foundation/directives/internal-doc-links/defaults.conf`) and fixed the eval paths in `packs/foundation/directives/internal-doc-links/evals/test.sh`. `packs/foundation/pack.yaml` adds it to the `minimal` preset and refreshes the description; `packs/foundation/directives/internal-doc-links/directive.yaml` moved with the folder. The now-empty `docs` pack (`packs/docs/pack.yaml`) was removed. Reference docs updated to match: `kit/references/DIRECTIVES_CATALOG.md`, `kit/references/INIT_FLOW.md`, `kit/references/LOCK_SCHEMA.md`, `kit/references/PACK_AUTHORING.md`, `kit/references/PACK_VERBS.md`, `kit/references/VERSIONING.md`, and `ARCHITECTURE.md` (three bundled packs, not four).

**Slim the README to a browsing-developer overview.** `README.md` was cut from 471 to ~330 lines, keeping the pitch, get-started, bundled packs, when-to-use, and a restructured docs hub, with deep mermaid sections moved out to existing docs.

**Establish the kit/references vs docs-site division and fix site drift.** Documented the contract in `AGENTS.md` and `scripts/docs-site/README.md`: `kit/references` is the canonical spec (wins on conflict), the published `docs/` site is the human narrative. Fixed the stale doc-freshness / `governance-kit/docs` / "four packs" drift the pack removal had left on the site (`docs/guide/configuration.mdx`, `docs/guide/introduction.mdx`, `docs/guide/quickstart.mdx`) and the narrative `docs/concepts/versioning.mdx`. On `docs/concepts/versioning.mdx` also lightened the leftover pointer-bridge `<Note>` (a vestige of the pre-generation "canonical-spec / reference wins" disclaimer approach) to a plain "go deeper" link — the disclaimer tone is obsolete now that the Reference tab is generated and the "reference wins" rule lives once in `AGENTS.md`; the link to the un-rendered `VERSIONING.md`/`RELEASE_FLOW.md` specs stays.

**Generate the site Reference tab from `kit/references` (single source of truth, the openclaw `.generated` model).** Added `scripts/docs-site/gen-reference.mjs` — a manifest-driven generator that renders each Reference page from its canonical `kit/references/*.md` source: rewriting cross-links (to other generated pages → site paths, everything else → GitHub blob URLs), escaping angle brackets outside code (the renderer is markdown-it with `html:true`), and injecting a "generated from" callout. `package.json` adds `docs:gen` / `docs:gen:check` and runs generation at the front of `docs:build`; `.github/workflows/docs.yml` runs `docs:gen:check` so a stale committed page fails CI. The six pages (`docs/reference/verbs.mdx`, `docs/reference/schemas.mdx`, `docs/reference/authoring-directives.mdx`, `docs/reference/authoring-packs.mdx`, `docs/reference/native-tests.mdx`, `docs/reference/directive-catalog.mdx`) are now generated, replacing the hand-authored copies; `scripts/docs-site/README.md` and `AGENTS.md` record that the Reference tab is generated and must be edited at the `kit/references` source.

## Decisions

- Folded `internal-doc-links` into `foundation` (not `audit`) per the maintainer's choice — it sits with `required-docs`, the existing doc-graph health check, and `foundation` is the always-installed base pack.
- Bridged the two doc surfaces by **generating the site Reference tab from `kit/references`** (openclaw's `.generated` model) rather than hand-maintaining canonical-spec pointers — generation makes drift structurally impossible, where pointers only flag it. Committed the generated output (visible in review, complete on GitHub) with a CI staleness guard, rather than gitignoring it. Retired the `kit/references/CONCEPTS.md` added mid-session once it became clear narrative belongs on the site.
- Editing `.github/workflows/docs.yml` to add the staleness check is a deliberate CI-config change (carries a `governance: allow-toolchain-config` waiver) — it is the place a stale generated page must be caught.
- Source `packs/` only for the pack change; the consumed `.governance/` tree and `CONSTITUTION.md` are not hand-edited (they catch up at release).

## Out of scope

- No release or version bump (`pack.yaml`/`kit.yaml` versions untouched — release-only per policy); the consumed `.governance/` tree is unchanged.
- The deeper chain `kit/references/DIRECTIVES_CATALOG.md` ← per-directive `packs/*/directives/*/{directive.yaml,constitution.md}` is not collapsed: the site catalog is generated from `DIRECTIVES_CATALOG.md`, but that kit file is still hand-maintained from the per-directive folders (a separate single-sourcing job, and it ships in the kit). Flagged as a follow-up.
- No new site pages for the kit-only specs (sub-agent attestation, sweep) — flagged as optional follow-ups.

## Verification

```sh
bash scripts/test-packs.sh          # 3 packs, 15 directives, 15 evals pass
bash .governance/run.sh             # dogfood suite: all 17 directives pass
npm install --no-audit --no-fund
npm run docs:gen:check              # site Reference tab is in sync with kit/references
DOCS_SITE_BASE_PATH=/governance-kit DOCS_SITE_CANONICAL_ORIGIN=https://duaility.github.io/governance-kit npm run docs:build && npm run docs:smoke
grep -rIn "doc-freshness\|governance-kit/docs\|four bundled\|four concern" docs/ kit/references packs README.md ARCHITECTURE.md | grep -v /assets/   # no stale refs
```

Governance checks pass.

## Audit

PASS - Verified against the full PR diff: doc-freshness fully deleted (5 files + `packs/docs/pack.yaml`, all `deleted file mode`); internal-doc-links renamed to `packs/foundation/` with every `governance-kit/docs`→`governance-kit/foundation` qualifier rewrite and added to the `minimal` preset (`foundation/pack.yaml`, version untouched); README cut 471→328 lines; the six Reference `.mdx` pages are genuinely generated by the new `scripts/docs-site/gen-reference.mjs` (each carries the "generated from" callout + `<!-- GENERATED FILE -->` header), wired into `package.json` `docs:gen`/`docs:gen:check` + `docs:build` and the `.github/workflows/docs.yml` `docs:gen:check` CI step. All 5 `- [x]` items are realized, `## Checklist` mirrors issue #309 verbatim, every changed file is named in the receipt, and the stale-ref grep returns clean.

## Layer boundaries

PASS - Every file sits in its owning layer: the generator and its README under `scripts/docs-site/`, the generated pages under `docs/reference/*.mdx` each stamped `<!-- GENERATED FILE — do not edit. Sources: kit/references/... -->`, spec edits confined to `kit/references/*.md`, the doc-freshness deletion and the internal-doc-links git-mv from `packs/docs/` to `packs/foundation/` touching pack source only, and zero hits under `.governance/` (consumed tree untouched, defers to release); no kit/engine logic landed in a pack. The only cross-layer dependency is `scripts/docs-site/gen-reference.mjs` reading `kit/references` as a content source to render `docs/` — a downstream docs→kit edge that respects the skill→kit→packs downward-only model, with the spec single-sourced in `kit/references` and rendered (not duplicated) into `docs/`, enforced against drift by `docs:gen:check` in `docs.yml`.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-fc0f8c09-11a-1781687306-1 | claude-code | fc0f8c09-11a6-476c-b2b1-c6e2e0db8d10 | #309 | claude-opus-4-8 | 7006 | 34930 | 30540 | 772 | 42708 | 0.2879 | 7006 | 34930 | 30540 | 772 | refactor(docs): unify doc surfaces and fold docs pack into foundation (#309) -m  |
| claude-code-658b7d9a-a58-1781688879-1 | claude-code | 658b7d9a-a584-4c7f-81d7-62015d7d2281 | #309 | claude-opus-4-8 | 6732 | 34460 | 30540 | 1042 | 42234 | 0.2904 | 6732 | 34460 | 30540 | 1042 | docs(site): generate the reference tab from kit/references (#309) -m Make the do |
| claude-code-1bb39549-863-1781689026-1 | claude-code | 1bb39549-8637-40c8-b1ad-2e4c5d40ce90 | #309 | claude-opus-4-8 | 65190 | 1712546 | 82343174 | 531227 | 2308963 | 65.4816 | 65190 | 1712546 | 82343174 | 531227 | docs(site): generate the reference tab from kit/references (#309) -m Make the do |
| claude-code-7cf48312-343-1781690637-1 | claude-code | 7cf48312-3431-437c-8d97-9ca0d2413f2d | #309 | claude-opus-4-8 | 11768 | 35768 | 30540 | 972 | 48508 | 0.3220 | 11768 | 35768 | 30540 | 972 | docs(site): lighten the versioning page's canonical-spec note (#309) -m The pre- |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-1bb39549863-1781688879-1 | 1bb39549-8637-40c8-b1ad-2e4c5d40ce90 | #309 | interrupt | structural |  | docs(site): generate the reference tab from kit/references (#309) -m Make the d… | 1 | 2026-06-17T09:17:58.851Z |
| steer-1bb39549863-1781688879-2 | 1bb39549-8637-40c8-b1ad-2e4c5d40ce90 | #309 | correction | classifier | scope too narrow — missed md files outside kit/references | docs(site): generate the reference tab from kit/references (#309) -m Make the d… | 2 | 2026-06-17T09:18:18.310Z |
| steer-1bb39549863-1781688879-3 | 1bb39549-8637-40c8-b1ad-2e4c5d40ce90 | #309 | interrupt | structural |  | docs(site): generate the reference tab from kit/references (#309) -m Make the d… | 3 | 2026-06-17T09:22:55.714Z |

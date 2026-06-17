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

**Establish the kit/references vs docs-site division and fix site drift.** Documented the contract in `AGENTS.md` and `scripts/docs-site/README.md`: `kit/references` is the canonical spec (wins on conflict), the published `docs/` site is the human narrative. Added a "Canonical spec" pointer to each duplicating site page (`docs/reference/verbs.mdx`, `docs/reference/schemas.mdx`, `docs/reference/authoring-directives.mdx`, `docs/reference/authoring-packs.mdx`, `docs/reference/native-tests.mdx`, `docs/reference/directive-catalog.mdx`, `docs/concepts/versioning.mdx`) and fixed the stale doc-freshness / `governance-kit/docs` / "four packs" drift the pack removal had left on the site (`docs/guide/configuration.mdx`, `docs/guide/introduction.mdx`, `docs/guide/quickstart.mdx`, and the rewritten `docs/reference/directive-catalog.mdx`).

## Decisions

- Folded `internal-doc-links` into `foundation` (not `audit`) per the maintainer's choice — it sits with `required-docs`, the existing doc-graph health check, and `foundation` is the always-installed base pack.
- Bridged the two doc surfaces by **division of responsibility plus canonical-spec pointers**, not by deleting the site's rendered reference pages — the banner + documented contract resolves the "which is right?" ambiguity without vandalizing a live site, and is reversible. Retired the `kit/references/CONCEPTS.md` added mid-session once it became clear narrative belongs on the site.
- Source `packs/` only; the consumed `.governance/` tree and `CONSTITUTION.md` are not hand-edited (they catch up at release).

## Out of scope

- No release or version bump (`pack.yaml`/`kit.yaml` versions untouched — release-only per policy); the consumed `.governance/` tree is unchanged.
- No deeper prose de-duplication of the (now-correct) site reference pages beyond the canonical-spec pointers, and no new site pages for the kit-only specs (sub-agent attestation, sweep) — flagged as optional follow-ups.
- No audit of unrelated pre-existing site drift beyond the directive-catalog page already rewritten here.

## Verification

```sh
bash scripts/test-packs.sh          # 3 packs, 15 directives, 15 evals pass
bash .governance/run.sh             # dogfood suite: all 17 directives pass
npm install --no-audit --no-fund && DOCS_SITE_BASE_PATH=/governance-kit DOCS_SITE_CANONICAL_ORIGIN=https://duaility.github.io/governance-kit npm run docs:build && npm run docs:smoke
grep -rIn "doc-freshness\|governance-kit/docs\|four bundled\|four concern" docs/ kit/references packs README.md ARCHITECTURE.md | grep -v /assets/   # no stale refs
```

Governance checks pass.

## Audit

PASS - Receipt faithfully matches the diff. All 5 `- [x]` items are realized: doc-freshness fully deleted (`check.sh`/`constitution.md`/`defaults.conf`/`directive.yaml`/`evals/test.sh` + `packs/docs/pack.yaml`); internal-doc-links renamed to `packs/foundation/` with the `governance-kit/docs`→`/foundation` qualifier rewrite and added to the `minimal` preset; README cut to ~328 lines; the two-surface contract added to `AGENTS.md` + `scripts/docs-site/README.md` with "Canonical spec" `<Note>` callouts on all 7 named site pages, and the four→three-pack / doc-freshness drift fixed across `docs/` and `kit/references`. The `## Checklist` mirrors issue #309's checklist verbatim, every changed file in the diffstat is named in the receipt, and a grep for stale `doc-freshness` / `governance-kit/docs` / "four packs" refs returns clean.

## Layer boundaries

PASS - Checked all changed files: pack SOURCE edits (delete `packs/docs/`, `git mv` internal-doc-links into `packs/foundation/`, `foundation/pack.yaml`) stay in `packs/`; spec/flow updates stay in `kit/references/*.md`; site narrative and canonical-spec pointers stay in `docs/*.mdx` + `scripts/docs-site/README.md`; root-doc and receipt edits sit in their own layers; the consumed `.governance/` tree is untouched (defers to release). All dependency edges point downward — the relocated `check.sh` self-references its new `governance-kit/foundation` home and consumes the kit-owned `lib.sh`/`eval-lib.sh` under `kit/assets/packs/lib/`, with no pack reaching up into skill or kit-engine internals. The doc-surface division is authored once in `AGENTS.md`/`scripts/docs-site/README.md` and linked, not duplicated as a parallel spec.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-fc0f8c09-11a-1781687306-1 | claude-code | fc0f8c09-11a6-476c-b2b1-c6e2e0db8d10 | #309 | claude-opus-4-8 | 7006 | 34930 | 30540 | 772 | 42708 | 0.2879 | 7006 | 34930 | 30540 | 772 | refactor(docs): unify doc surfaces and fold docs pack into foundation (#309) -m  |

# Receipt — issue #323

Refresh the published docs site (`docs/`) so it matches the current kit after the last few releases and reads in the README's developer-to-developer voice — the README being the tonal reference point. The work is in three layers: correct the factual drift (retired accounting trailers, the folded-in `docs` pack, dropped preset directives), align the lead framing and vocabulary to the README (harness-engineering, "locally fine and globally wrong", the depth ladder), and reuse the README's diagrams instead of redrawing them. Every fact was checked against the live kit (`packs/*/pack.yaml`, the audit directives' `constitution.md`, `.governance/install.yaml`) before editing. The generated `docs/reference/*.mdx` pages were deliberately left alone — they regenerate from `kit/references` and were already current.

## Checklist

- [x] Correct the factual drift: remove the retired accounting commit trailers, fix the folded-in `docs` pack, and drop the preset directives that no longer exist.
- [x] Lead the docs with the README's harness-engineering framing and import the "locally fine and globally wrong" hook and the four-level depth ladder.
- [x] Reuse the README's diagrams: the harness-loop mermaid on the landing page and the designed lifecycle SVG embedded on the docs site.
- [x] Keep the governance suite green — `internal-doc-links` passes and no stale trailer or dead-pack references remain in the narrative pages.

## What changed

- **Correct the factual drift: remove the retired accounting commit trailers, fix the folded-in `docs` pack, and drop the preset directives that no longer exist.** — `docs/concepts/audit-chain.mdx` is rewritten off the trailer model (#293/#294): the mermaid, the link table, the cost section (now the v4 `cum-*` row + the frozen-token-endpoint reconciliation), the steering section (v2 row, identity dedup), and "reading the record" no longer mention `Token-Total`/`Cost-Key`/`Steer-Count`; `commit-issue-receipt-match` is described file-first. The same correction propagated to `docs/concepts/runtime.mdx` (the populator step now *writes the cost row + freezes the endpoint*, and the Mode-B list drops "accounting trailers"), `docs/concepts/limitations.mdx` (dropped the stale "squash must keep commit bodies" constraint), and `docs/guide/troubleshooting.mdx` (the `agent-token-accounting` failure row). `docs/concepts/packs.mdx` drops the dead `docs` pack from the bundled list (`{foundation,commits,audit}`), and `docs/concepts/versioning.mdx` replaces the `docs/v0.2.0` tag and `release.sh docs` examples with live packs. `docs/guide/quickstart.mdx`'s preset table no longer names "kit-version sync" / "doc freshness".
- **Lead the docs with the README's harness-engineering framing and import the "locally fine and globally wrong" hook and the four-level depth ladder.** — `docs/guide/introduction.mdx` is reworked so harness-engineering is the lead lens (reconciliation reframed as the "under the hood" mechanism), opens "What problem does it solve?" with the README's "locally fine and globally wrong" hook, and adds a new "How deep can a rule go?" section carrying the four-level depth ladder (repo-state → change-set → ledger → sub-agent attestation). `docs/index.mdx`'s lead and "How does it work?" now lead with executable-rails/harness-engineering and the repo-memory hook. `docs/guide/mental-models.mdx`'s opening ties the whole page to the harness-engineering stance and drops the academic "internalize" phrasing.
- **Reuse the README's diagrams: the harness-loop mermaid on the landing page and the designed lifecycle SVG embedded on the docs site.** — `docs/index.mdx`'s hero diagram is now the README's harness-loop mermaid copied verbatim (Human→Pack→Gate→Agent→Record with the colored `classDef`s and the "next agent reads" feedback edge), and its surrounding prose was adjusted so the words match the diagram. `docs/guide/mental-models.mdx`'s second diagram (the installer/product/content model) is now the designed `docs/assets/lifecycle-light.svg` / `lifecycle-dark.svg` embedded via Mintlify's `block dark:hidden` / `hidden dark:block` light/dark pattern inside a `<Frame>`, replacing the hand-drawn mermaid; the purpose-built reconciliation mermaid (mental-models #1) and the audit-chain mermaid are kept.
- **Keep the governance suite green — `internal-doc-links` passes and no stale trailer or dead-pack references remain in the narrative pages.** — verified by grep sweeps over the narrative pages (no `Token-Total`/`Cost-Key`/`Steer-Count`/`governance-kit/docs`/`doc freshness` survivors) and by running the dead-link directive; brand prose stays "Governance Kit". The full set of changed files is `docs/index.mdx`, `docs/guide/introduction.mdx`, `docs/guide/mental-models.mdx`, `docs/guide/quickstart.mdx`, `docs/guide/troubleshooting.mdx`, `docs/concepts/audit-chain.mdx`, `docs/concepts/limitations.mdx`, `docs/concepts/packs.mdx`, `docs/concepts/runtime.mdx`, and `docs/concepts/versioning.mdx`.

## Out of scope

- `docs/reference/*.mdx` (verbs, directive-catalog, schemas, native-tests, authoring-directives, authoring-packs) — generated from `kit/references/*.md` by `scripts/docs-site/gen-reference.mjs`; they were already current (the catalog already states "no commit trailers, #293") and editing them by hand would break `docs:gen:check`.
- `kit/references/*.md`, `README.md`, `CONSTITUTION.md`, `.governance/` — not a docs-site refresh; untouched.
- `ARCHITECTURE.md`'s mermaid (a third rendering of the installer/product/content model, slightly drifted) — a repo-internal doc, not a docs-site page; left for a separate change.

## Verification

Docs-only change. The dead-link directive passes and no stale references survive the grep sweeps:

```sh
bash .governance/run.sh internal-doc-links        # ✓ internal-doc-links
# no retired-trailer / dead-pack / dropped-directive strings remain in the narrative:
grep -rniE 'Token-Total|Cost-Key|Steer-Count|governance-kit/docs|docs/v0|doc freshness|kit-version sync' \
  docs/index.mdx docs/guide/*.mdx docs/concepts/*.mdx
# both reused SVG variants exist and are tracked:
git ls-files docs/assets/lifecycle-light.svg docs/assets/lifecycle-dark.svg
# the README harness loop is on the landing page; mental-models #2 is now the SVG:
grep -c '```mermaid' docs/index.mdx docs/guide/mental-models.mdx
```

The grep sweep returns no matches in the narrative pages (the only `prepare-commit-msg` hits are the legitimate hook-kind enum and dispatcher list). `docs/index.mdx` carries one mermaid (the harness loop); `docs/guide/mental-models.mdx` carries one mermaid (the kept reconciliation diagram), its installer/product/content diagram now the embedded SVG.

## Decisions

- **Harness-engineering leads, reconciliation supports.** The docs led with the Kubernetes/Terraform reconciliation metaphor, which the README never uses; the README leads with harness-engineering. Rather than drop reconciliation (it is accurate and is the right diagram for `mental-models` #1), it was demoted to the "under the hood" mechanism and harness-engineering made the headline lens, so a reader moving README → site meets one stance, not two.
- **Reuse the designed SVG over the hand-drawn mermaid.** The polished `lifecycle-*.svg` lived in `docs/assets/` but was embedded only by the README; the docs redrew the same idea as a lower-fidelity mermaid. The SVG is embedded via Mintlify's class-based `dark:hidden` pattern (not the README's `<picture>`/`prefers-color-scheme`, which tracks the OS theme rather than Mintlify's in-app toggle). User chose "reuse README's assets" over aligning the mermaids.
- **Anchored headers preserved.** Four headers are cross-link anchor targets (`mental-models#2-an-installer-a-product-its-content`, `packs#presets`, `packs#update-vs-reset`, `quickstart#choosing-a-preset`); their text was kept verbatim so no intra-site link breaks.
- **Backing issue created for the flow.** This refresh started from a user request, not a pre-existing issue; issue #323 was opened to satisfy the repo's issue → receipt → commit chain.

## Audit

PASS

- PASS — Every one of the 10 staged non-receipt files is named in `## What changed` and each narrated claim matches the hunks: `audit-chain.mdx` drops `Token-Total`/`Cost-Key`/`Steer-Count` and reframes `commit-issue-receipt-match` file-first, `packs.mdx` changes the bundled list to `{foundation,commits,audit}`, `versioning.mdx` swaps `docs/v0.2.0`→`commits/v0.2.1`, `quickstart.mdx` removes "kit-version sync"/"doc freshness", `index.mdx` replaces the reconciliation hero with the README harness-loop mermaid, and `mental-models.mdx` #2 becomes the embedded `lifecycle-light/dark.svg` while keeping reconciliation mermaid #1.
- PASS — All four `- [x]` boxes are realized in the diff and crosswalk into `## What changed` / `## Verification`: trailers removed (audit-chain/runtime/limitations/troubleshooting hunks), README framing + depth-ladder added (`introduction.mdx` "How deep can a rule go?" table, mental-models harness lead, index lead), both SVG variants tracked via `git ls-files`, and the green-suite box backed by index/mental-models each carrying exactly one mermaid with no retired-trailer survivors.
- PASS — The `## Checklist` covers every issue #323 proposed-fix item (factual drift; harness framing + "locally fine and globally wrong" + depth ladder; reuse harness mermaid + lifecycle SVG) and both acceptance criteria (no stale refs; landing + mental-models reuse the diagrams; `internal-doc-links` green), with the reference-page edits correctly excluded per the issue's stated out-of-scope.

This `## Audit` verdict was produced by a fresh-context sub-agent handed only the staged diff (`git diff --cached`), this receipt, and `gh issue view 323`; it confirmed PASS on all three dimensions.

## Layer boundaries

PASS

- PASS — Every staged file sits in its correct surface: all 10 changed files are narrative pages under `docs/{index,guide,concepts}/*.mdx` (the published-site layer) and the one new file is `receipts/issue-323-docs-site-refresh.md` (the ledger layer); no `skill/`, `kit/`, `packs/`, or `.governance/` source was touched, confirmed by `git diff --cached --name-only | grep -vE '^(docs/|receipts/)'` returning nothing.
- PASS — No dependency crosses a layer edge the wrong way: the docs pages only *describe* lower layers and link sideways within the site (e.g. `mental-models.mdx` embeds the pre-existing `docs/assets/lifecycle-*.svg` and links to `/concepts/versioning`), introducing no code-level import or upward reference from `docs/` / `receipts/` into `skill` / `kit` / `packs`.
- PASS — No shared logic is duplicated into a consumer layer: the changes are prose/diagram edits that single-source from the lower layers rather than re-implementing them (the receipt leaves generated `docs/reference/*.mdx` untouched because they regenerate from `kit/references`, and the mental-models lifecycle diagram reuses the existing designed SVG instead of redrawing the kit's architecture).

This `## Layer boundaries` verdict was produced by a fresh-context sub-agent handed only the staged diff and the layer model in `ARCHITECTURE.md`; it confirmed PASS on all three dimensions.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-411c3220-7bb-1781709298-1 | claude-code | 411c3220-7bb7-4fee-a87e-ebb816937323 | #323 | claude-opus-4-8 | 25008 | 34592 | 30540 | 654 | 60254 | 0.3729 | 25008 | 34592 | 30540 | 654 | docs: refresh the published docs site to match recent releases and the README (# |

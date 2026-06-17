# Issue 303: Tighten README messaging and replace lifecycle diagram with SVG

Closes [#303](https://github.com/Duaility/governance-kit/issues/303).

## Checklist

- [x] Reframe the opening around the real failure mode.
- [x] Introduce receipts as the accountability pillar in the core idea.
- [x] Lead the tagline on coherence and trim the slice and redundant value-prop bullets.
- [x] Reword the audit-chain section and simplify its diagram.
- [x] Replace the Lifecycle mermaid with theme-aware committed SVG variants.
- [x] Verify the governance suite passes.

## What changed

**Reframe the opening around the real failure mode.** `README.md`'s core idea no longer opens with a four-anecdote story. It now states the failure crisply — the agent completes the task "in a way that's locally fine and globally wrong" — then names three distinct failure modes (architecture drift; half-following the constraints written into `AGENTS.md`/`CLAUDE.md`, missing the ones that matter or optimizing for the wrong ones; the next agent losing the correction across sessions) and the backfiring reflex of piling more rules into a bloated instruction file ("More instructions buy less control").

**Introduce receipts as the accountability pillar in the core idea.** `README.md` now pairs invariants ("keep the work coherent") with receipts ("keep it accountable") in the core idea, explaining that what an agent changed, cost, and was corrected on would otherwise disappear when the session ends — so the kit pins it to the issue as a receipt in git. This earns the downstream audit-chain section.

**Lead the tagline on coherence and trim the slice and redundant value-prop bullets.** The header tagline in `README.md` now leads with "keep every agent coherent with your repo." The two "define the slice"/"keep the diff inside that slice" bullets (capabilities the kit does not enforce) were removed, the example list was reordered coherence-first, and the two "What developers get" bullets that merely restated the core idea ("Less repeated steering", "Shared behavior across agents") were cut.

**Reword the audit-chain section and simplify its diagram.** The `## The audit chain` intro in `README.md` was rewritten to build on the new receipts framing (the receipt is trustworthy because it sits in an enforced chain and its cost/steering rows reconcile against the transcript) instead of re-explaining what a receipt is. Its mermaid diagram was reduced from three subgraphs and seven labeled cross-edges to a linear `Issue → receipt → commit → push` spine with a single dashed transcript feeder; the duplicate reconciliation clause was dropped from the Token-cost bullet.

**Replace the Lifecycle mermaid with theme-aware committed SVG variants.** The Lifecycle mermaid block (and its now-redundant lead-in sentence) in `README.md` was replaced with a centered `<picture>` referencing two new assets, `docs/assets/lifecycle-light.svg` and `docs/assets/lifecycle-dark.svg`, that switch on `prefers-color-scheme` exactly like the banner. The variants share an identical layout and tier colors and differ only in their neutral grays.

**Verify the governance suite passes.** `bash .governance/run.sh` was run after the edits.

## Out of scope

- Any change to the kit engine, packs, or directive behavior.
- The consumed `.governance/` tree, release metadata, or version markers.
- New README sections beyond the messaging and diagram changes above.

## Decisions

- The lifecycle diagram was rendered as a committed SVG (with light/dark variants via `<picture>`) rather than refined mermaid, because mermaid's auto-layout cannot guarantee the clean two-column block alignment across renderers; the trade is that label changes now require regenerating the SVG. The other (flow) mermaid diagrams were left in place where exact layout does not matter.

## Verification

```sh
bash .governance/run.sh
```

Result: all directives passed.

## Audit

PASS - The only product-facing file changed is `README.md`; the change also adds two SVG assets under `docs/assets/` and this receipt under `receipts/`. The receipt's checklist mirrors the issue, every checked item crosswalks into a bold heading under `## What changed`, and every changed path (`README.md`, `docs/assets/lifecycle-light.svg`, `docs/assets/lifecycle-dark.svg`) is named. The claims describe copy edits and a mermaid-to-SVG swap that match the diff.

## Layer boundaries

PASS - The diff touches only the documentation/audit layer: `README.md` copy, two presentational SVG assets under `docs/assets/`, and this receipt under `receipts/`. No kit engine logic, pack directive code, runtime files, or consumed `.governance/` tree were added, moved, or modified. No shared logic was introduced or duplicated and no cross-layer dependency was created.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-e50a46d6-f96-1781674354-1 | claude-code | e50a46d6-f96c-4520-a835-f8b11c02a3c2 | #303 | claude-opus-4-8 | 71846 | 1714654 | 23179821 | 440535 | 2227035 | 33.6791 | 71846 | 1714654 | 23179821 | 440535 | docs(readme): tighten messaging and replace lifecycle diagram with SVG (#303) -m |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-e50a46d6f96-1781674353-1 | e50a46d6-f96c-4520-a835-f8b11c02a3c2 | #303 | correction | classifier | Wanted opening point sharper and reframed more generically across whole README | docs(readme): tighten messaging and replace lifecycle diagram with SVG (#303) -… | 1 | 2026-06-16T18:17:04.238Z |
| steer-e50a46d6f96-1781674353-2 | e50a46d6-f96c-4520-a835-f8b11c02a3c2 | #303 | correction | classifier | Asked to undo the harness-engineering blockquote change | docs(readme): tighten messaging and replace lifecycle diagram with SVG (#303) -… | 2 | 2026-06-17T04:52:02.302Z |
| steer-e50a46d6f96-1781674353-3 | e50a46d6-f96c-4520-a835-f8b11c02a3c2 | #303 | correction | classifier | Rejected lifecycle diagram; wanted a simple block diagram instead | docs(readme): tighten messaging and replace lifecycle diagram with SVG (#303) -… | 3 | 2026-06-17T05:11:24.438Z |
| steer-e50a46d6f96-1781674353-4 | e50a46d6-f96c-4520-a835-f8b11c02a3c2 | #303 | correction | classifier | Said the audit-chain diagram was too complex; wanted it simplified | docs(readme): tighten messaging and replace lifecycle diagram with SVG (#303) -… | 4 | 2026-06-17T05:21:31.888Z |

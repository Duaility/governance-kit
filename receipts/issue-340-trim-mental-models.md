## Checklist

- [x] Cut the mental-models page from eight models to four core models
- [x] Fold the demoted four models into a "mechanics that follow" table
- [x] Reuse the README brand-colored loop diagram for model #1
- [x] Add a hand-authored rule-layer SVG pair, light and dark
- [x] Recolor the rule-layer SVG accent from olive to brand teal

## What changed

- `docs/guide/mental-models.mdx`: Cut the mental-models page from eight models
  to four core models (reconciliation loop, rule-and-test as one artifact,
  rule-layer steering, durable receipts). Fold the demoted four models into a
  "mechanics that follow" table, trimming ~22% of the prose. Reuse the README
  brand-colored loop diagram for model #1 instead of the page's own uncolored
  duplicate, and apply the same brand palette to the rule=test and audit-chain
  mermaid diagrams.
- `docs/assets/rule-layer-light.svg`, `docs/assets/rule-layer-dark.svg`: Add a
  hand-authored rule-layer SVG pair, light and dark (turn layer vs rule layer),
  style-matched to the existing `lifecycle-*.svg` assets and referenced by the
  page's `<Frame>`. A follow-up review then found the pair painted the
  CONSTITUTION.md / rule-layer accent in an olive-green family that appears
  nowhere else in the kit; recolor the rule-layer SVG accent from olive to
  brand teal (`#075b4a` / `#36d6af` / `#dcfff4`) — box fill, stroke, inner
  text, and the "THE RULE LAYER" header — so the directive/constitution concept
  reads as one color across the page (matching the `lifecycle-*.svg` assets and
  the page's own mermaid diagrams).

## Out of scope

- Removing `lifecycle-*.svg` — still referenced by the README, so the page no
  longer embedding it does not orphan it.
- The loop mermaid is now intentionally duplicated between the README and this
  page; deduplicating it (single-sourcing) is deferred — edit both if it
  changes.
- No copy or structural changes beyond the trim and the visual swaps; the
  recolor is hex-values only (no layout or text change).

## Decisions

- The olive → teal recolor was a reviewer steering call made *after* the
  original trim commit, which shipped the olive palette. It is folded into this
  same PR/receipt rather than a separate issue because it is the same change
  surface (the rule-layer SVG pair authored here).
- `is_accounting_stub` exempted the original slugless `receipts/issue-340.md`
  from the slug + section + audit rules, so the PR was green with only a
  hook-minted stub. Fleshing the receipt out here (slug + narrative + this
  `## Audit`) is the deliberate graduation that makes the receipt discipline
  actually bind. The structural gap — that nothing forces a substantive change
  set's receipt to graduate from a stub — is filed separately as a
  graduation-gate directive proposal.
- `AGENT_ISSUE='#340'` was required for the recolor commit because the
  accounting populator did not auto-infer the `(#340)` anchor from the subject
  on that run.

## Verification

```sh
# docs site builds and smoke-checks clean
npm run docs:build && npm run docs:smoke

# both rule-layer SVGs are well-formed XML
xmllint --noout docs/assets/rule-layer-light.svg docs/assets/rule-layer-dark.svg

# no olive/lime accent remains; teal is in place
grep -nE '#5f6b10|#5d6810|#aeb84a|#f6f8df|#c3cf5a' docs/assets/rule-layer-*.svg   # → no matches
grep -c '#075b4a' docs/assets/rule-layer-light.svg docs/assets/rule-layer-dark.svg

# full governance suite passes for this repo
bash .governance/run.sh
```

Both SVGs were also rendered (`qlmanage -t`) in light and dark and visually
confirmed: the CONSTITUTION.md box and "THE RULE LAYER" header now read brand
teal, matching the lifecycle assets and the page's mermaid diagrams.

## Audit

Fresh-context sub-agent (low tier) audited this receipt against the change-set
diff and issue #340:

- **Check 1 (What changed faithful to diff):** PASS — the `## What changed`
  section accurately describes both changed surfaces: the consolidation of
  `docs/guide/mental-models.mdx` from eight to four models with the new
  mechanics table, and the two new `rule-layer-*.svg` assets with their
  olive→teal recolor. No materially changed file is omitted.
- **Check 2 (each checked item realized in the diff):** PASS — all five
  `- [x]` items are demonstrated in the diff: the page cuts to four models,
  folds the rest into a "mechanics that follow" table, reuses the README
  brand-colored loop mermaid, adds both rule-layer SVGs, and paints the
  rule-layer accent brand teal (`#075b4a` / `#36d6af` / `#dcfff4`).
- **Check 3 (Checklist mirrors the issue):** PASS — items 1–4 map directly to
  issue #340's four scoped points; item 5 (olive→teal recolor) is recorded in
  `## Decisions` as a reviewer steering refinement on the same change surface,
  an appropriate fold-in of post-commit feedback rather than scope creep.

## Layer boundaries

Fresh-context sub-agent layer audit against `ARCHITECTURE.md`:

- PASS — `docs/guide/mental-models.mdx` is a narrative page on the docs site
  (`docs/`), orthogonal to the skill → kit → packs layer map and carrying no
  executable logic.
- PASS — `docs/assets/rule-layer-light.svg` and `rule-layer-dark.svg` are docs
  image assets, not part of the executable skill/kit/packs hierarchy, and
  introduce no cross-layer dependencies.
- PASS — `receipts/issue-340-trim-mental-models.md` is a receipt
  (system-of-record), orthogonal to the layer diagram and consistent with the
  audit infrastructure; no shared logic is duplicated into a consumer layer.

## Steering

Fresh-context sub-agent review of the session transcript:

- PASS — The one course-shaping input — the user's push on receipt slug naming
  ("while it is creating issue-N.md why not just add full slug") — is faithfully
  captured in `## Decisions`, which records the acknowledged structural gap and
  defers it to a separate graduation-gate directive proposal rather than
  scope-creeping into this change. The remaining user messages were clarifying
  questions and approvals, not course corrections, so no further `### Steering`
  rows are warranted.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-b5194b37-28b-1781843663-1 | claude-code | b5194b37-28b2-4331-a444-51ead4f25789 | #340 | claude-opus-4-8 | 30368 | 412708 | 8735094 | 125935 | 569011 | 10.2472 | 30368 | 412708 | 8735094 | 125935 | docs(guide): trim mental models to four core ideas + visuals (#340)Cut the menta |
| claude-code-3e7fe78f-b6d-1781844612-1 | claude-code | 3e7fe78f-b6d4-4568-913d-683993d54648 | #340 | claude-opus-4-8 | 29379 | 173528 | 4539442 | 44499 | 247406 | 4.6136 | 29379 | 173528 | 4539442 | 44499 |  |
| claude-code-cd5cbba8-574-1781847242-1 | claude-code | cd5cbba8-5746-4b05-8836-6377cc052d46 | #340 | claude-opus-4-8 | 62100 | 660593 | 20160466 | 218835 | 941528 | 19.9903 | 62100 | 660593 | 20160466 | 218835 |  |

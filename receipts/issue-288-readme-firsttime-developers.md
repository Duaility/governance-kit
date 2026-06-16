## Checklist

- [x] Reframed the README around the first-time developer perspective for coding-agent-heavy repos
- [x] Improved the README Mermaid diagrams for the governance loop, audit chain, sweep lane, and lifecycle model
- [x] Removed stale README details about bundled packs, directive counts, and release examples
- [x] Added the invariant ladder showing repo-state, change-set, ledger, sub-agent, and sweep-depth rules
- [x] Made custom governance packs first-class in the README narrative
- [x] Explained sub-agent attestations as semantic checks without pretending bash is smart
- [x] Simplified the sub-agent attestation diagram to the essential remediation loop
- [x] Tweaked the lifecycle Mermaid diagram to match the compact language-toolchain reference layout

## What changed

- Reframed the README around the first-time developer perspective for
  coding-agent-heavy repos: `README.md` now opens with the core idea that
  Governance Kit turns repeated instructions to agents into repo-native
  invariants.
- `README.md` adds a compact "What developers get" section that maps the kit's
  concrete pieces (`CONSTITUTION.md`, directive folders, packs, gates, audit
  chain, and sweep lane) to the evaluation questions a first-time reader is
  likely to ask.
- Improved the README Mermaid diagrams for the governance loop, audit chain,
  sweep lane, and lifecycle model: `README.md` replaces the four diagrams with
  clearer grouped diagrams that show pass/fail paths, audit joins, the
  off-commit-path sweep, and the skill/kit/pack/repo pin relationship.
- Removed stale README details about bundled packs, directive counts, and
  release examples: `README.md` removes stale security-pack rows from the
  bundled directive table, corrects the dogfood check count to 17 synchronous
  directive checks, updates the top navigation anchor, and uses an actual
  bundled pack in the release example.
- Added the invariant ladder showing repo-state, change-set, ledger, sub-agent,
  and sweep-depth rules: `README.md` now names the depth of invariants users can
  express and gives concrete examples for each enforcement surface.
- Made custom governance packs first-class in the README narrative:
  `README.md` now explains packs as portable bundles of invariants and gives
  example organization-specific packs such as platform, security, migration,
  and mobile packs.
- Explained sub-agent attestations as semantic checks without pretending bash is
  smart: `README.md` now describes the remediation loop where a failing hook
  prompts a harness agent to spawn a fresh-context auditor and record a
  PASS/REFUTED section.
- Simplified the sub-agent attestation diagram to the essential remediation
  loop: `README.md` now shows the missing-attestation failure, generated audit
  prompt, fresh-context review, recorded verdict, and retry pass as one compact
  left-to-right flow.
- Tweaked the lifecycle Mermaid diagram to match the compact language-toolchain
  reference layout: `README.md` now renders the skill, kit, and packs as a
  stacked left column, their rustup/toolchain/lockfile analogies as a right
  column, and the repo version pins as a full-width footer with a color legend.

## Out of scope

- No kit behavior, directive implementation, release tooling, or vendored
  `.governance/` content changed.
- No new screenshots or generated image assets were added.

## Verification

```sh
git diff --check
```

```sh
bash .governance/run.sh
```

## Decisions

- Treated PR #288 as the issue anchor for this documentation-only repair
  because the branch was already pushed and the PR is the durable review record
  for the change.
- The original pushed commit bypassed the hook path; the repaired amend is run
  through the runtime-aware hook path so the final commit can carry real
  generated accounting trailers and receipt rows.

## Layer boundaries

PASS.

- PASS — every file added or changed sits in the layer its role belongs to.
  `README.md` is root-level public documentation, and
  `receipts/issue-288-readme-firsttime-developers.md` is the audit receipt for
  the PR branch. No kit engine logic, pack directive content, or consumed
  `.governance/` content moved layers.
- PASS — no dependency points the wrong way across a layer edge. The change is
  Markdown documentation only and introduces no code imports, shell sourcing,
  package references, or runtime dependency edges.
- PASS — no new shared logic was introduced, so there is no shared helper to
  place in a lower or higher layer.

## Audit

PASS.

- PASS — `## What changed` faithfully describes the diff. The change set edits
  `README.md` and updates this receipt; the README changes are narrative,
  invariant-ladder, custom-pack, sub-agent-attestation, diagram, stale-table,
  lifecycle-diagram-layout, count, navigation, and release-example updates.
- PASS — each checked item is realized in the diff. The README is reframed for
  first-time developers, the invariant ladder is introduced, custom packs are
  explained as portable rule bundles, sub-agent attestations get their own
  section, the sub-agent attestation diagram is simplified to the core
  remediation loop, the lifecycle Mermaid diagram now mimics the compact
  reference layout, other Mermaid diagrams are replaced or improved, and stale
  bundled-pack/count/release-example details are corrected.
- PASS — the checklist mirrors the requested work in this thread: refine the
  README for a first-time developer evaluating why Governance Kit matters for
  coding agents, explain the power/depth of invariants users can express,
  highlight custom packs, improve or replace the diagrams as needed, and adjust
  the sub-agent and lifecycle diagrams based on the provided feedback.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ecfa3-cfa-1781601741-1 | codex | 019ecfa3-cfa6-73e1-97f4-841d6359e84c | #288 | gpt-5.5 | 45250 | 0 | 2068096 | 3421 | 48671 | 0.6815 | 484743 | 0 | 6963840 | 23933 | docs(readme): refine first-time developer story (#288) |
| codex-019ecfa3-cfa-1781602730-1 | codex | 019ecfa3-cfa6-73e1-97f4-841d6359e84c | #288 | gpt-5.5 | 85333 | 0 | 5876608 | 12890 | 98223 | 1.8758 | 570076 | 0 | 12840448 | 36823 | docs(readme): refine first-time developer story (#288) |
| codex-019ecfa3-cfa-1781603802-1 | codex | 019ecfa3-cfa6-73e1-97f4-841d6359e84c | #288 | gpt-5.5 | 502803 | 0 | 4468352 | 9005 | 511808 | 2.5092 | 1072879 | 0 | 17308800 | 45828 | docs(readme): refine first-time developer story (#288) |
| codex-019ecfa3-cfa-1781604133-1 | codex | 019ecfa3-cfa6-73e1-97f4-841d6359e84c | #288 | gpt-5.5 | 224470 | 0 | 992256 | 3088 | 227558 | 0.8556 | 1297349 | 0 | 18301056 | 48916 | docs(readme): refine first-time developer story (#288) |
| codex-019ed002-48e-1781606636-1 | codex | 019ed002-48e2-7b43-892f-d2c495a89314 | #288 | gpt-5.5 | 148866 | 0 | 1396480 | 8658 | 157524 | 0.8512 | 148866 | 0 | 1396480 | 8658 | docs(readme): clarify developer-facing kit story (#288) |
| codex-019ed002-48e-1781606863-1 | codex | 019ed002-48e2-7b43-892f-d2c495a89314 | #288 | gpt-5.4 | 126881 | 0 | 611456 | 1442 | 128323 | 0.4917 | 275747 | 0 | 2007936 | 10100 | docs(readme): clarify developer-facing kit story (#288) -m governance: allow-doc |

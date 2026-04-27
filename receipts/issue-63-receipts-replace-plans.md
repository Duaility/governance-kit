# Receipt: replace plans-as-audit-artifact with receipts

Issue: [#63](https://github.com/Duaility/governance-kit/issues/63)

## Checklist

- [x] plan-per-issue and commit-issue-plan-match directives are removed
- [x] new directive folders added
- [x] old directive folders deleted
- [x] pack.yaml minimal preset updated
- [x] Cross-references updated

## What changed

The `plan-per-issue` and `commit-issue-plan-match` directives are removed. They are replaced with `receipt-shape` and `commit-issue-receipt-match`, which enforce the same disciplines against `receipts/*.md` instead of `plans/*.md`.

The taxonomy shift: in this repo's mental model, "plan" is reserved for the pre-implementation artifact that Claude Code / Codex produce in plan-mode (an agent-runtime concept, out of governance scope). The governance concern is the **post-implementation audit trace** — what was changed, and how a reviewer can verify it. That artifact is now called a *receipt*, written/iterated by the agent across the multi-commit work cycle and read by the human reviewer at PR time.

Edits land at both layers per the pack-and-dogfood dual-edit rule:

- **Pack source** (`extensions/packs/agent-governance/directives/`): old directive folders deleted, new directive folders added with `directive.yaml`, `check.sh`, `constitution.md`, and `evals/test.sh`. `pack.yaml` `minimal` preset updated.
- **Dogfood install** (`tests/governance/directives/`): old directive folders deleted, new directive folders added (no evals at this layer).
- `CONSTITUTION.md`: old subsections removed, new subsections inserted, Evolution Log entry appended.
- `.governance-kit/installed-packs.yaml`: directive list under `duaility/agent-governance` updated.
- Cross-references updated in `README.md`, `extensions/catalog.community.json`, `governance/references/DIRECTIVES_CATALOG.md`, and the agent-governance pack `README.md`.

The existing `plans/` folder is intentionally left untouched as historical record. The `<!-- governance: allow-plan-per-issue -->` waivers in those files become harmless comments.

## Out of scope

- **Coverage check** — a directive that enforces "every closed issue has a receipt" is intentionally out of scope for v1. The constitution + human PR review carry that load. A CI-only coverage directive may be added later if the silent-skip failure mode shows up in practice.
- **Plan-mode plans** as a governance concern — pre-implementation plans produced by Claude Code / Codex are an agent-runtime concept and remain out of scope.
- **Migration of existing `plans/`** — those files stay as-is.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Old directives are gone.** `tests/governance/directives/plan-per-issue/` and `tests/governance/directives/commit-issue-plan-match/` no longer exist (same at `extensions/packs/agent-governance/directives/`).
2. **New directives are present at both layers.** `receipt-shape/` and `commit-issue-receipt-match/` exist under `tests/governance/directives/` (with `directive.yaml`, `check.sh`, `constitution.md`) and under `extensions/packs/agent-governance/directives/` (with the same plus `evals/test.sh`).
3. **Manifest is consistent.** `extensions/packs/agent-governance/pack.yaml` `minimal` preset names the two new directives. `.governance-kit/installed-packs.yaml` lists them under the `duaility/agent-governance` block.
4. **Smoke test passes.** `bash tests/governance/run.sh` exits 0 on this branch.
5. **Evals pass.** `bash scripts/test-packs.sh` (or the equivalent eval harness) runs the new `evals/test.sh` for both directives and they pass.
6. **No live references to the old directive ids remain** outside of `CONSTITUTION.md` Evolution Log entries, the `plans/` folder, and `COSTS.md` historical rows. (Search: `grep -rn 'plan-per-issue\|commit-issue-plan-match'`.)
7. **Constitution captures the change.** `CONSTITUTION.md` has new `### receipt-shape` and `### commit-issue-receipt-match` subsections, the old subsections are gone, and the Evolution Log carries a 2026-04-26 entry referencing this issue.
8. **This commit itself satisfies `commit-issue-receipt-match`.** The commit's `(#63)` anchor matches the `issue-63` token on this very file.

# Receipt — issue #321

Have the sub-agent attestation envelope explicitly request a small, low-cost model. The author-time attestation is a bounded read-and-record audit whose verdict the merge-time sweep lane re-derives, so the expensive model belongs in the sweep lane, not on the commit-path audit. The request rides the shared `attestation_prompt` helper, so every attestation directive (`receipt-per-issue`, `layer-boundaries`, any future adopter) inherits it from one surface — no per-directive knob.

## Checklist

- [x] `attestation_prompt` (`lib.sh`) requests a small, low-cost model (the low capability tier — e.g. Claude Haiku or a GPT-mini-class model) when instructing the harness to spawn the sub-agent.
- [x] Document the rationale in `SUBAGENT_ATTESTATION.md` and align `receipt-per-issue`'s in-source prompt comment.

## What changed

- **`attestation_prompt` (`lib.sh`) requests a small, low-cost model (the low capability tier — e.g. Claude Haiku or a GPT-mini-class model) when instructing the harness to spawn the sub-agent.** — `kit/assets/dot-governance/lib.sh`'s `attestation_prompt` printf now opens `Spawn a fresh-context sub-agent — on a small, low-cost model (the low capability tier, e.g. Claude Haiku or a comparable GPT-mini-class model; … verdict is independently re-derived by the merge-time sweep lane) — …`, and also asks the auditor to render each verdict as exactly the token `PASS` or `REFUTED`. The asserted substring `Spawn a fresh-context sub-agent` (`scripts/test-runtime.sh`) is preserved. The function's doc comment gains a note that the small-model request is a deliberate cost optimization (issue #321) because the verdict is re-derived by the sweep lane. Because both `receipt-per-issue` and the repo-local `layer-boundaries` emit their instruction through this one helper, they inherit the guidance with no per-directive change.
- **Document the rationale in `SUBAGENT_ATTESTATION.md` and align `receipt-per-issue`'s in-source prompt comment.** — `kit/references/SUBAGENT_ATTESTATION.md` gains a "Model tier: use a small model" section (the author-time pass is bounded read-and-record; the sweep lane re-derives the truth on its own `model_tier`; capability tier not a pinned model id; small models can fumble strict formatting but the gate matches the verdict token case-insensitively anywhere), and its `attestation_prompt` helper bullet now links that section. `packs/audit/directives/receipt-per-issue/check.sh`'s in-source prompt comment notes the harness runs the audit on a small, low-cost model and points at the new section, so the comment no longer understates what the shared envelope emits.

## Out of scope

- The repo-local `layer-boundaries` directive (`.governance/packs/duaility/governance-kit/`) — it consumes `require_attestation` from the consumed `.governance/lib.sh`, so it inherits the small-model request automatically once the dogfood catches up to this `kit/assets/` source edit at the next release + `governance update`. No edit to the consumed tree (hand-edit-forbidden).
- A `defaults.conf` knob to configure the model/tier — deliberately not added; the model choice rides the prompt text (the single existing surface), keeping one opt-in surface rather than a new per-directive gate.
- The sweep lane's `model_tier` — already a capability tier; unchanged. This issue only governs the author-time attestation pass.
- `CONSTITUTION.md` / `.governance/` consumed tree — not hand-edited; catches up at the next release.

## Verification

The runtime test (which asserts the `attestation_prompt` output), the pack evals (which install the directive against this source `lib.sh` and exercise `receipt-per-issue`'s `## Audit` gate), and the dogfood suite all pass:

```sh
bash -n kit/assets/dot-governance/lib.sh           # printf edit is valid bash
bash scripts/test-runtime.sh                        # 78 assertions, incl. the attestation-prompt substring
bash scripts/test-packs.sh                          # 3 packs, 15 directives, 15 evals
bash .governance/run.sh                             # 16 directives pass
```

This receipt's own `## Audit` and `## Layer boundaries` sections were authored by fresh-context sub-agents spawned **on Haiku** — dogfooding the very optimization this issue introduces.

## Decisions

- **One surface (`attestation_prompt`), no config knob.** The model request lives in the shared prompt envelope, so every attestation directive inherits it and there is nothing per-directive to wire. A `defaults.conf` tier knob was considered and rejected — it would add an internal gate to an already-single opt-in surface.
- **Capability tier, not a model id.** The prompt says "low capability tier — e.g. Claude Haiku or a GPT-mini-class model" rather than pinning one model, mirroring the sweep lane's `model_tier`, and naming both a Claude and an OpenAI example because the envelope is emitted under both the Claude Code and Codex harnesses.
- **Also asked for a literal `PASS`/`REFUTED` token.** A trial run of the attestations on Haiku for this very PR showed a small model can leave template/placeholder text in its output. The gate already matches the token case-insensitively anywhere in the section, so this never blocks a commit, but instructing the auditor to render the bare token keeps the recorded section clean — a cheap robustness add that directly serves the cost goal (cheap models need crisper format instructions).
- **`layer-boundaries` not touched directly.** It inherits the change through `require_attestation` once the consumed tree catches up; editing the consumed tree by hand is forbidden.

## Audit

PASS

- PASS — The `## What changed` section accurately describes all four changed files (`lib.sh`, `SUBAGENT_ATTESTATION.md`, `receipt-per-issue/check.sh`, and this receipt). The `attestation_prompt` printf now opens with the preserved substring "Spawn a fresh-context sub-agent" followed by the small-model guidance, asks for the literal `PASS`/`REFUTED` token, and the doc comment gains the cost-optimization note. `SUBAGENT_ATTESTATION.md` adds the "Model tier: use a small model" section with a link from the helper bullet, and `receipt-per-issue/check.sh`'s comment is updated to reference it. All paths and edits match the staged diff.
- PASS — Both checklist items are realized in the diff: item 1 (attestation_prompt requests a small model) in `lib.sh`'s doc comment and printf; item 2 (document in SUBAGENT_ATTESTATION.md + align the receipt-per-issue comment) in the new doc section and the updated check.sh comment. The substring asserted by `scripts/test-runtime.sh` is preserved and the language is capability-tier, not a pinned model id.
- PASS — The `## Checklist` mirrors issue #321's proposed change exactly: request a small/low-cost model in `attestation_prompt`, document the rationale in `SUBAGENT_ATTESTATION.md`, align `receipt-per-issue`'s comment, preserve the substring, and use capability-tier language.

This `## Audit` verdict was derived by a fresh-context sub-agent (run on Haiku) handed only the staged diff, this receipt, and `gh issue view 321`; it returned PASS on all three dimensions.

## Layer boundaries

PASS

- PASS — All changed files sit in their declared layers: `kit/assets/dot-governance/lib.sh` and `kit/references/SUBAGENT_ATTESTATION.md` are kit-layer (shared engine + docs); `packs/audit/directives/receipt-per-issue/check.sh` is a pack-layer directive (comment-only edit); the receipt is repo-root tooling outside the stack. ARCHITECTURE.md's `skill → kit → packs` (downward-only) map is honored.
- PASS — Dependency edges point downward only. The pack's `check.sh` sources the kit-owned `lib.sh` and calls `require_attestation`/`attestation_prompt` (kit-layer functions); no kit code references pack code. The kit→pack edge is the permitted direction; the change adds no upward edge.
- PASS — The small-model request is wired into the one kit-owned shared helper (`attestation_prompt` in `lib.sh`), not duplicated into the pack. Every attestation-backed directive inherits it via `require_attestation` → `attestation_prompt`; the pack's comment merely references the kit documentation.

This `## Layer boundaries` verdict was derived by a fresh-context sub-agent (run on Haiku) handed only the staged diff and the `## Layer map` section of `ARCHITECTURE.md`; it returned PASS on all three dimensions.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-c594b53d-954-1781706595-1 | claude-code | c594b53d-954e-457f-b804-476378ea9dd1 | #321 | claude-opus-4-8 | 86010 | 341768 | 41440108 | 265858 | 693636 | 29.9326 | 116925 | 754822 | 58191654 | 430125 |  |

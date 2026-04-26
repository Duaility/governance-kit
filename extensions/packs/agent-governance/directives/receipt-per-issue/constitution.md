### receipt-per-issue

- **Directive**: Every tracked `receipts/*.md` file satisfies two shape requirements:
    1. The filename includes an `issue-<N>` token identifying the GitHub issue the receipt is for, and no two receipts share the same issue number.
    2. The body contains three Markdown sections — `## What changed`, `## Out of scope`, and `## Verification` — describing what the change did, what it intentionally did not do, and the criteria a reviewer uses to judge the work complete.
- **Rationale**: Receipts are the durable post-implementation audit trace for work an agent did against a GitHub issue. The one-receipt-per-issue binding keeps the system of record unambiguous: a reviewer jumps from an issue to its single receipt, and an agent can detect whether an issue already has a receipt before drafting a duplicate. The three required sections force the agent to write the parts a reviewer actually needs — `What changed` (the surface area), `Out of scope` (so omissions are not mistaken for oversights), and `Verification` (how completion is judged). In this repo's mental model, all code is authored by coding agents, so the receipt is the agent's attestation to the human reviewer. Receipts are distinct from the pre-implementation plans Claude Code / Codex produce in plan-mode — those are an agent-runtime concept, out of governance scope.
- **Enforced by**: `tests/governance/directives/receipt-per-issue/check.sh`
- **Exceptions**: None. Receipts are a fresh discipline; there is no legacy receipt corpus to grandfather.

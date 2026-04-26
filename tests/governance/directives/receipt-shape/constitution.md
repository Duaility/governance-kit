### receipt-shape

- **Directive**: Every tracked `receipts/*.md` file satisfies two shape requirements:
    1. The filename includes an `issue-<N>` token identifying the GitHub issue the receipt is for, and no two receipts share the same issue number.
    2. The body contains a `## Verification` section describing the criteria a reviewer uses to judge the work complete.
- **Rationale**: Receipts are the durable post-implementation audit trace for work an agent did against a GitHub issue — they record what was changed and how a reviewer can verify it. In this repo's mental model, all code is authored by coding agents, so a receipt is the agent's attestation of the work and its verification criteria. One receipt per issue keeps the system of record unambiguous: a reviewer jumps from an issue to its single receipt, and an agent can detect whether an issue already has a receipt before drafting a duplicate. Receipts are distinct from the pre-implementation plans Claude Code / Codex produce in plan-mode — those are an agent-runtime concept, out of governance scope.
- **Enforced by**: `tests/governance/directives/receipt-shape/check.sh`
- **Exceptions**: None. Receipts are a fresh discipline; there is no legacy receipt corpus to grandfather.

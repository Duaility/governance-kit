# Issue 301: Clarify README for Agent Coherence

Closes [#301](https://github.com/Duaility/governance-kit/issues/301).

## Checklist

- [x] README.md speaks to developers driving Codex, Claude Code, Cursor, OpenCode, or similar coding agents.
- [x] README.md explains that agents can pass local tasks while causing architecture or taste drift over time.
- [x] README.md covers context-management and repo-knowledge failures beyond architecture drift.
- [x] README.md ties governance-kit to harness engineering through enforceable repo-local boundaries rather than larger prompt blobs.
- [x] README.md stays concise while broadening the core idea.
- [x] Governance checks pass.

## What changed

**README.md speaks to developers driving Codex, Claude Code, Cursor, OpenCode, or similar coding agents.** The README opening now addresses developers who use coding agents heavily and names the multi-agent handoff problem directly: one agent receives a correction, but the next agent on the branch does not inherit that session memory. The benefits list now emphasizes shared behavior across Codex, Claude Code, Cursor, OpenCode, and humans through repo-pinned checks.

**README.md explains that agents can pass local tasks while causing architecture or taste drift over time.** The core idea section now frames the failure as work that is locally fine but globally wrong: tests pass, but the architecture drifts because logic lands in the wrong layer, a prior pattern is reinvented, a fallback survives, or a boundary widens.

**README.md covers context-management and repo-knowledge failures beyond architecture drift.** The core idea now calls out context scarcity, stale guidance, invisible knowledge outside the repo, throughput-amplified entropy, and local success that still creates global drift. The examples now include keeping `AGENTS.md` short and making docs fresh, linked, scoped, and discoverable.

**README.md ties governance-kit to harness engineering through enforceable repo-local boundaries rather than larger prompt blobs.** The harness-engineering paragraph now describes the human role as designing the environment agents work inside, with repo-local knowledge, structural tests, architecture boundaries, and taste invariants that execute. It also connects that stance back to governance-kit packs and git-native receipts.

**README.md stays concise while broadening the core idea.** The new framing is contained to the opening copy, one compact problem list, the harness-engineering bridge, and the existing benefits list. The README's install, packs, proof, lifecycle, and documentation sections remain intact.

No runtime behavior, bundled directive code, pack metadata, `CONSTITUTION.md`, or `.governance/` managed file changed.

## Out of scope

- Changing governance runtime behavior.
- Changing bundled directive code or pack metadata.
- Rewriting `CONSTITUTION.md` or managed `.governance/` files.
- Reworking the README install, packs, proof, lifecycle, or documentation sections beyond the positioning copy.

## Decisions

The initial PR draft focused mainly on local-success/global-drift. After rereading the Harness Engineering article, the README framing was broadened to cover the other agent-first operating problems without adding a new long-form section.

## Verification

```sh
bash .governance/run.sh
```

Result: Governance checks pass. All 17 governance directives passed before the PR handoff.

## Audit

PASS - `## What changed` faithfully describes the diff. The diff changes `README.md` positioning copy and this receipt only; the receipt names the broadened agent-first framing and the unchanged runtime/governance surfaces.

PASS - Each checked checklist item is realized in the diff. The README now names Codex, Claude Code, Cursor, and OpenCode; describes locally fine but globally wrong agent work; covers context-management and repo-knowledge failures beyond architecture drift; ties the pitch to harness engineering and executable repo-local invariants; stays concise by keeping the broader framing in the opening section; and the verification section records the governance command.

PASS - The `## Checklist` mirrors issue #301's checklist. The checked items use the same acceptance criteria text from the issue.

## Layer boundaries

PASS - Every changed file sits in the layer its role belongs to. `README.md` is public-facing project documentation, and `receipts/issue-301-readme-agent-coherence.md` is the audit artifact for issue #301.

PASS - No dependency points the wrong way across a layer edge. This is documentation-only work and introduces no code dependency.

PASS - No new shared logic was duplicated into a consumer layer. The change adds no shared logic.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed1ae-92a-1781637234-1 | codex | 019ed1ae-92aa-7753-a53f-d11baddc0ec3 | #301 | gpt-5.5 | 240440 | 0 | 2921344 | 11076 | 251516 | 1.4976 | 240440 | 0 | 2921344 | 11076 | docs: clarify README for agent coherence (#301) |
| codex-019ed1ae-92a-1781670342-1 | codex | 019ed1ae-92aa-7753-a53f-d11baddc0ec3 | #301 | gpt-5.5 | 153246 | 0 | 2120832 | 6831 | 160077 | 1.0158 | 393686 | 0 | 5042176 | 17907 | docs: broaden README agent-first framing (#301) |
| codex-019ed1ae-92a-1781670470-1 | codex | 019ed1ae-92aa-7753-a53f-d11baddc0ec3 | #301 | gpt-5.5 | 14300 | 0 | 845568 | 1162 | 15462 | 0.2646 | 407986 | 0 | 5887744 | 19069 | docs: broaden README agent-first framing (#301) -m governance: allow-agent-token |

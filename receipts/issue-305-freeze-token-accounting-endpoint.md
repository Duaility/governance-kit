# Issue 305: Freeze token accounting endpoint between pre-commit and commit-msg

Closes [#305](https://github.com/Duaility/governance-kit/issues/305).

## Checklist

- [x] A commit passes when the receipt row matches the frozen coordinate written by the pre-commit accounting hook, even if the live transcript advances before commit-msg.
- [x] A commit fails when an agent runtime is detected but no matching frozen endpoint exists for the staged tree.
- [x] A commit fails when the frozen endpoint exists but the receipt row does not match it.
- [x] Existing receipt ledger validation still catches malformed rows, duplicate keys, non-monotonic cumulative rows, and bad deltas.
- [x] Tests/evals cover the race observed above.
- [x] Governance checks pass.

## What changed

**A commit passes when the receipt row matches the frozen coordinate written by the pre-commit accounting hook, even if the live transcript advances before commit-msg.** `packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh` now writes a staged-tree endpoint after appending and staging the receipt row. The endpoint is keyed as `governance-token-endpoints/<tree>.json`, where `<tree>` is the post-row `git write-tree` result, so `packs/audit/directives/agent-token-accounting/check.sh` verifies the exact coordinate sampled by the writer instead of comparing against a later live transcript coordinate. The new helper lives at `packs/audit/directives/agent-token-accounting/lib/endpoint.py`; it writes the endpoint and verifies that the staged receipt row named by `cost_key` has the same session and cumulative coordinate.

**A commit fails when an agent runtime is detected but no matching frozen endpoint exists for the staged tree.** `packs/audit/directives/agent-token-accounting/check.sh` still detects whether an agent runtime is active through `packs/audit/directives/agent-token-accounting/lib/runtime.sh`, but once a runtime is detected it requires the tree-keyed endpoint file. A hook-skipped commit has no endpoint for the staged tree and fails with a direct remediation message.

**A commit fails when the frozen endpoint exists but the receipt row does not match it.** `packs/audit/directives/agent-token-accounting/lib/endpoint.py` verifies the endpoint's receipt path, `cost_key`, `session`, and `cum-*` coordinate against the staged receipt row. A missing row, duplicate row, wrong session, or wrong cumulative coordinate is reported as a commit-time violation.

**Existing receipt ledger validation still catches malformed rows, duplicate keys, non-monotonic cumulative rows, and bad deltas.** The repo-wide `validate-dir` path is unchanged: `packs/audit/directives/agent-token-accounting/lib/ledger.py` still owns row parsing and delegates validation to the existing validation/reconciliation stack. Its `session-cum` text was downgraded to query-helper language because the commit-time completeness check no longer uses it as the endpoint.

**Tests/evals cover the race observed above.** `packs/audit/directives/agent-token-accounting/evals/test.sh` now creates the same staged-tree endpoint that pre-commit writes. The main pass fixture records a frozen coordinate, advances the simulated live runtime cumulative before commit-msg, and still passes because the staged receipt row matches the frozen endpoint. The failure fixtures cover a missing endpoint and an endpoint whose coordinate does not match the staged row.

**Governance checks pass.** The directive docs were updated in `packs/audit/directives/agent-token-accounting/README.md`, `packs/audit/directives/agent-token-accounting/constitution.md`, comments in `packs/audit/directives/agent-token-accounting/check.sh`, `packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh`, and `packs/audit/directives/agent-token-accounting/lib/runtime.sh` so the source-pack contract describes the frozen endpoint behavior.

## Out of scope

- The consumed `.governance/` tree; this is source-pack work and the consumed tree updates only through a release/pin flow.
- Steering accounting semantics.
- Weakening token accounting to best-effort or removing commit-msg reconciliation.
- Changing the receipt row schema.

## Verification

```sh
bash packs/audit/directives/agent-token-accounting/evals/test.sh
```

```sh
bash scripts/test-packs.sh
```

## Decisions

- Added a small `lib/endpoint.py` helper instead of extending `lib/ledger.py`, because `ledger.py` is already at the repo-hygiene file-size limit and endpoint files are a separate git-dir concern from receipt row parsing.
- Keyed endpoints by the staged tree after `git add "$RECEIPT"` rather than by session or timestamp. The staged tree is the identity commit-msg can recompute without accepting stale endpoint reuse from an earlier commit attempt.
- Kept runtime detection in `check.sh` so human/manual commits still no-op, but stopped using the live runtime counters for reconciliation after detection. The live counters are deliberately allowed to move after the writer samples them.

## Audit

PASS - The diff changes only the `agent-token-accounting` source directive and this receipt. The `## What changed` section names every changed source path and maps each issue acceptance item to an implementation or eval claim: `hooks/pre-commit.sh` writes the tree-keyed endpoint; `check.sh` requires/verifies it; `lib/endpoint.py` validates the staged receipt row; `lib/ledger.py`/`lib/runtime.sh` comments are adjusted to the new contract; `README.md` and `constitution.md` document the behavior; and `evals/test.sh` covers live transcript movement plus missing/mismatched endpoint failures. The issue checklist is mirrored from #305's acceptance criteria, and each checked item is evidenced above or in `## Verification`.

## Layer boundaries

PASS - The diff stays inside the pack-source/audit-documentation layer: all behavior changes are under `packs/audit/directives/agent-token-accounting/`, and the only added non-pack file is this receipt under `receipts/`. No kit engine code, published thin skill code, consumed `.governance/` tree, release metadata, or hook dispatchers are changed. The new shared helper `lib/endpoint.py` lives inside the directive that owns the endpoint contract rather than being duplicated into kit runtime code or the consumed tree, and no dependency points upward across the `skill -> kit -> packs -> consumed repo` model.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed425-7a3-1781676905-1 | codex | 019ed425-7a35-7ba1-9d20-8400d7a50349 | #305 | gpt-5.5 | 394894 | 0 | 3161600 | 19436 | 414330 | 2.0692 | 394894 | 0 | 3161600 | 19436 | fix(audit): freeze token accounting endpoint (#305) -m governance: allow-agent-t |

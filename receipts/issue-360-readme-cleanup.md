# issue-360 — clean up README for the current kit release

Closes [#360](https://github.com/Duaility/governance-kit/issues/360).

## Checklist

- [x] Replace the invalid quickstart commit example with a valid issue-linked Conventional Commit.
- [x] Tighten the wording around judge-backed attestations, receipts, and cost/steering accounting.
- [x] Remove or correct any stale README claims or links found while making the cleanup.
- [x] Keep the change documentation-only; do not change kit behavior, bundled directives, or the consumed `.governance/` tree.

## What changed

- **README.md**: replace the quickstart command with a valid issue-linked Conventional Commit and explain the invalid `stuff` example as the failure case; align the receipt and audit-chain copy with identity-at-commit / measurement-at-rest accounting; rename the retired `subagent:` terminology to the current `judge:` declaration; and update the dogfood count to 19 executable checks plus 2 repo-local judge-only sweep declarations.
- **receipts/issue-360-readme-cleanup.md**: record the issue checklist, scope, verification commands, and the required audit attestations for this documentation change.
- **Checklist crosswalk**: Replace the invalid quickstart commit example with a valid issue-linked Conventional Commit. Tighten the wording around judge-backed attestations, receipts, and cost/steering accounting. Remove or correct any stale README claims or links found while making the cleanup. Keep the change documentation-only; do not change kit behavior, bundled directives, or the consumed `.governance/` tree.

## Out of scope

- No kit runtime, bundled directive, pack metadata, generated reference page, or consumed `.governance/` file changes.
- No README restructuring beyond the stale examples, accounting terminology, judge terminology, and current dogfood-count correction identified in issue #360.

## Decisions

- The branch was fast-forwarded to `origin/main` at `04b84b1` before editing, per the operator request, so this PR exercises the current v0.13.0 dogfood-sync tree.
- The quickstart keeps `stuff` only as explanatory failure output; the command users can run is the valid issue-linked example `docs: record the first governance run (#1)`.
- The dogfood count is derived from the current tree: 21 installed directive declarations, 19 executable `check.sh` checks, and 2 repo-local `hook: none` judge-only declarations.

## Verification

```sh
bash .governance/run.sh
git diff --check
test "$(find .governance/packs -type f -path '*/directives/*/check.sh' | wc -l | tr -d ' ')" = 19
test "$(find .governance/packs -type f -path '*/directives/*/directive.yaml' | wc -l | tr -d ' ')" = 21
! rg -n '`subagent:`|runtime endpoint|17 synchronous directive checks' README.md
```

The clean `origin/main` base passed all 19 executable governance directives before this change; the same suite is rerun after the README and receipt are staged.

## Audit

Fresh-context sub-agent review against issue #360 and the staged diff.

**Verdict: PASS.**

- The README changes match the diff: quickstart, attestation, accounting, terminology, and count corrections.
- Every checked checklist item is realized by the documentation-only diff.
- The four checklist items mirror the four issue-scope requirements one-to-one.

## Layer boundaries

Fresh-context sub-agent review against `ARCHITECTURE.md` and the staged diff.

**Verdict: PASS.**

- `README.md` remains a narrative and catalog surface; it does not change kit behavior.
- The receipt remains an issue-scoped evidence and attestation record.
- `ARCHITECTURE.md` is untouched, and no kit, directive, pack, generated-reference, or consumed `.governance/` files change.

## Steering

Fresh-context sub-agent review of the session transcript.

**Verdict: PASS.**

- The user interruption requiring a fast-forward from `main` is recorded as one structural correction in the accounting ledger below.
- No additional interrupts or corrections were identified in the available transcript for this change.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-08-05 | codex | 019fd107-dd78-76b0-b760-9434ab807af0 | - | - | - | - | - | - | unresolved |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-019fd107dd78-1785918687-1 | 019fd107-dd78-76b0-b760-9434ab807af0 | #360 | correction | structural | Pull in changes from main branch and then start your work. | - | 2 | 2026-08-05T08:31:27.000Z |

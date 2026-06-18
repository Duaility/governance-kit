# issue-335: fix(audit): make Codex token runtime strict

Closes [#335](https://github.com/Duaility/governance-kit/issues/335).

## Checklist

- [x] Make Codex token accounting resolve transcripts from the current Codex contract
- [x] Remove newest-transcript guessing and legacy transcript-shape parsing
- [x] Make transcript remediation text runtime-aware
- [x] Add regression coverage for Codex transcript resolution and strict no-guess behavior
- [x] Harden sub-agent attestation remediation for Codex mini-model execution
- [x] Document conventional issue/PR titles for governance work

## What changed

- **Make Codex token accounting resolve transcripts from the current Codex contract.**
  `packs/audit/directives/agent-token-accounting/runtimes/codex.sh` now accepts
  `CODEX_TRANSCRIPT_PATH` as an explicit transcript path, otherwise requires
  `CODEX_THREAD_ID` and searches `~/.codex/sessions/` plus
  `~/.codex/archived_sessions/` for a filename ending in
  `$CODEX_THREAD_ID.jsonl`. `packs/audit/directives/agent-token-accounting/lib/runtime.sh`
  and `packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh`
  document/detect the same Codex signals.
- **Remove newest-transcript guessing and legacy transcript-shape parsing.**
  `packs/audit/directives/agent-token-accounting/runtimes/codex.sh` no longer
  chooses the newest `.jsonl`, derives a session id from the filename, or sums
  older `usage` / `message.usage` / `response.usage` shapes. It reads the current
  Codex Desktop transcript shape only: `session_meta.payload.id`,
  `turn_context.payload.collaboration_mode.settings.model`, and
  `event_msg.payload.info.total_token_usage`.
- **Make transcript remediation text runtime-aware.**
  `kit/assets/dot-governance/lib.sh` resolves the `transcript` sub-agent input
  to Codex-specific guidance when `CODEX_THREAD_ID` or `CODEX_TRANSCRIPT_PATH`
  is present, and preserves Claude Code guidance when `CLAUDE_CODE_SESSION_ID`
  or `CLAUDE_TRANSCRIPT_PATH` is present. The reference docs in
  `kit/references/SUBAGENT_ATTESTATION.md`,
  `kit/references/INIT_FLOW.md`,
  `packs/audit/directives/agent-token-accounting/README.md`, and
  `packs/audit/directives/agent-steering-accounting/README.md` were updated to
  match the current runtime behavior.
- **Add regression coverage for Codex transcript resolution and strict no-guess behavior.**
  `scripts/test-runtime.sh` now builds current-shape Codex JSONL fixtures,
  asserts that the thread-id transcript wins over a newer unrelated transcript,
  asserts that the reader refuses to guess without `CODEX_THREAD_ID` or
  `CODEX_TRANSCRIPT_PATH`, and checks the runtime-aware transcript prompt.
- **Receipt coverage.** This receipt is tracked as
  `receipts/issue-335-codex-runtime-token-accounting.md`.
- **Harden sub-agent attestation remediation for Codex mini-model execution.**
  `kit/assets/dot-governance/lib.sh` now names a Codex mini-class model for the
  low-tier attest lane and explicitly tells the primary agent not to
  self-author attestation sections. `scripts/test-runtime.sh` locks both
  strings into the remediation output.
- **Document conventional issue/PR titles for governance work.**
  `kit/references/DIRECTIVE_AMEND_FLOW.md` now says GitHub issue and PR titles
  created by the flow should use the same Conventional Commits subject stem
  because squash merges and release notes commonly inherit those titles.

## Out of scope

- Updating the consumed `.governance/` tree. This repo treats `.governance/` as
  a released consumer materialization, so source changes land under `kit/`,
  `packs/`, and `scripts/` only.
- Changing Claude Code transcript resolution.
- Changing model rate-card behavior such as family-prefix pricing rows.

## Decisions

- **No newest-transcript fallback for Codex.** In v0 the current runtime
  contract is enough: a Codex-authored commit has `CODEX_THREAD_ID`, and an
  operator can supply `CODEX_TRANSCRIPT_PATH` explicitly. If neither is present,
  the reader exits non-zero instead of guessing.
- **Current transcript shape only.** The Codex adapter now prices the shape
  Codex Desktop writes today. Older transcript layouts can fail loudly rather
  than staying as hidden compatibility paths.
- **Explicit transcript paths remain supported.** `CODEX_TRANSCRIPT_PATH` is an
  operator-provided coordinate, not a heuristic path; it is useful for targeted
  debugging and scripted tests.
- **Low-tier attestations should not inherit the primary model.** Codex
  harnesses now get a version-agnostic mini-class hint for the bounded
  read-and-record attest lane, while stronger models remain available through
  the operator-owned `SUBAGENT_TIERS_ATTEST` overlay.

## Verification

```sh
bash scripts/test-runtime.sh
npm run docs:gen:check
git diff --check
bash .governance/run.sh
bash scripts/test-packs.sh
bash scripts/test.sh
```

All commands passed locally. `scripts/test-runtime.sh` reports 119 assertions,
including the new Codex strict-reader cases.

## Audit

Fresh-context sub-agent audit of the branch diff against `main`, issue #335,
and this receipt:

- PASS - The receipt's `## What changed` faithfully describes the branch diff against `main`; the changed files and behavioral claims match the diff.
- PASS - Each checked checklist item is realized in the diff: strict Codex transcript resolution, removal of newest/legacy parsing paths, runtime-aware transcript guidance, and regression coverage are all present.
- PASS - The receipt checklist mirrors issue #335's proposed fix bullets.

## Layer boundaries

Fresh-context sub-agent layer audit against `ARCHITECTURE.md`:

- PASS - Changed files sit in appropriate layers: Codex runtime logic stays in the audit pack, shared sub-agent prompt resolution stays in kit runtime support, reference/docs stay in kit/directive docs, and tests stay under `scripts/`.
- PASS - No changed dependency points the wrong way across the `skill -> kit -> packs` architecture edges; `skill/` and consumed `.governance/` are untouched.
- PASS - No shared logic is duplicated into a consumer layer; the shared transcript-input wording remains centralized in `kit/assets/dot-governance/lib.sh`.

## Steering

Fresh-context sub-agent review of the session transcript:

- PASS - The operator correction to remove legacy fallback behavior is recorded in `### Steering` with transcript ordinal 3 and timestamp `2026-06-18T05:53:43.041Z`.
- PASS - The later correction that the receipt claimed fresh-context attestation before a sub-agent was actually triggered is recorded in `### Steering` with transcript ordinal 8 and timestamp `2026-06-18T06:10:44.466Z`.
- PASS - The correction covering conventional GitHub titles, mini-model attestations, and systemic pack/kit fixes is recorded in `### Steering` with transcript ordinal 9 and timestamp `2026-06-18T06:16:23.867Z`.
- PASS - The later correction to avoid enforcing the cache-create clarification and to avoid explicit mini-model version names is recorded in `### Steering` with transcript ordinal 10 and timestamp `2026-06-18T06:25:46.133Z`.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque - do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-019ed941f410-1781762023-1 | 019ed941-f410-7871-bacf-6db3af231768 | #335 | correction | classifier | Remove legacy fallback behavior; keep only the current v0 Codex runtime path. | fix(audit): make codex token runtime strict (#335) | 3 | 2026-06-18T05:53:43.041Z |
| steer-019ed941f410-1781763044-1 | 019ed941-f410-7871-bacf-6db3af231768 | #335 | correction | classifier | Correct false claim that fresh-context attestation had already been triggered. | fix(audit): make codex token runtime strict (#335) | 8 | 2026-06-18T06:10:44.466Z |
| steer-019ed941f410-1781763383-1 | 019ed941-f410-7871-bacf-6db3af231768 | #335 | correction | classifier | Use Conventional Commits-style issue/PR titles, spawn attestations on a Codex mini model, and add systemic pack/kit fixes for the mistakes above. | fix(audit): make codex token runtime strict (#335) | 9 | 2026-06-18T06:16:23.867Z |
| steer-019ed941f410-1781763946-1 | 019ed941-f410-7871-bacf-6db3af231768 | #335 | correction | classifier | Do not add cache-create clarification as an enforced change, and keep Codex mini-model guidance version-agnostic. | fix(audit): make codex token runtime strict (#335) | 10 | 2026-06-18T06:25:46.133Z |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed941-f41-1781762894-1 | codex | 019ed941-f410-7871-bacf-6db3af231768 | #335 | gpt-5.5 | 506794 | 0 | 9999872 | 30304 | 537098 | 8.4430 | 506794 | 0 | 9999872 | 30304 | fix(audit): make codex token runtime strict (#335) -m governance: allow-toolchai |
| codex-019ed941-f41-1781764366-1 | codex | 019ed941-f410-7871-bacf-6db3af231768 | #335 | gpt-5.5 | 284217 | 0 | 7691264 | 24133 | 308350 | 5.9907 | 791011 | 0 | 17691136 | 54437 | fix(audit): make codex token runtime strict (#335) -m governance: allow-toolchai |

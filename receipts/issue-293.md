# Receipt — issue #293

Retire the per-commit accounting trailers. Token completeness is now proven by reconciling the receipt's recorded cumulative against the transcript at commit time; steering keeps only its ledger-shape check; `commit-issue-receipt-match` anchors file-first on the touched receipt path. The receipt becomes the single accounting artifact and the single commit↔issue link.

## Checklist

- [x] token/steering `prepare-commit-msg.sh` and `lib/trailers.py` removed; generated `.githooks/prepare-commit-msg` becomes a no-op dispatcher.
- [x] agent-token-accounting Mode A does transcript↔ledger endpoint reconciliation (new `lib/runtime.sh` shared detection + `ledger.py session-cum`); Mode B = `validate-dir` only.
- [x] agent-steering-accounting check = `validate-dir`; pre-commit drops the handoff + summary-triple derivation.
- [x] commit-issue-receipt-match is file-first.
- [x] constitution subsections, READMEs, defaults, DIRECTIVES_CATALOG, and the three eval suites updated; `scripts/test-packs.sh` green.

## What changed

- **token/steering `prepare-commit-msg.sh` and `lib/trailers.py` removed; generated `.githooks/prepare-commit-msg` becomes a no-op dispatcher.** — deleted `packs/audit/directives/agent-token-accounting/hooks/prepare-commit-msg.sh`, `packs/audit/directives/agent-token-accounting/lib/trailers.py`, `packs/audit/directives/agent-steering-accounting/hooks/prepare-commit-msg.sh`, and `packs/audit/directives/agent-steering-accounting/lib/trailers.py`. The hook generator (`kit/assets/packs/lib/hooks.sh`) still emits a `prepare-commit-msg` dispatcher unconditionally for any future directive that ships one; with no bundled directive shipping a helper it is now an empty no-op (comment updated to say so). Both pre-commit writers stop writing their handoff env files: `packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh` and `packs/audit/directives/agent-steering-accounting/hooks/pre-commit.sh`.
- **agent-token-accounting Mode A does transcript↔ledger endpoint reconciliation (new `lib/runtime.sh` shared detection + `ledger.py session-cum`); Mode B = `validate-dir` only.** — new `packs/audit/directives/agent-token-accounting/lib/runtime.sh` holds the shared `resolve_runtime_cumulative` (runtime detection + session cumulative), sourced by both `packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh` (the writer) and `packs/audit/directives/agent-token-accounting/check.sh` (the checker). `packs/audit/directives/agent-token-accounting/lib/ledger.py` gains `session_cum` + the `session-cum` CLI command (the receipt-side endpoint). `check.sh` is rewritten: always `validate-dir`; Mode A reconciles the receipt's recorded `cum-*` for the active session against the transcript (with a `governance: allow-agent-token-accounting <reason>` waiver); Mode B is `validate-dir` only (no trailer/commit-walk). `pre-commit.sh` now sources `lib/runtime.sh` and drops the trailer/handoff tail.
- **agent-steering-accounting check = `validate-dir`; pre-commit drops the handoff + summary-triple derivation.** — `packs/audit/directives/agent-steering-accounting/check.sh` is rewritten to run `lib/ledger.py validate-dir` in both modes (the only remaining contract). `packs/audit/directives/agent-steering-accounting/hooks/pre-commit.sh` keeps extracting + appending rows but drops the staged-diff summary derivation and the handoff write.
- **commit-issue-receipt-match is file-first.** — `packs/audit/directives/commit-issue-receipt-match/check.sh` now requires every non-merge/non-revert commit to add/modify a `receipts/issue-<N>.md`; the touched receipt path is the issue anchor (no subject `(#N)` / body `Issue:` parsing, no HEAD-fallback). Merge/revert exemptions and the `allow-commit-issue-receipt-match` waiver are kept.
- **constitution subsections, READMEs, defaults, DIRECTIVES_CATALOG, and the three eval suites updated; `scripts/test-packs.sh` green.** — rewrote the constitution, README, directive.yaml, and eval for all three directives: `packs/audit/directives/agent-token-accounting/constitution.md`, `packs/audit/directives/agent-token-accounting/README.md`, `packs/audit/directives/agent-token-accounting/directive.yaml`, `packs/audit/directives/agent-token-accounting/evals/test.sh`, `packs/audit/directives/agent-steering-accounting/constitution.md`, `packs/audit/directives/agent-steering-accounting/README.md`, `packs/audit/directives/agent-steering-accounting/directive.yaml`, `packs/audit/directives/agent-steering-accounting/evals/test.sh`, `packs/audit/directives/commit-issue-receipt-match/constitution.md`, `packs/audit/directives/commit-issue-receipt-match/directive.yaml`, and `packs/audit/directives/commit-issue-receipt-match/evals/test.sh`. `defaults.conf` needed no change (no trailer references). Also updated `kit/references/DIRECTIVES_CATALOG.md` (three entries), `kit/references/INIT_FLOW.md` (bootstrap populator + no-runtime fallback), `kit/references/RELEASE_FLOW.md` (one line), root `README.md` (pack table, the work-order mermaid diagram, and the "Token cost" bullet), `packs/audit/directives/agent-token-accounting/lib/report.py` (docstring), and the stale fresh-repo comment in `scripts/test-packs.sh`.

## Out of scope

- `CONSTITUTION.md`, `.governance/` (the vendored consumed tree), prior `receipts/`, `CHANGELOG.md`, `COSTS.md`, `STEERING.md` — immutable, historical, or hand-edit-forbidden. The root `CONSTITUTION.md` and `.governance/` catch up to these `packs/` source edits at the next release + `governance update`, by design (the dogfood lags one release).
- Generic `prepare-commit-msg` references that describe the still-supported hook *kind* (in `AGENTS.md`, `ARCHITECTURE.md`, `kit/references/{INIT_FLOW,NATIVE_TESTS,PACK_AUTHORING,DIRECTIVE_AMEND_FLOW,UNINSTALL_FLOW,UNINSTALL_MATRIX}.md`, `kit/assets/receipt.bootstrap.template.md`) — left as-is; the dispatcher is still emitted, so they remain true.
- A versioning bump for the `audit` pack — versions move only in `chore(release)` commits, never feature PRs.

## Verification

The three reworked directives' evals plus the full kit-internal umbrella suite (which includes the pack smoke, hook-generation, and fresh-repo install contract) pass green:

```sh
bash packs/audit/directives/agent-token-accounting/evals/test.sh
bash packs/audit/directives/agent-steering-accounting/evals/test.sh
bash packs/audit/directives/commit-issue-receipt-match/evals/test.sh
bash scripts/test-packs.sh      # 4 packs, 16 directives, 16 evals
bash scripts/test.sh            # all 19 kit-internal layers
```

The dogfood's own vendored suite is green on the working tree (it lags one release, so it still validates via the old trailer-based directives):

```sh
bash .governance/run.sh         # 17 directives pass
```

## Decisions

- **Asymmetry between token and steering is deliberate.** Token gets a new endpoint-reconciliation check because its absolute `cum-*` coordinates make "did a row get written" cheap and deterministic to verify against the transcript. Steering gets pure removal (no new check) because its completeness was always best-effort — the extractor is non-blocking and the trailer's only contract ("stamp == staged rows") is vacuous once the stamp is gone; `validate-dir` already enforces every real invariant.
- **commit-issue-receipt-match dropped the subject/trailer cross-check entirely** rather than keeping a best-effort one. Post-squash the subject is the PR number, so a subject↔receipt cross-check can't hold on the trunk without a trailer; the receipt path is the authoritative, squash-robust anchor. A subject that names a different number is no longer flagged here (`commit-message-format` still requires the `(#N)`).
- **The `unsupported-runtime` token waiver was retired** — an unrecognised runtime now no-ops the endpoint check (no transcript → nothing to reconcile), so release/human/unsupported-runtime commits pass without a waiver. A general `allow-agent-token-accounting <reason>` waiver remains for the rare legitimate out-of-hook commit.
- **Reconciliation is Mode-A-only** (commit time). Running it in Mode B / a mid-session `run.sh` would false-fail, because the transcript legitimately leads the not-yet-committed work.
- **Tradeoff accepted (from the issue):** per-commit attribution for a `--no-verify` commit is no longer recoverable in CI (no transcript to reconcile against); the absolute `cum-*` coordinates preserve session-total fidelity, so the missing commit's tokens roll into the next accounted row.

## Layer boundaries

PASS

- PASS — Every staged path sits in exactly one layer of the `skill/` → `kit/` → `packs/` stack (plus repo-root tooling/docs): directive logic under `packs/audit/directives/*`, kit-layer docs/lib under `kit/references/*` and `kit/assets/packs/lib/hooks.sh`, the repo-root `README.md`, `scripts/test-packs.sh`, and this receipt. Nothing in `skill/` was touched.
- PASS — No dependency edge is added across layers. The new `lib/runtime.sh` is a *sibling* of the existing `runtimes/` and `lib/` inside the same directive folder, sourced only by that directive's own `check.sh` and `hooks/pre-commit.sh`; no `packs/` code reaches up into `kit/` or `skill/`, and the `kit/` edits are documentation/comments only.
- PASS — No shared logic is duplicated across layers. `resolve_runtime_cumulative` is extracted into one `lib/runtime.sh` and shared by the writer and the checker *within* the agent-token-accounting directory — it removes duplication rather than introducing it; steering keeps its own runtime adapter as before.

## Audit

PASS

- PASS — `## What changed` faithfully maps to the diff: the four deleted files (`prepare-commit-msg.sh` ×2, `trailers.py` ×2) are gone; `lib/runtime.sh` is added and sourced by both the token `check.sh` and `hooks/pre-commit.sh`; `ledger.py` gains `session_cum` + the `session-cum` CLI; the token `check.sh` runs `validate-dir` always and reconciles `session-cum` against the runtime cumulative only in Mode A; the steering `check.sh` is `validate-dir`-only and its `pre-commit.sh` no longer derives a summary or writes a handoff; `commit-issue-receipt-match/check.sh` requires a touched `receipts/*.md` with no subject/trailer parsing. No material diff hunk is unaccounted for in the bullets.
- PASS — Every `- [x]` checklist item is realized and independently verified: the four removals + no-op dispatcher (confirmed by `find` showing no `prepare-commit-msg.sh`/`trailers.py` under `packs/` and the hook-generation layer of `scripts/test.sh` passing); the token endpoint reconciliation (token eval cases 1–8 cover match/lag/missing-row/waiver/rc-2/revert); the steering `validate-dir` contract (steering eval cases 1–8); file-first matching (commit-issue-receipt-match eval); and the doc + eval updates with `bash scripts/test-packs.sh` reporting `4 pack(s), 16 directive(s), 16 eval(s) passed` and `bash scripts/test.sh` reporting `all kit-internal test layers passed`.
- PASS — the receipt's `## Checklist` mirrors issue #293's acceptance checklist verbatim (five items, same wording and order as `gh issue view 293`).

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-0617e8a7-009-1781625287-1 | claude-code | 0617e8a7-0093-464c-9264-14b031b1919b | #293 | claude-opus-4-8 | 7010 | 42846 | 96732 | 2644 | 52500 | 0.4173 | 7010 | 42846 | 96732 | 2644 | refactor(audit): drop accounting trailers; reconcile ledger (#293) -m Retire the |
| claude-code-34d08bf0-ffb-1781625568-1 | claude-code | 34d08bf0-ffb3-4605-a582-eb043a3e08f3 | #293 | claude-opus-4-8 | 44507 | 1587608 | 74862310 | 666187 | 2298302 | 64.2309 | 44507 | 1587608 | 74862310 | 666187 | refactor(audit): drop accounting trailers; reconcile ledger (#293) -m Retire the |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-34d08bf0ffb-1781625286-1 | 34d08bf0-ffb3-4605-a582-eb043a3e08f3 | #293 | correction | classifier | Challenges agent's claim that hook checks only the trailer, not receipt rows | refactor(audit): drop accounting trailers; reconcile ledger (#293) -m Retire th… | 1 | 2026-06-16T14:52:48.034Z |
| steer-34d08bf0ffb-1781625286-2 | 34d08bf0-ffb3-4605-a582-eb043a3e08f3 | #293 | correction | classifier | Calls out verbosity and redirects toward a non-duplicating creative solution | refactor(audit): drop accounting trailers; reconcile ledger (#293) -m Retire th… | 2 | 2026-06-16T14:58:17.821Z |

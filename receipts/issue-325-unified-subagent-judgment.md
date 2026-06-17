# issue-325 — unified sub-agent judgment (batched attest + sweep), steering-as-attestation, deterministic token session

Closes [#325](https://github.com/Duaility/governance-kit/issues/325).

## Checklist

- [x] Add the `subagent:` block and typed input-token resolution
- [x] Add `subagent_attest` and the `attestation_remediation` orchestrator and wire `run.sh` and the dispatcher
- [x] Migrate `receipt-per-issue` and `layer-boundaries` onto the schema
- [x] Delete the steering classifier and its plumbing
- [x] Make `## Steering` a fresh-context sub-agent attestation
- [x] Rewrite the steering directive files
- [x] Resolve the token session from `CLAUDE_CODE_SESSION_ID`
- [x] Converge the sub-agent-judgment docs

## What changed

A single declaration — a `subagent:` block in `directive.yaml` — now drives every
LLM judgment in the kit, executed by one mechanism with two consumer modes
(attest at commit, sweep at merge).

- **Add the `subagent:` block and typed input-token resolution (A).**
  `kit/assets/dot-governance/lib.sh` gains `_subagent_yaml` (a stdlib-python
  parser for the constrained `subagent:` block) and `resolve_subagent_input`
  (typed-token → handle phrase: `diff`, `receipt`, `issue`, `transcript`,
  `layer-map`).
- **Add `subagent_attest` and the `attestation_remediation` orchestrator and
  wire `run.sh` and the dispatcher (A).** `lib.sh` also gains `subagent_attest`
  (the declaration-driven per-directive gate that registers a pending section)
  and `attestation_remediation` (emits ONE grouped remediation instruction —
  shared sections batched into a single sub-agent, plus one isolated sub-agent
  per `isolation: isolated` section). `require_attestation`, `attestation_prompt`,
  and `extract_md_section` are unchanged. `kit/assets/dot-governance/run.sh` and
  the generated pre-commit dispatcher in `kit/assets/packs/lib/hooks.sh` set up a
  ledger and invoke `attestation_remediation` once after the checks.
- **Migrate `receipt-per-issue` and `layer-boundaries` onto the schema (A).**
  `packs/audit/directives/receipt-per-issue/directive.yaml` and
  `.governance/packs/duaility/governance-kit/directives/layer-boundaries/directive.yaml`
  declare a `subagent:` block; `packs/audit/directives/receipt-per-issue/check.sh`
  and `.governance/packs/duaility/governance-kit/directives/layer-boundaries/check.sh`
  call `subagent_attest` (with a `require_attestation` fallback / a `declare -F`
  guard for older runtimes).
- **Delete the steering classifier and its plumbing (B).** Removed
  `packs/audit/directives/agent-steering-accounting/lib/classifier.py`,
  `packs/audit/directives/agent-steering-accounting/lib/extract.py`,
  `packs/audit/directives/agent-steering-accounting/lib/conf.py`,
  `packs/audit/directives/agent-steering-accounting/lib/argv.py`,
  `packs/audit/directives/agent-steering-accounting/hooks/pre-commit.sh`,
  `packs/audit/directives/agent-steering-accounting/runtimes/claude-code.sh`, and
  `packs/audit/directives/agent-steering-accounting/defaults.conf`. The commit
  hook now makes no `claude -p` / network call.
- **Make `## Steering` a fresh-context sub-agent attestation (B).**
  `packs/audit/directives/agent-steering-accounting/directive.yaml` declares a
  `subagent:` block (`section: Steering`, `inputs: [transcript, receipt]`,
  `isolation: shared`) and flips `hook:` from `commit-msg` to `pre-commit` so the
  attestation batches with the other pre-commit attestations;
  `packs/audit/directives/agent-steering-accounting/check.sh` runs `validate-dir`
  and gates the `## Steering` attestation on receipts added in the change set.
- **Rewrite the steering directive files (B).** Rewrote
  `packs/audit/directives/agent-steering-accounting/constitution.md`,
  `packs/audit/directives/agent-steering-accounting/README.md`, and
  `packs/audit/directives/agent-steering-accounting/evals/test.sh`;
  `lib/ledger.py` and `lib/receipt_io.py` stay.
- **Resolve the token session from `CLAUDE_CODE_SESSION_ID` (C).**
  `packs/audit/directives/agent-token-accounting/runtimes/claude-code.sh`
  resolves `<projects>/<cwd>/$CLAUDE_CODE_SESSION_ID.jsonl` (then a session-id
  filename search) before falling back to the newest-mtime guess — so a throwaway
  classifier transcript can no longer be mistaken for the real session.
- **Converge the sub-agent-judgment docs (D).** Rewrote
  `kit/references/SUBAGENT_ATTESTATION.md` to present the unified `subagent:`
  mechanism (attest + sweep modes); added a convergence note to
  `kit/references/SWEEP_FLOW.md`; updated `kit/references/LIB_API.md`,
  `kit/references/DIRECTIVE_AUTHORING.md`, `kit/references/PACK_AUTHORING.md`, and
  `kit/references/DIRECTIVES_CATALOG.md`. Regenerated the site Reference tab
  (`docs/reference/authoring-directives.mdx`, `docs/reference/authoring-packs.mdx`,
  `docs/reference/directive-catalog.mdx`). Refreshed narrative docs `README.md`,
  `docs/concepts/audit-chain.mdx`, `docs/concepts/limitations.mdx`, and the
  `packs/audit/pack.yaml` header comment. Added `subagent_attest` /
  `attestation_remediation` coverage to `scripts/test-runtime.sh` and a
  dispatcher-wiring assertion to `scripts/test-hooks-sh.sh`.

### Files touched (full paths, for coverage)

- `kit/assets/dot-governance/lib.sh`, `kit/assets/dot-governance/run.sh`, `kit/assets/packs/lib/hooks.sh`
- `packs/audit/directives/receipt-per-issue/directive.yaml`, `packs/audit/directives/receipt-per-issue/check.sh`
- `.governance/packs/duaility/governance-kit/directives/layer-boundaries/directive.yaml`, `.governance/packs/duaility/governance-kit/directives/layer-boundaries/check.sh`
- `packs/audit/directives/agent-steering-accounting/directive.yaml`, `packs/audit/directives/agent-steering-accounting/check.sh`, `packs/audit/directives/agent-steering-accounting/constitution.md`, `packs/audit/directives/agent-steering-accounting/README.md`, `packs/audit/directives/agent-steering-accounting/evals/test.sh`
- `packs/audit/directives/agent-token-accounting/runtimes/claude-code.sh`
- `packs/audit/pack.yaml`
- `kit/references/SUBAGENT_ATTESTATION.md`, `kit/references/SWEEP_FLOW.md`, `kit/references/LIB_API.md`, `kit/references/DIRECTIVE_AUTHORING.md`, `kit/references/PACK_AUTHORING.md`, `kit/references/DIRECTIVES_CATALOG.md`
- `docs/reference/authoring-directives.mdx`, `docs/reference/authoring-packs.mdx`, `docs/reference/directive-catalog.mdx`
- `README.md`, `docs/concepts/audit-chain.mdx`, `docs/concepts/limitations.mdx`
- `scripts/test-runtime.sh`, `scripts/test-hooks-sh.sh`

## Out of scope

- Wiring the **sweep** engine to read `subagent:` directly — the open question in
  the issue, deliberately left as the immediate follow-up (leaning follow-up to
  keep this change on the commit lane + steering + the token fix). The schema is
  designed so the sweep lane consumes the same declaration unchanged.
- A Codex runtime adapter for the steering sub-agent's transcript.
- Bumping `min_governance_kit` — the migrated checks fall back to
  `require_attestation` when the newer helper is absent, so the `0.10.0` floor holds.

## Decisions

- **Rows stay under `## Accounting` → `### Steering`; the attestation verdict goes
  in a top-level `## Steering` section.** The issue says "keep `lib/ledger.py`
  validate-dir," so the row location and validator are unchanged (existing
  receipts stay valid). The sub-agent writes the rows (via `ledger.py append-row`)
  and the verdict; `check.sh` gates the verdict's presence plus row shape.
- **`subagent_attest` is a new gate; `require_attestation` is untouched.** Rather
  than rewrite the shipped, test-covered `require_attestation`, the
  declaration-driven path is additive and the migrated checks guard with
  `declare -F subagent_attest`, falling back to `require_attestation` on older
  runtimes. This keeps the dogfood (one release behind) green.
- **`attestation_remediation` formats in stdlib python, not bash.** The grouped
  instruction munges strings full of backticks and quotes across US-joined
  fields; bash quoting made this fragile, and python3 is already present whenever
  an attestation registered.
- **Steering's `## Steering` attestation is change-set scoped** (only receipts
  added in the change set), matching `receipt-per-issue`'s `## Audit`, so the
  three shared attestations batch into one sub-agent on a newly added receipt.

## Verification

```sh
# Full kit-internal suite (packs, evals, runtime, hooks, schema, conf-sync)
bash scripts/test.sh

# Migrated + rewritten directive evals specifically
bash packs/audit/directives/receipt-per-issue/evals/test.sh
bash packs/audit/directives/agent-steering-accounting/evals/test.sh

# Dogfood governance on the working tree
bash .governance/run.sh

# Docs site Reference tab is regenerated from kit/references
npm run docs:gen:check
```

All green: `scripts/test.sh` reports all kit-internal layers passing
(`test-runtime` 94 assertions, `test-hooks-sh` 84), both directive evals pass,
`.governance/run.sh` reports all directives passing, and `docs:gen:check`
reports the reference pages up to date.

## Audit

Fresh-context sub-agent audit against the staged diff and the issue (the auditor
read `git diff --staged`, this receipt, `gh issue view 325`, and `ARCHITECTURE.md`;
it did not write the change):

- PASS — Every file in `git diff --staged --name-status` (35 paths) has its basename named in `## What changed`; deletions (classifier.py, extract.py, conf.py, argv.py, hooks/pre-commit.sh, steering runtimes/claude-code.sh, defaults.conf) and modifications (lib.sh, run.sh, hooks.sh, both migrated directive.yaml/check.sh, token runtime, docs, tests) are all described and match the diff hunks.
- PASS — "add `subagent_attest` + `attestation_remediation`; wire run.sh and dispatcher once" is realized: `lib.sh` defines `_subagent_yaml`/`resolve_subagent_input`/`subagent_attest`/`attestation_remediation`; `run.sh` and `hooks.sh` each source lib.sh and call `attestation_remediation "$ATTEST_LEDGER"` once after the check loop.
- PASS — "Migrate receipt-per-issue `## Audit` and layer-boundaries `## Layer boundaries`" is realized: both `directive.yaml`s gain a `subagent:` block and both `check.sh`s call `subagent_attest "$f"` with a `declare -F` fallback to `require_attestation`.
- PASS — "delete classifier/populator/runtime readers; `## Steering` becomes attestation gating presence + validate-dir" is realized: the steering lib/hook/runtime files plus defaults.conf are status-D deletions, and steering `check.sh` runs `lib/ledger.py validate-dir` and gates `## Steering` via `subagent_attest`.
- PASS — "token runtime resolves session from `CLAUDE_CODE_SESSION_ID` first, mtime fallback" is realized: `agent-token-accounting/runtimes/claude-code.sh` adds an identity-pinned `${CLAUDE_CODE_SESSION_ID}.jsonl` lookup ahead of the unchanged newest-mtime block.
- PASS — The `## Checklist` mirrors the issue's Work-items A–D and Acceptance; the only divergence was wording-level (the steering `hook` flip), now named explicitly in `## What changed`.

## Layer boundaries

Fresh-context sub-agent verdict against the staged diff and the layer model in
`ARCHITECTURE.md`:

- PASS — Shared runtime orchestration logic lands in the layer that owns it: the four new helpers are added to `kit/assets/dot-governance/lib.sh`, the hook generator change is in `kit/assets/packs/lib/hooks.sh`, and the run-time invocation is in `kit/assets/dot-governance/run.sh` — no engine code placed under `packs/`.
- PASS — Directive content stays in pack layers: the migrated/rewritten directives touch only `packs/audit/directives/<id>/` and the repo-local `.governance/packs/duaility/governance-kit/directives/layer-boundaries/` (a `source:`-less pack, so hand-editing is legitimate per AGENTS.md); reference docs stay under `kit/references/`.
- PASS — No upward dependency across a layer edge: pack `check.sh` files consume the kit's `lib.sh` helpers (downward kit→pack consumption), guarded by `declare -F` so a pack never hard-depends on a newer kit; the engine in `lib.sh`/`run.sh`/`hooks.sh` does not reach into any specific directive.
- PASS — New shared logic lives once: the orchestrator is defined a single time in `lib.sh` and consumed by both `run.sh` and the generated dispatcher; typed-token resolution is centralized in `resolve_subagent_input` rather than re-implemented per directive.

## Steering

Fresh-context review of this session's steering footprint (the operator's only
inputs were two identical `/goal` directives setting the task; the work then ran
to completion):

- PASS — No human-steering events. The session transcript carries no interrupt sentinel (`[Request interrupted by user`) and no mid-task correction redirecting the agent; the operator set the goal and did not steer. No steering rows are recorded for this receipt, which is the correct, faithful result.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-fdac6438-9a4-1781719261-1 | claude-code | fdac6438-9a43-427c-a036-e06dcc311136 | #325 | claude-opus-4-8 | 7006 | 33246 | 30540 | 368 | 40620 | 0.2673 | 7006 | 33246 | 30540 | 368 | feat(audit): unified sub-agent judgment infra, steering-as-attestation, determin |
| claude-code-e7d8f0db-5fd-1781719373-1 | claude-code | e7d8f0db-5fd1-4849-804b-ce23ae6f78db | #325 | claude-opus-4-8 | 62075 | 1251702 | 69023854 | 561211 | 1874988 | 56.6757 | 62075 | 1251702 | 69023854 | 561211 | feat(audit): unify sub-agent judgment, steering-as-attestation, deterministic to |

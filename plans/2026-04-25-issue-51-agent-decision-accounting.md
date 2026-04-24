# Agent Decision Accounting — issue-51

## Goal

Ship a new `agent-decision-accounting` directive under the
`duaility/agent-governance` pack that gives repos an append-only ledger
(`DECISIONS.md`) of **load-bearing human decisions** made during
agent-driven development — with the divergence signal between the
agent's lean and the human's choice captured in a fixed vocabulary and
mirrored into commit trailers that survive squash merges. Implements
[governance-kit#51](https://github.com/Duaility/governance-kit/issues/51)
(synthesizing the earlier brainstorm in [#46](https://github.com/Duaility/governance-kit/issues/46)).

## Design decisions resolved from the two issues

1. **Record every load-bearing decision, not just divergences.** #51
   proposed "append only on divergence" — we reverted to #46's stance.
   Override count without a baseline is uninterpretable; override rate,
   reframe rate, and time-to-override all need the denominator.
2. **Four-state vocabulary, not a binary flag.** `agreed` / `overrode` /
   `reframed` / `deferred` from #46. `reframed` is the single most
   valuable signal — it flags the agent's *question set* as broken, not
   its lean accuracy. A binary `divergence: bool` collapses that.
3. **Paired trailers: `Decision-Key:` + `Decision-Diverged: M/N`.** Both
   from #46. The counter surfaces divergence rate in `git log` without
   parsing the ledger, and both trailers are mutually required to avoid
   silent drift.
4. **Opt-in, not in `agent-governance.standard` preset.** Unlike
   `agent-token-accounting`, divergence capture requires agent-side
   discipline (structurally declaring the lean); auto-enrolling every
   repo would produce empty ledgers. Promote into the preset once
   divergence rates prove the signal is worth the install cost.
5. **Runtime-agnostic with no per-runtime reader.** Cost accounting
   reads transcripts because the runtime emits tokens for free.
   Divergence is a deliberate agent action — the agent writes the
   ledger row at question time. Same markdown format works identically
   on Claude Code and Codex; no `runtimes/<name>.sh` sibling.
6. **`cost-key` cross-column, soft-coupled.** Column exists; cross-check
   runs only when `COSTS.md` is present. The directive does not require
   `agent-token-accounting` to be installed.
7. **Placement in `agent-governance` pack, not `core` or a new pack.**
   Only makes sense where every tree-change is agent-driven.

## Ledger schema (11 columns)

```
| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
```

- `diverged ∈ {agreed, overrode, reframed, deferred}`
- `phase ∈ {scoping, plan-review, pr-review, post-merge}`
- `cost-key` optional; resolves to a `COSTS.md` row when set.

## Files landed

- `extensions/packs/agent-governance/directives/agent-decision-accounting/`
  - `directive.yaml` — `surface: change-set`, `hook: commit-msg`, `recommended: false`.
  - `constitution.md` — Directive / Rationale / Enforced by / Exceptions.
  - `check.sh` — Mode A (commit-msg) + Mode B (CI walk), plus optional
    `COSTS.md` cross-ref.
  - `lib/ledger.py` — parse / validate / find-by-decision-key (stdlib-only).
  - `lib/trailers.py` — parse `Decision-Key` + `Decision-Diverged`,
    cross-check against a ledger snapshot.
  - `install-assets/DECISIONS.md` — seed file with header + column schema.
  - `evals/test.sh` — six assertions (two pass, four fail) exercising
    trailer-ledger cross-check, exemption paths, and ledger vocab.

## Follow-ups landed in this PR (second commit)

- Reference doc `governance/references/AGENT_DECISION_ACCOUNTING.md`
  with Codex + Claude Code worked examples for the question-ask contract.
- Catalog entry in `governance/references/DIRECTIVES_CATALOG.md`.
- Broadened evals from 6 → 13 assertions: adds bad-phase, duplicate-key,
  bad-column-count, bad-issue-format, dangling-cost-key,
  cost-key-resolved, and cost-key-no-costs-md cases.

## Deferred to a later issue

- Decision on whether a `governance decision record` verb is worth
  adding, or whether pure hook+agent-write stays the path.
- Promotion into `agent-governance.standard` preset once divergence
  rates prove the install cost is justified.
- Aggregation / analytics tooling over `DECISIONS.md`.
- Comment-thread (non-commit) decision capture.
- Machine-readable `replaces:` column for reconstructing
  reframe → replacement question chains.

## Acceptance

- [x] Directive folder populated with required files (yaml, check, constitution, lib, install-assets, evals).
- [x] `bash tests/governance/run.sh` passes with the new folder in tree.
- [x] `bash scripts/test-packs.sh` passes the new directive's evals (6/6 assertions).
- [x] `check.sh` rejects: wrong numerator, missing ledger key, trailer inconsistency (only one of the pair).
- [x] `check.sh` accepts: no trailer, revert commits, merge commits, consistent trailer+ledger.
- [x] `lib/ledger.py validate` flags bad `diverged`, bad `phase`, non-unique keys, bad column count.
- [x] Reference doc + catalog entry landed.

## Validation

- `bash tests/governance/run.sh` — green.
- Manual end-to-end in `/tmp/dec-test` — six scenarios (pass, bad numerator,
  missing key, one-of-pair, no trailer, revert) all produce the expected
  outcome.

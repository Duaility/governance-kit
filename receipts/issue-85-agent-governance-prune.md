# Receipt: prune agent-governance pack — decouple steering accounting; retire pr-required directive

Issue: [#85](https://github.com/Duaility/governance-kit/issues/85)

## Checklist

- [x] Decouple `agent-steering-accounting` from `agent-token-accounting`
- [x] `prepare-commit-msg.sh` stamps zero defaults when handoff absent
- [x] Eval coverage demonstrates independence and universal contract
- [x] `pr-required-when-checklist-complete` directive is retired entirely
- [x] Pack `minimal` preset drops the retired directive
- [x] `pr-review-required-when-pr-ready` no longer references the retired sibling
- [x] Reference docs and READMEs updated
- [x] Two evolution-log entries appended
- [x] Pack source and dogfood install consistent
- [x] Smoke tests pass

## What changed

Two cleanups to the `duaility/agent-governance` pack, bundled because both prune directive surface that surfaced as friction during dogfooding.

### Part 1 — Decouple `agent-steering-accounting` from `agent-token-accounting`

The directive previously gated enforcement on the presence of an `Agent:` trailer (produced by `agent-token-accounting`), so commits without it silently passed. That contradicted the repo's stance that all code is agent-authored, made the directive parasitic on a sibling it was advertised as independent of, and surfaced as an internal "non-agent commit → exempt" branch in `lib/trailers.py` (the kind of internal gate the project rule against per-tier gates explicitly forbids — installation is the gate).

New shape: every non-merge, non-revert commit stamps the `Steer-Count` / `Steer-Types` / `Steer-Tiers` triple, period.

- `lib/trailers.py` drops the `is_agent` branch entirely and the "Steer-* on non-agent commit → wrong shape" violation; every in-scope commit must carry the triple.
- `hooks/prepare-commit-msg.sh` no longer silently no-ops when no handoff is present — it stamps `Steer-Count: 0` / `Steer-Types: none` / `Steer-Tiers: none` defaults so a commit made outside a recognised agent runtime still satisfies the contract.
- `hooks/pre-commit.sh` is unchanged in behavior: it still requires a runtime + transcript to *append rows*, but a missing handoff no longer leaks through to a missing-trailer commit. Header docstring rewritten to describe the new always-stamp contract.
- The constitution snippet's `**Directive**` opener changes from "Every agent-authored commit (one carrying an `Agent:` trailer from `agent-token-accounting`)" to "Every non-merge, non-revert commit", with an explicit "independent of `agent-token-accounting`" sentence; the `**Exceptions**` line drops the "outside a recognised agent runtime → exempt" carve-out and notes the prepare-commit-msg zero-default fallback.
- Eval coverage: Case 5 relabelled `missing-summary` (was `missing-summary-agent`); Case 7 flips from "non-agent commit, no Steer-* → exempt pass" to "non-agent commit, summary triple stamped → pass" (demonstrates independence); a new Case 11 "non-agent commit, no triple → fail" demonstrates the universal contract.
- `governance/references/AGENT_STEERING_ACCOUNTING.md` updated to match (Trailer schema, "no Agent gate" paragraph, prepare-commit-msg flow diagram, "every in-scope commit" phrasing in the commit-msg cross-checks list).
- `governance/references/DIRECTIVES_CATALOG.md` row for `agent-steering-accounting` reworded to drop the `Agent:` qualifier.

### Part 2 — Retire `pr-required-when-checklist-complete`

The directive demanded an open PR exist as soon as HEAD's receipt had ≥1 `- [x]` and zero `- [ ]` items. In practice the gate fired during natural mid-work states — the agent finishes the receipt's checklist locally, keeps iterating, and the post-commit advisory plus the CI hard-fail kept demanding a PR for branches that weren't ready to be reviewed yet. The trigger condition is also a poor proxy for "ready for code review": the checklist completes when the *receipt* says the work is done, not when the author wants eyes on it.

Removed surfaces:

- The directive folder under `extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/` and the dogfood mirror under `tests/governance/directives/pr-required-when-checklist-complete/` are deleted entirely.
- The `agent-governance` pack's `minimal` preset drops the id (now `receipt-per-issue` + `commit-issue-receipt-match`).
- The `### pr-required-when-checklist-complete` subsection is removed from `CONSTITUTION.md`.

Cross-references updated:

- `extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready/check.sh` and `constitution.md` carried a "Composition with `pr-required-when-checklist-complete`" paragraph in their rationale; both rewritten to describe the directive's own trigger axis without referencing the retired sibling. Mirrored to the dogfood install.
- User-facing docs updated: `README.md` catalog row drops the retired id; `extensions/packs/agent-governance/README.md` auxiliary section + preset table re-counted (minimal: 3→2, standard: 7→6); `governance/references/DIRECTIVES_CATALOG.md` catalog row + `minimal` preset row updated.

The kit's `post-commit` hook infrastructure (`packctl.py`'s `HOOKS` set, `hooks.sh`'s `_emit_post_commit`, the dispatcher generator) is kept — `pr-review-required-when-pr-ready` still uses it, and the kind is generally useful for future advisory directives.

### Cross-cutting

Two evolution-log entries dated 2026-04-29 appended to `CONSTITUTION.md` — one per change — naming the surfaces touched and the rationale.

## Out of scope

- **Filing two separate issues / two separate PRs** for the two cleanups. Both touch the agent-governance pack surface and were authored in the same session; bundling keeps the review story coherent without losing separability (each evolution-log entry stands alone, and reviewers can read each part independently).
- **Migrating the existing `.governance-kit/installed-packs.yaml` manifest** for either change. The retired directive was never in the manifest (a pre-existing inconsistency from when it was added), and the steering accounting changes don't alter the directive's id or installed path. No manifest entry to update.
- **Rewriting historical evolution-log entries** (lines 190, 192–194 in `CONSTITUTION.md`) that reference `pr-required-when-checklist-complete` by name — they describe what was true at the time, per the project's "don't rewrite history" convention.
- **Editing receipt files for prior issues** (`receipts/issue-69-*.md`, `issue-71-*.md`, etc.) that reference the retired directive — same convention.
- **Editing `COSTS.md` or `STEERING.md` historical rows** that name the retired directive in a commit subject — append-only ledgers are immutable.
- **Adding a backwards-compatibility alias** for `pr-required-when-checklist-complete` so existing installs keep working — explicitly skipped per the project's V0 stance (no stability promise yet).
- **Adding a `### pr-review-required-when-pr-ready` subsection to `CONSTITUTION.md`** to mirror the dogfood directive — that subsection was never authored (a pre-existing oversight from PR #79/#80 captured in the #83 receipt). Out of scope for this prune.

## Verification

A reviewer can confirm the change is complete by checking:

1. **`agent-steering-accounting` is independent of `agent-token-accounting`.** Read `extensions/packs/agent-governance/directives/agent-steering-accounting/lib/trailers.py`: the `validate` function has no `is_agent` branch and no "Steer-* on non-agent commit" violation. The module docstring's contract paragraph names "Every non-merge, non-revert commit" with an explicit "independent of `agent-token-accounting`" sentence.
2. **`prepare-commit-msg.sh` stamps zero defaults when handoff absent.** Read `extensions/packs/agent-governance/directives/agent-steering-accounting/hooks/prepare-commit-msg.sh`: the `[[ -f "$HANDOFF" ]] || exit 0` early-exit is gone; the source-and-cleanup is wrapped in `if [[ -f "$HANDOFF" ]]`; the trailer printing block always runs and uses `${AGENT_STEERING_COUNT:-0}` / `${AGENT_STEERING_TYPES:-none}` / `${AGENT_STEERING_TIERS:-none}` defaults.
3. **Eval coverage demonstrates independence and universal contract.** `bash extensions/packs/agent-governance/directives/agent-steering-accounting/evals/test.sh` shows 11 cases including `no-agent-with-triple` (pass — non-agent commit with summary triple satisfies the contract) and `bare-commit-no-triple` (fail — non-agent commit without the triple violates the universal contract).
4. **`pr-required-when-checklist-complete` directive is retired entirely.** `extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/` and `tests/governance/directives/pr-required-when-checklist-complete/` do not exist. `grep -rln pr-required-when-checklist-complete` returns only historical record (evolution-log entries, ledger files, prior receipts).
5. **Pack `minimal` preset drops the retired directive.** `extensions/packs/agent-governance/pack.yaml` `minimal.directives` is `[receipt-per-issue, commit-issue-receipt-match]`.
6. **`pr-review-required-when-pr-ready` no longer references the retired sibling.** Read its `check.sh` header and `constitution.md` (pack source + dogfood mirror): the "Composition with `pr-required-when-checklist-complete`" paragraph is gone, replaced by a description of its own trigger axis.
7. **Reference docs and READMEs updated.** `README.md` catalog table has no row for the retired id. `extensions/packs/agent-governance/README.md` auxiliary section lists two directives (review-gate + steering); preset table shows `minimal: 2` / `standard: 6`. `governance/references/DIRECTIVES_CATALOG.md` catalog table has no row for the retired id and the `minimal` preset row lists `receipt-per-issue, commit-issue-receipt-match`.
8. **Two evolution-log entries appended.** `CONSTITUTION.md` carries two 2026-04-29 entries — one for the steering-accounting decoupling, one for the pr-required retirement — each describing the surfaces touched.
9. **Pack source and dogfood install consistent.** `diff -r --brief extensions/packs/agent-governance/directives/agent-steering-accounting tests/governance/directives/agent-steering-accounting | grep -v evals\|install-assets` returns nothing. Same for `pr-review-required-when-pr-ready`.
10. **Smoke tests pass.** `bash scripts/test-packs.sh` reports `2 pack(s), 15 directive(s), 15 eval(s) passed` (was 16 before — `pr-required-when-checklist-complete` removed). `bash tests/governance/run.sh` reports `all 15 directive(s) passed` (was 1 failure before — `pr-required-when-checklist-complete` itself).
11. **This commit satisfies `commit-issue-receipt-match`.** The commit's `(#85)` anchor matches the `issue-85` token on this receipt file.

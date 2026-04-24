<!-- governance: allow-plan-validation legacy -->
<!-- last-verified: 2026-04-23 -->

# 2026-04-23 — Add `commit-issue-plan-match`, retire `plan-captured`

## Goal

Close the hole where `conventional-commits` (commit → `(#N)`), `plan-per-issue`
(plan file → `issue-<N>`), and `plan-captured` (substantive commits touch some
plan) each check one link in the issue-driven chain but never cross-check the
three against each other. A commit claiming `(#15)` that touches only
`plans/…-issue-42-….md` currently passes all three rules. The new rule cross-
validates the commit's issue number against the `issue-<N>` tokens on the
plan files the commit actually touched. In the same amendment, retire
`plan-captured` — its "substantive changes touch a plan" obligation is
subsumed and strengthened by the new rule (which also checks the number
matches), its "`plans/` exists with ≥1 `.md`" check is trivially implied
once every commit touches a plan, and its `## Goal` / `## Steps` structure
check is stylistic.

Closes [#19](https://github.com/Duaility/governance-kit/issues/19).

## Steps

1. **Author `tests/governance/rules/commit-issue-plan-match.sh`**:
   - Mode A (commit-msg hook): take a msg-file path, read the subject and the
     staged diff. Validate the pending commit.
   - Mode B (CI / run.sh): walk `merge-base(HEAD, default-branch)..HEAD` and
     validate each non-merge, non-revert commit using its message and
     `git diff-tree`.
   - Per-commit check:
     1. Extract the trailing `(#N)` from the subject (already guaranteed by
        `conventional-commits`; emit a violation if absent rather than
        silently passing).
     2. Collect `issue-<N>` tokens from every `plans/*.md` added or modified
        in the change set.
     3. If the subject's issue number is not among the plan's numbers → fail
        and name both values.
     4. If the commit touches no `plans/*.md` → fail (subsumes the plan-touch
        obligation `plan-captured` used to enforce).
   - Exceptions: merge commits and revert commits (mirror
     `conventional-commits` / `agent-token-accounting`). Per-commit waiver:
     `governance: allow-commit-issue-plan-match <reason>` anywhere in the
     commit body.
2. **Delete `tests/governance/rules/plan-captured.sh`**.
3. **Amend `CONSTITUTION.md`**:
   - Remove the `### plan-captured` invariant subsection.
   - Add a `### commit-issue-plan-match` invariant subsection in the
     issue-driven cluster (next to `conventional-commits` and
     `plan-per-issue`).
   - Append a single Evolution Log line covering both halves of the
     amendment.
4. **Wire the new rule into `.githooks/commit-msg`** so the pending commit's
   subject is cross-checked against its staged plan changes before the
   commit lands — mirroring how `conventional-commits` and
   `agent-token-accounting` are wired.
5. **Update the governance-gardener reference** in
   `governance-gardener/SKILL.md` that names `plan-captured` by rule —
   rewrite it to reference the now-live rule set. Leave the
   `<!-- governance: allow-plan-captured -->` waiver line in the report
   template as a harmless no-op (per the issue's guidance: retired-rule
   waivers stay as comments). Waiver lines in `COSTS.md` and
   `scripts/governance/lib/ledger.py` similarly stay.
6. **Run `bash tests/governance/run.sh`** — all remaining rules pass, the
   new rule passes on this commit (subject `(#19)`, plan
   `plans/2026-04-23-issue-19-commit-issue-plan-match.md` carries
   `issue-19`), and `plan-captured` is gone from the rule count.

## Rationale for bundling

Governance's cardinal rule: constitution + enforcing test land together in
one commit. The same logic applies to a replace/retire pair — the rule that
subsumes lands with the rule that retires, in one commit, or the
intervening state is a lie (both exist, only one adds safety). Splitting
this into two PRs doubles review burden with zero safety gain.

## Test plan

- [ ] Commit `(#15)` touching `plans/…-issue-15-….md` → pass.
- [ ] Commit `(#15)` touching `plans/…-issue-42-….md` → fail, names both
      numbers.
- [ ] Commit `(#15)` touching no `plans/*.md` → fail.
- [ ] Merge commit → skipped.
- [ ] Revert commit → skipped.
- [ ] Body carries `governance: allow-commit-issue-plan-match <reason>` →
      skipped.
- [ ] `bash tests/governance/run.sh` is green on `main` after the amendment
      lands; `plan-captured.sh` is gone; no tracked doc references the
      retired rule as a live invariant.

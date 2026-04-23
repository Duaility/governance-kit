<!-- governance: allow-plan-per-issue predates-rule -->

# 2026-04-22 — Add `issues-tracked` governance rule

## Goal

Add a rule that requires `QUALITY.md` at the repo root to track bugs and quality issues. Fills the gap where observations discovered mid-stream (linter limitations, shipped-asset bugs, missing enforcement) had no durable home — they surfaced in session and would otherwise evaporate.

## Steps

1. Author `tests/governance/rules/issues-tracked.sh` asserting:
   - `QUALITY.md` exists at repo root.
   - Has a top-level `# ` heading.
   - Has `## Open` and `## Resolved` sections.
2. Syntax-check + smoke-test. Expect first-run fail (no `QUALITY.md` yet).
3. Seed `QUALITY.md` with the real open/resolved issues from this dogfood session:
   - **Open**: hooks-not-enforced-by-rule; linter doesn't skip inline code spans.
   - **Resolved**: governance.yml missing permissions (patched in PR #2); RULES_CATALOG prose triggering linter (patched in PR #2).
4. Amend `CONSTITUTION.md`: new Invariants subsection + Evolution Log entry.
5. Stage rule + constitution + QUALITY.md + this plan file. Commit via hooks. Push to PR #2.

## Notes

- Structure-only check, like `plan-captured`. Entry-format enforcement (dates, IDs, linked commits) is a candidate follow-up rule if log drift becomes a problem.
- `QUALITY.md` is named separately from a CHANGELOG — those are different concerns: CHANGELOG is what shipped to users, QUALITY is what we know is wrong.

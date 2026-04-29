<!-- governance: allow-plan-validation legacy -->
# Require One Plan File Per Issue

## Goal

Add a new governance rule `plan-per-issue` that binds every `plans/*.md` file
to a single GitHub issue via an `issue-<N>` token in the filename, and rejects
duplicate plans for the same issue. This addresses issue
[#15](https://github.com/Duaility/governance-kit/issues/15): "Create a new
constitution rule which enforces a single plan file for each issue."

## Steps

1. Add `.governance/rules/plan-per-issue.sh` — checks filenames, detects
   duplicates, supports a per-file `governance: allow-plan-per-issue` waiver so
   grandfathered plans do not block the rule.
2. Insert a `plan-per-issue` **Invariants** subsection in `CONSTITUTION.md`
   (after `plan-captured`) and append an **Evolution Log** entry dated
   2026-04-23.
3. Grandfather the nine existing pre-rule plan files by adding an HTML-comment
   waiver line explaining they predate the convention.
4. Smoke-test: run `bash .governance/rules/plan-per-issue.sh` and the
   full `.governance/run.sh` suite; confirm the rule passes against the
   current tree once waivers are in place.
5. Stage only the amendment artifacts (rule script, constitution edits, the
   nine waivered plan files, this plan).

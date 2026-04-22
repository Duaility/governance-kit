# 2026-04-22 — Add `plan-captured` governance rule

Plan for the amendment that introduces the `plan-captured` rule. Captured here to satisfy the rule it creates — the first commit under the new regime should itself have a plan on disk.

## Goal

Add a governance rule that enforces the presence of plan documents in the repo, so that for every substantive change a reviewer can read the plan the implementer followed. The diff tells us *what* changed; plans/ tells us *why it took this shape*.

The rule is named `plan-captured`. It is a directory-and-structure check, not a commit-trailer check — we want the cost of compliance low enough that people actually do it, and a convention of "one markdown file per substantive effort" is cheaper than policing commit messages.

## Steps

1. Author `tests/governance/rules/plan-captured.sh` that asserts:
   - `plans/` exists at the repo root.
   - At least one tracked `plans/*.md` file exists.
   - Every tracked `plans/*.md` has a top-level `# ` heading, a `## Goal` section, and a `## Steps` section.
   - Per-file waiver: a line matching `governance: allow-plan-captured` exempts a file.
2. Syntax-check and smoke-test the script. Expect it to fail on first run (no `plans/` yet).
3. Seed `plans/` with this very document, so the smoke test passes and the rule's own introduction is captured by the rule.
4. Amend `CONSTITUTION.md`:
   - Insert a new **Invariants** subsection for `plan-captured`.
   - Append an **Evolution Log** entry dated 2026-04-22.
5. Stage the three artifacts (rule script, constitution edits, this plan file) plus the new `plans/` path and hand back to the user.
6. **Out of scope for this amendment** — a separate follow-up will add a `changelog-current` rule that enforces CHANGELOG.md is updated on substantive changes. Conflating plan capture and release notes would muddy both.

## Notes

- Trailer-based enforcement was considered and rejected: too heavy, hard to backfill, and the signal is fragile (typos, forgotten trailers). A directory convention plus soft PR-review enforcement is the chosen layering.
- The rule does not tie individual plans to individual commits. If we want that tightness later, we can add a follow-up `plan-linked` rule that parses a `Plan:` trailer and checks it resolves.
- Per-file waiver is the escape hatch for unusual plan files (templates, partial drafts kept under version control).

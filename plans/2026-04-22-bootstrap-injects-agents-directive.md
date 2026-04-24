<!-- governance: allow-plan-validation legacy -->
<!-- governance: allow-plan-per-issue predates-rule -->

# 2026-04-22 — Bootstrap injects the AGENTS.md directive

## Goal

Make the `governance-bootstrap` skill responsible for placing the "Rules to follow" directive into `AGENTS.md`, not just adding the Compliance section to `CONSTITUTION.md`. The constitution is the rule; AGENTS.md is the routing pointer that gets agents to the rule. Both must propagate to every bootstrapped repo.

## Steps

1. Add a new shipped asset `governance-bootstrap/assets/AGENTS.directive.md` containing the directive snippet, leading with the marker comment `<!-- governance: rules-to-follow -->` so injection can be made idempotent.
2. Add a new **Step 4b** to `governance-bootstrap/SKILL.md` between the constitution-writing step and the runner-installation step:
   - Always grep for the marker before inserting (idempotent).
   - If `AGENTS.md` exists and lacks the marker: inject after the H1 + intro paragraph, before the first `##`.
   - If `AGENTS.md` is missing AND the user picked `agents-md-exists`: scaffold a stub with the directive included.
   - If `AGENTS.md` is missing AND the rule was not picked: skip silently.
3. Add the marker comment to **this repo's** `AGENTS.md` so it matches the new convention (re-running bootstrap on this repo would now skip cleanly).
4. Run governance suite (no rule changes — should still be 12/12).
5. Stage skill asset + SKILL.md + AGENTS.md + plan doc, commit, push to PR #3.

## Notes

- The marker comment is the authoritative idempotency check. Do not rely on a substring match against the directive text — users may legitimately edit the prose, and false-negative duplicate inserts would be worse than false-positive skips.
- Stub creation only happens when `agents-md-exists` was selected. Creating a file the user didn't ask for is presumptuous; respecting the rule selection keeps the skill predictable.
- This is a skill enhancement, not a constitutional amendment. No new rule, no test changes, no Evolution Log entry.

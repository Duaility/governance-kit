<!-- governance: allow-plan-per-issue predates-rule -->

# 2026-04-22 — Add Compliance directive (AGENTS.md + CONSTITUTION.md + bootstrap template)

## Goal

Make the obligation to follow the constitution **prescriptive** rather than descriptive, in three places:

1. CONSTITUTION.md gets a new top-level **Compliance** section that names the audience (humans, agents, automation) and states they must satisfy every principle, guideline, and invariant in the document — not just the mechanically enforced invariants.
2. AGENTS.md gets a "Rules to follow" directive at the top that points to the Compliance section. Stale "currently 10 invariants" phrase is removed (we have 12 now and it'll rot again).
3. The `governance-bootstrap` skill's CONSTITUTION template is updated so every bootstrapped repo inherits the Compliance section automatically.

Also: add `<!-- last-verified: 2026-04-22 -->` stamps to AGENTS.md and CONSTITUTION.md so the gardener can detect drift on these critical docs (both are already in its baseline).

## Steps

1. Edit `governance-bootstrap/assets/CONSTITUTION.template.md` — insert Compliance section between the cardinal-rule callout and Principles.
2. Edit `governance-bootstrap/SKILL.md` (Step 4) so the skill knows the Compliance section is part of the template and shouldn't be re-invented.
3. Edit this repo's `CONSTITUTION.md` — same Compliance section, plus an Evolution Log entry.
4. Rewrite the top of `AGENTS.md`:
   - Add `<!-- last-verified: 2026-04-22 -->` stamp.
   - New `## Rules to follow` section as the first heading after the intro paragraph.
   - Trim "How governance works here" to remove the stale "10 invariants" line and avoid duplication.
5. Add `<!-- last-verified: 2026-04-22 -->` stamp to `CONSTITUTION.md`.
6. Run governance suite (12/12 should still pass — no new rule, just doc edits).
7. Stage everything + commit + push to PR #2.

## Notes

- Compliance is intentionally **not** a new invariant. It can't be mechanically checked ("did the agent actually follow the rules?" requires inspecting the diff against intent). It's a meta-statement, like the existing Principles section. Per the constitution itself: "If a rule cannot be mechanically checked, it does not belong [in Invariants]."
- The gardener watches AGENTS.md and CONSTITUTION.md via its built-in baseline — no `freshness.conf` change needed. Adding the stamp gives it something to compare against.
- QUALITY.md is **not** in the gardener's baseline. Adding it is a candidate follow-up (would need a `freshness.conf` entry).

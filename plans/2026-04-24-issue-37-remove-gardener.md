<!-- governance: allow-plan-validation legacy -->
# Plan — issue-37: Remove governance-gardener skill

Closes [#37](https://github.com/Duaility/governance-kit/issues/37).

## Goal

Retire the companion `governance-gardener` skill and cleanly detach every
reference to it from the rest of the kit. The gardener never reached
load-bearing status — the unified `governance` skill owns the write path
for lifecycle operations, and ad-hoc review/health-check questions are
better answered directly by the agent than routed to a parallel skill
with its own activation surface.

## Steps

1. **Delete the skill tree.** Remove `governance-gardener/` in full
   (SKILL.md, assets, references, eval fixtures).
2. **Top-level docs.** Drop the companion-skill row from `AGENTS.md`
   (table + repo layout + symlink snippet), the intro bullet from
   `README.md`, the "Surfaces" paragraph in `ARCHITECTURE.md`, and the
   signal / watched-scope / gardener-mode glossary entries in
   `GOVERNANCE_VOCABULARY.md`.
3. **`governance` skill + references.** Remove gardener routing rows
   from `governance/SKILL.md` (frontmatter + verb dispatch table) and
   from `VERBS.md`, `RULE_VERBS.md`, `INIT_FLOW.md`, `RULE_AMEND_FLOW.md`.
   Review / audit requests now fall through to "answer directly"
   rather than routing to a skill that no longer exists.
4. **Evals.** Update the negative-routing cases in
   `governance/evals/amend/evals.json`, `governance/evals/bootstrap/evals.json`,
   and `governance/evals/amend/files/README.md` so health-check prompts
   assert "answered directly without staging changes".
5. **Miscellaneous.** Strip gardener-specific commentary from
   `governance/assets/freshness.conf`, `.governance/freshness.conf`,
   the `governance/assets/packs/lib/install.sh` header comment, and the
   `SKILLS=` array in `scripts/eval-report.sh`.
6. **Verify.** `bash .governance/run.sh` passes; a repo-wide grep
   for `governance-gardener|gardener` returns only historical
   `plans/*.md` entries, which are intentionally left untouched as
   frozen records of past work.

## Non-goals

- Refactoring `scripts/eval-report.sh` to match the current unified
  eval layout under `governance/evals/{bootstrap,amend,reset}/`. The
  script was already stale before this change; fixing the layout
  mismatch is a separate task.
- Rewriting `plans/2026-04-22-governance-gardener.md` or any other
  historical plan. Plans are append-only records of what was decided
  at the time.

# Plan — issue-39: Roll harness-engineering lessons into existing rules

Closes [#39](https://github.com/Duaility/governance-kit/issues/39).

## Goal

Fold the durable ideas from OpenAI's Harness Engineering post into the
rules that already own the relevant policy surface, instead of spawning
one-off rules per insight. Two concrete strengthenings:

1. `core/required-docs` agents sub-check — AGENTS.md must be an explicit
   map to the repo's bedrock durable docs, not a standalone manual.
2. `agent-governance/plan-per-issue` — every tracked plan must carry a
   validation-intent section (`## Validation`, `## Verification`, or
   `## Acceptance`), so a reviewer can tell at a glance how the plan
   will be judged complete.

Draft names `agent-docs-map` and `plan-validation-evidence` are dropped —
they duplicate ownership the existing rules already have.

## Steps

1. **Decide ownership.** AGENTS.md presence already lives in
   `core/required-docs` — the `agents` sub-check is the right home for
   the map-shape tightening. Putting it in an agent-governance extension
   would split one file's shape across two rules.
2. **Strengthen the agents sub-check.** Require AGENTS.md to link to
   `CONSTITUTION.md` at minimum — the bedrock durable doc the same rule
   already mandates. Keep the existing bounded-length and
   minimum-internal-links checks. Update `check.sh`, `constitution.md`,
   and evals (new fail fixture: AGENTS.md without a CONSTITUTION.md
   link).
3. **Strengthen `plan-per-issue`.** Add a scan for `^##[[:space:]]+
   (Validation|Verification|Acceptance)\b`. Introduce a new per-file
   waiver `governance: allow-plan-validation` so existing plans can be
   grandfathered without touching the filename-token check's waiver.
   Update `check.sh`, `constitution.md`, and evals.
4. **Grandfather legacy plans.** Add
   `<!-- governance: allow-plan-validation legacy -->` to every plan in
   `plans/` that predates this rule and does not already include a
   validation-intent section. This keeps the repo green while the rule
   takes effect for new plans.
5. **Catalog + references.** Update
   `governance/references/RULES_CATALOG.md` to mention the new agents
   sub-check details and the validation-section requirement on
   `plan-per-issue`.
6. **Verify.** Run `bash scripts/test-packs.sh` and
   `bash tests/governance/run.sh` — both must pass.

## Validation

- `bash tests/governance/run.sh` exits 0 on this branch.
- `bash scripts/test-packs.sh` exits 0 — every rule eval (including the
  new fail fixtures for the strengthened checks) passes.
- New negative assertions exist in
  `governance/assets/packs/core/rules/required-docs/evals/test.sh` and
  `extensions/packs/agent-governance/rules/plan-per-issue/evals/test.sh`.
- No legacy plan file is reported as a violation — each is either
  updated or carries the `allow-plan-validation` waiver.
- The two `plan-per-issue` waivers are independent: `allow-plan-per-issue`
  alone must not silence the validation-section check. Covered by a
  dedicated fail eval (`filename-waiver-still-checks-validation`) plus a
  pass eval for the both-waivers case.

## Non-goals

- Standalone architecture-boundary rules. The issue explicitly defers
  these until there is a concrete checker.
- Tightening `issues-tracked` to grade domain/layer quality. Also
  deferred per the issue.
- Renaming or restructuring `AGENTS.md` on this or target repos beyond
  the link-to-CONSTITUTION.md requirement.

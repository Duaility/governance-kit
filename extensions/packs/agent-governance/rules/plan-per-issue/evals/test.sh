#!/usr/bin/env bash
set -u
EVAL_ID="plan-per-issue"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — no plans/ directory, rule is a no-op
EVAL_LABEL="$EVAL_ID no-plans" expect_pass "$RULE"

# pass — two plans, distinct issue numbers, each with a validation section
mkdir -p plans
cat > plans/2026-04-23-issue-1-alpha.md <<'EOF'
# Plan one

## Validation

Rule evals pass.
EOF
cat > plans/2026-04-23-issue-2-beta.md <<'EOF'
# Plan two

## Acceptance

Ship it when tests go green.
EOF
stage_all
commit_quiet "docs: add two plans"
EVAL_LABEL="$EVAL_ID distinct" expect_pass "$RULE"

# fail — a plan filename missing the issue token
printf '# Rogue plan\n\n## Validation\n\nok\n' > plans/rogue.md
stage_all
commit_quiet "docs: add untokened plan"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$RULE"

# fail — duplicate issue number across two plans
rm plans/rogue.md
cat > plans/2026-04-23-issue-1-duplicate.md <<'EOF'
# Plan three

## Verification

done.
EOF
stage_all
commit_quiet "docs: dup plan"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$RULE"

# fail — validation/verification/acceptance section missing
rm plans/2026-04-23-issue-1-duplicate.md
printf '# Plan four\n\nbody without validation heading.\n' > plans/2026-04-23-issue-3-gamma.md
stage_all
commit_quiet "docs: plan without validation"
EVAL_LABEL="$EVAL_ID missing-validation" expect_fail "$RULE"

# pass — validation waiver grandfathers the missing-section plan
cat > plans/2026-04-23-issue-3-gamma.md <<'EOF'
# Plan four

<!-- governance: allow-plan-validation legacy -->

Body without a validation heading, waived.
EOF
stage_all
commit_quiet "docs: waive validation on legacy plan"
EVAL_LABEL="$EVAL_ID validation-waiver" expect_pass "$RULE"

# fail — `allow-plan-per-issue` waiver exempts the filename check only and
# must NOT silence the validation-section check. Plan has a rogue filename
# + the filename waiver + no validation section → validation block fires.
cat > plans/rogue-with-filename-waiver.md <<'EOF'
# Rogue plan with only the filename waiver

<!-- governance: allow-plan-per-issue intentional -->

Body without a validation heading.
EOF
stage_all
commit_quiet "docs: waive filename only"
EVAL_LABEL="$EVAL_ID filename-waiver-still-checks-validation" expect_fail "$RULE"

# pass — both waivers together exempt the plan entirely.
cat > plans/rogue-with-filename-waiver.md <<'EOF'
# Rogue plan waived on both axes

<!-- governance: allow-plan-per-issue intentional -->
<!-- governance: allow-plan-validation legacy -->

Body without a validation heading.
EOF
stage_all
commit_quiet "docs: waive both"
EVAL_LABEL="$EVAL_ID both-waivers" expect_pass "$RULE"

eval_done

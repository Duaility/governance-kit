#!/usr/bin/env bash
set -u
EVAL_ID="plan-per-issue"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — no plans/ directory, rule is a no-op
EVAL_LABEL="$EVAL_ID no-plans" expect_pass "$RULE"

# pass — two plans, distinct issue numbers
mkdir -p plans
printf '# Plan one\n' > plans/2026-04-23-issue-1-alpha.md
printf '# Plan two\n' > plans/2026-04-23-issue-2-beta.md
stage_all
commit_quiet "docs: add two plans"
EVAL_LABEL="$EVAL_ID distinct" expect_pass "$RULE"

# fail — a plan filename missing the issue token
printf '# Rogue plan\n' > plans/rogue.md
stage_all
commit_quiet "docs: add untokened plan"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$RULE"

# fail — duplicate issue number across two plans
rm plans/rogue.md
printf '# Plan three\n' > plans/2026-04-23-issue-1-duplicate.md
stage_all
commit_quiet "docs: dup plan"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$RULE"

eval_done

#!/usr/bin/env bash
set -u
EVAL_ID="commit-issue-plan-match"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# Stage a plan touch + craft a pending commit-msg file — this is Mode A
# (commit-msg hook). The rule reads --cached diff; we stage without
# committing so the change is visible.
mkdir -p plans
printf '# Plan\n' > plans/2026-04-23-issue-7-thing.md
git add plans/2026-04-23-issue-7-thing.md

msg="$(mktemp)"

# pass — subject (#7) matches the staged plan's issue-7 token
printf 'feat: do a thing (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID match" expect_pass "$RULE" "$msg"

# fail — subject (#8) does not match the staged plan (issue-7)
printf 'feat: do a thing (#8)\n' > "$msg"
EVAL_LABEL="$EVAL_ID mismatch" expect_fail "$RULE" "$msg"

# fail — subject has issue number but no plan in staged changes
git reset --quiet HEAD plans/2026-04-23-issue-7-thing.md
rm plans/2026-04-23-issue-7-thing.md
printf 'feat: no plan (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-plan-touch" expect_fail "$RULE" "$msg"

# pass — waiver line allows a cross-issue commit
printf 'feat: cross-cutting (#9)\n\ngovernance: allow-commit-issue-plan-match needed for one-time migration\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$RULE" "$msg"

rm -f "$msg"
eval_done

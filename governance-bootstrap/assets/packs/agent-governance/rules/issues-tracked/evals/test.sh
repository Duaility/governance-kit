#!/usr/bin/env bash
set -u
EVAL_ID="issues-tracked"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — QUALITY.md with Open + Resolved sections
cat > QUALITY.md <<'EOF'
# Quality tracker

## Open

- Nothing tracked right now.

## Resolved

- Placeholder for resolved issues.
EOF
stage_all
commit_quiet "docs: add quality tracker"
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — missing one of the required sections
cat > QUALITY.md <<'EOF'
# Quality tracker

## Open

- Nothing.
EOF
stage_all
commit_quiet "docs: drop resolved"
EVAL_LABEL="$EVAL_ID no-resolved" expect_fail "$RULE"

# fail — QUALITY.md absent altogether
rm QUALITY.md
stage_all
commit_quiet "chore: drop quality file"
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

eval_done

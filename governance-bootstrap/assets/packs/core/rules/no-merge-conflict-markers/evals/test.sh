#!/usr/bin/env bash
set -u
EVAL_ID="no-merge-conflict-markers"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — commit a file with a live conflict marker
cat > conflict.md <<'EOF'
# Thing

<<<<<<< HEAD
ours
=======
theirs
>>>>>>> branch
EOF
stage_all
commit_quiet "chore: oops"
EVAL_LABEL="$EVAL_ID marker" expect_fail "$RULE"

eval_done

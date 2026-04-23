#!/usr/bin/env bash
set -u
EVAL_ID="no-debug-statements"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — ship a console.log in a JavaScript source file
mkdir -p src
cat > src/index.js <<'EOF'
function main() {
  console.log("DEBUG: hi");
}
EOF
stage_all
commit_quiet "feat: index"
EVAL_LABEL="$EVAL_ID console-log" expect_fail "$RULE"

eval_done

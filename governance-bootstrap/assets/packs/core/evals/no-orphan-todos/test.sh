#!/usr/bin/env bash
set -u
EVAL_ID="no-orphan-todos"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# pass — a TODO that references a tracker
mkdir -p src
cat > src/a.py <<'EOF'
def foo():
    pass  # TODO(#42): handle edge case
EOF
stage_all
commit_quiet "feat: a"
EVAL_LABEL="$EVAL_ID tracked" expect_pass "$RULE"

# fail — an orphan TODO with no tracker reference on the same line
cat > src/b.py <<'EOF'
def bar():
    pass  # TODO: forget about this forever
EOF
stage_all
commit_quiet "feat: b"
EVAL_LABEL="$EVAL_ID orphan" expect_fail "$RULE"

eval_done

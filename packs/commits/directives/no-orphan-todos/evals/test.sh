#!/usr/bin/env bash
set -u
EVAL_ID="no-orphan-todos"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/commits"
CHECK=".governance/packs/governance-kit/commits/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# pass — a TODO that references a tracker
mkdir -p src
cat > src/a.py <<'EOF'
def foo():
    pass  # TODO(#42): handle edge case
EOF
stage_all
commit_quiet "feat: a"
EVAL_LABEL="$EVAL_ID tracked" expect_pass "$CHECK"

# fail — an orphan TODO with no tracker reference on the same line
cat > src/b.py <<'EOF'
def bar():
    pass  # TODO: forget about this forever
EOF
stage_all
commit_quiet "feat: b"
EVAL_LABEL="$EVAL_ID orphan" expect_fail "$CHECK"

eval_done

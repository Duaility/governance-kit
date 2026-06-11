#!/usr/bin/env bash
set -u
EVAL_ID="token-permissions"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/security"
CHECK=".governance/packs/governance-kit/security/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — workflow declares a permissions block
mkdir -p .github/workflows
cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo hi
EOF
stage_all
commit_quiet "ci: workflow with permissions"
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — strip the permissions: block
cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo hi
EOF
stage_all
commit_quiet "ci: drop permissions"
EVAL_LABEL="$EVAL_ID no-perms" expect_fail "$CHECK"

# pass — same missing block, but waived with a head-of-file token
cat > .github/workflows/ci.yml <<'EOF'
# governance: allow-token-permissions intentionally inherits default for this fixture
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo hi
EOF
stage_all
commit_quiet "ci: waive permissions"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

eval_done

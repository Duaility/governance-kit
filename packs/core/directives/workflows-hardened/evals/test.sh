#!/usr/bin/env bash
set -u
EVAL_ID="workflows-hardened"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

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

# fail — third-party action pinned by tag instead of SHA
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
      - uses: tj-actions/changed-files@v44
      - run: echo hi
EOF
stage_all
commit_quiet "ci: add tag-pinned action"
EVAL_LABEL="$EVAL_ID tag-pin" expect_fail "$CHECK"

eval_done

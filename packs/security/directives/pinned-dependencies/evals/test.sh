#!/usr/bin/env bash
set -u
EVAL_ID="pinned-dependencies"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/security"
CHECK=".governance/packs/governance-kit/security/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — third-party action pinned to a full SHA; actions/* tag pin is allowlisted
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
      - uses: tj-actions/changed-files@0000000000000000000000000000000000000000
      - run: echo hi
EOF
stage_all
commit_quiet "ci: sha-pinned third-party action"
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

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
commit_quiet "ci: tag-pinned third-party action"
EVAL_LABEL="$EVAL_ID tag-pin" expect_fail "$CHECK"

# pass — same tag pin, waived on the offending line
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
      - uses: tj-actions/changed-files@v44  # governance: allow-pinned-dependencies fixture only
      - run: echo hi
EOF
stage_all
commit_quiet "ci: waive tag pin"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

eval_done

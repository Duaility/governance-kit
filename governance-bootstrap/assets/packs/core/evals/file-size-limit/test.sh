#!/usr/bin/env bash
set -u
EVAL_ID="file-size-limit"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — no tracked source files in the baseline
EVAL_LABEL="$EVAL_ID empty" expect_pass "$RULE"

# pass — a small source file stays under the default limit
mkdir -p src
seq 1 100 > src/small.py
stage_all
commit_quiet "feat: add small module"
EVAL_LABEL="$EVAL_ID small" expect_pass "$RULE"

# fail — override the limit to a tiny value and the file is over
EVAL_LABEL="$EVAL_ID tiny-limit" GOVERNANCE_FILE_SIZE_LIMIT=10 expect_fail "$RULE"

# fail — ship a file that exceeds the default 500-line limit
seq 1 600 > src/big.py
stage_all
commit_quiet "feat: add big module"
EVAL_LABEL="$EVAL_ID default-limit" expect_fail "$RULE"

eval_done

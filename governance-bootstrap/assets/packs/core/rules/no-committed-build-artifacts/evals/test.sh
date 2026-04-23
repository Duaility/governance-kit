#!/usr/bin/env bash
set -u
EVAL_ID="no-committed-build-artifacts"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — commit a Python bytecode file
printf 'bytecode\n' > module.pyc
stage_all
commit_quiet "chore: oops"
EVAL_LABEL="$EVAL_ID pyc" expect_fail "$RULE"

eval_done

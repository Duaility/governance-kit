#!/usr/bin/env bash
set -u
EVAL_ID="no-secrets"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — an AWS-style access key id appears in a tracked file
printf 'AKIAABCDEFGHIJKLMNOP\n' > config.txt
stage_all
commit_quiet "chore: config"
EVAL_LABEL="$EVAL_ID aws-key" expect_fail "$RULE"

eval_done

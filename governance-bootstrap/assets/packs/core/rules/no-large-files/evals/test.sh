#!/usr/bin/env bash
set -u
EVAL_ID="no-large-files"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — commit a ~2 MB file with a 1 MB limit
dd if=/dev/zero of=blob.bin bs=1024 count=2048 status=none
stage_all
commit_quiet "chore: add blob"
EVAL_LABEL="$EVAL_ID oversize" GOVERNANCE_MAX_FILE_SIZE_MB=1 expect_fail "$RULE"

eval_done

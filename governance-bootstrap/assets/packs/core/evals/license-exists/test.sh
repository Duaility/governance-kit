#!/usr/bin/env bash
set -u
EVAL_ID="license-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — no LICENSE at any accepted path
rm LICENSE
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

# fail — LICENSE exists but is empty
: > LICENSE
EVAL_LABEL="$EVAL_ID empty" expect_fail "$RULE"

eval_done

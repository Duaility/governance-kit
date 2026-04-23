#!/usr/bin/env bash
set -u
EVAL_ID="readme-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — README has no top-level heading
printf 'no heading here, just a body paragraph\n' > README.md
EVAL_LABEL="$EVAL_ID no-heading" expect_fail "$RULE"

# fail — no README at any accepted path
rm README.md
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

eval_done

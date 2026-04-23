#!/usr/bin/env bash
set -u
EVAL_ID="security-md-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — SECURITY.md present but carries no contact mechanism
printf '# Security\n\nPlease be careful.\n' > SECURITY.md
EVAL_LABEL="$EVAL_ID no-contact" expect_fail "$RULE"

# fail — missing SECURITY.md from every accepted location
rm SECURITY.md
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

eval_done

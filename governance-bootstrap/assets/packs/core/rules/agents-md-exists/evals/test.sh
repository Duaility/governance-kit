#!/usr/bin/env bash
set -u
EVAL_ID="agents-md-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline AGENTS.md satisfies min-lines + min-links defaults
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — shrunk below the 30-line floor
printf '# AGENTS.md\n\nstub.\n' > AGENTS.md
EVAL_LABEL="$EVAL_ID stub" expect_fail "$RULE"

# fail — missing entirely
rm AGENTS.md
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

eval_done

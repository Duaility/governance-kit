#!/usr/bin/env bash
set -u
EVAL_ID="architecture-doc-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — stub architecture doc
printf '# Architecture\n\nTBD.\n' > ARCHITECTURE.md
EVAL_LABEL="$EVAL_ID stub" expect_fail "$RULE"

# fail — missing architecture doc (and no fallback paths)
rm ARCHITECTURE.md
EVAL_LABEL="$EVAL_ID missing" expect_fail "$RULE"

eval_done

#!/usr/bin/env bash
set -u
EVAL_ID="ci-workflow-exists"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline ships a ci.yml alongside governance
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — only governance.yml remains (rule requires a non-governance workflow)
rm .github/workflows/ci.yml
printf 'name: Governance\non: [push]\njobs: {test: {runs-on: ubuntu-latest, steps: [{run: "true"}]}}\n' \
    > .github/workflows/governance.yml
EVAL_LABEL="$EVAL_ID only-governance" expect_fail "$RULE"

eval_done

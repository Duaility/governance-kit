#!/usr/bin/env bash
set -u
EVAL_ID="env-example-current"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — no local .env means the rule is a no-op
EVAL_LABEL="$EVAL_ID no-env" expect_pass "$RULE"

# pass — .env keys are covered by .env.example
printf 'DATABASE_URL=real-value\nAPI_KEY=real-value\n' > .env
EVAL_LABEL="$EVAL_ID synced" expect_pass "$RULE"

# fail — .env introduces a new key that .env.example does not list
printf 'DATABASE_URL=x\nAPI_KEY=x\nNEW_TOKEN=x\n' > .env
EVAL_LABEL="$EVAL_ID drift" expect_fail "$RULE"

# fail — .env exists but .env.example is missing
rm .env.example
EVAL_LABEL="$EVAL_ID missing-example" expect_fail "$RULE"

rm -f .env
eval_done

#!/usr/bin/env bash
set -u
EVAL_ID="dotenv-gitignored"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline has .env in .gitignore and no tracked .env
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — .env got committed
printf 'DATABASE_URL=postgres://x\n' > .env
git add -f .env
commit_quiet "chore: oops"
EVAL_LABEL="$EVAL_ID tracked-env" expect_fail "$RULE"

# fail — .env removed from ignore list and still tracked
git rm --cached -q .env
printf '*.log\n' > .gitignore
stage_all
commit_quiet "chore: drop env from ignore"
git add -f .env
commit_quiet "chore: re-track"
EVAL_LABEL="$EVAL_ID no-ignore" expect_fail "$RULE"

eval_done

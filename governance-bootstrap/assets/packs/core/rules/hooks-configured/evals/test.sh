#!/usr/bin/env bash
set -u
EVAL_ID="hooks-configured"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

# The rule skips the core.hooksPath check in CI; force the local branch so
# this eval exercises both halves regardless of where it runs.
unset CI GITHUB_ACTIONS

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline ships .githooks/pre-commit tracked + core.hooksPath set
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — pre-commit hook not tracked
git rm --quiet .githooks/pre-commit
commit_quiet "chore: drop pre-commit hook"
EVAL_LABEL="$EVAL_ID missing-hook" expect_fail "$RULE"

# restore for next assertion
mkdir -p .githooks
printf '#!/usr/bin/env bash\nexit 0\n' > .githooks/pre-commit
chmod +x .githooks/pre-commit
stage_all
commit_quiet "chore: restore hook"

# fail — core.hooksPath points somewhere else
git config core.hooksPath other-dir
EVAL_LABEL="$EVAL_ID wrong-path" expect_fail "$RULE"

eval_done

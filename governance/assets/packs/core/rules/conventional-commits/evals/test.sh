#!/usr/bin/env bash
set -u
EVAL_ID="conventional-commits"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# Mode A — commit-msg hook. A well-formed pending message passes.
msg="$(mktemp)"
printf 'feat(auth): accept refresh tokens from the new IdP (#42)\n' > "$msg"
EVAL_LABEL="$EVAL_ID well-formed" expect_pass "$RULE" "$msg"

# Missing issue suffix — fails.
printf 'feat: add login\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-issue" expect_fail "$RULE" "$msg"

# Unknown type — fails.
printf 'bogus: change the thing (#1)\n' > "$msg"
EVAL_LABEL="$EVAL_ID bad-type" expect_fail "$RULE" "$msg"

rm -f "$msg"
eval_done

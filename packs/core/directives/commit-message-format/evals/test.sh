#!/usr/bin/env bash
set -u
EVAL_ID="commit-message-format"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Mode A — commit-msg hook. A well-formed pending message passes.
msg="$(mktemp)"
printf 'feat(auth): accept refresh tokens from the new IdP (#42)\n' > "$msg"
EVAL_LABEL="$EVAL_ID well-formed" expect_pass "$CHECK" "$msg"

# Missing issue suffix — fails.
printf 'feat: add login\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-issue" expect_fail "$CHECK" "$msg"

# Unknown type — fails.
printf 'bogus: change the thing (#1)\n' > "$msg"
EVAL_LABEL="$EVAL_ID bad-type" expect_fail "$CHECK" "$msg"

rm -f "$msg"
eval_done

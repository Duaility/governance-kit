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

# Waiver — bad subject becomes acceptable when the body carries the waiver.
printf 'bogus: change the thing\n\ngovernance: allow-commit-message-format one-off vendored squash from upstream\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK" "$msg"

# Waiver without a reason — bare token does not waive.
printf 'bogus: change the thing\n\ngovernance: allow-commit-message-format\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver-without-reason" expect_fail "$CHECK" "$msg"

# ── overlay layering on the pack-owned default type list ──
mkdir -p .governance/conf

# pass — overlay adds a custom type (`wip`)
printf 'wip\n' > .governance/conf/commit-message-format.conf
printf 'wip: scratch work (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID overlay-adds-type" expect_pass "$CHECK" "$msg"

# fail — overlay drops a default type (`style`) with `!`, so it is rejected
printf '!style\n' > .governance/conf/commit-message-format.conf
printf 'style: reformat (#8)\n' > "$msg"
EVAL_LABEL="$EVAL_ID overlay-removes-type" expect_fail "$CHECK" "$msg"

# pass — a still-default type stays accepted after the removal above
printf 'feat: real feature (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID default-type-survives" expect_pass "$CHECK" "$msg"

rm -f "$msg"
eval_done

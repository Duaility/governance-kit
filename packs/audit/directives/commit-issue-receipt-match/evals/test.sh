#!/usr/bin/env bash
set -u
EVAL_ID="commit-issue-receipt-match"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Mode A (commit-msg hook): the directive reads the staged --cached diff for the
# receipt-touch check and the msg file for merge/revert detection + the waiver.
# Issue #293 made this file-first: the touched receipt's path is the issue
# anchor; the subject's (#N) is no longer parsed or cross-checked.
mkdir -p receipts
printf '# Receipt\n\n## Verification\n\nok\n' > receipts/issue-7-thing.md
git add receipts/issue-7-thing.md

msg="$(mktemp)"

# pass — a receipt is staged; the commit touches its issue's receipt.
printf 'feat: do a thing (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID receipt-touched" expect_pass "$CHECK" "$msg"

# pass — subject carries a different / PR-style number (#99) but a receipt is
# still staged. File-first: the receipt is the authoritative anchor, so the
# subject number is no longer cross-checked (this is the post-squash case where
# the subject is the PR id while the receipt is for the underlying issue).
printf 'feat: squash-merged PR (#99)\n' > "$msg"
EVAL_LABEL="$EVAL_ID subject-number-not-cross-checked" expect_pass "$CHECK" "$msg"

# fail — a real change that touches no receipt at all.
git reset --quiet HEAD receipts/issue-7-thing.md
rm receipts/issue-7-thing.md
printf 'placeholder\n' > src.txt
git add src.txt
printf 'feat: forgot the receipt (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-receipt-touch" expect_fail "$CHECK" "$msg"

# pass — waiver line allows a commit that legitimately touches no receipt.
printf 'chore(release): cut v1.2.3\n\ngovernance: allow-commit-issue-receipt-match release commits carry no receipt\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK" "$msg"

# pass — revert commits are exempt even with no receipt.
printf 'Revert "feat: do a thing (#7)"\n' > "$msg"
EVAL_LABEL="$EVAL_ID revert-exempt" expect_pass "$CHECK" "$msg"

rm -f "$msg"
eval_done

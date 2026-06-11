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

# Stage a receipt touch + craft a pending commit-msg file — this is Mode A
# (commit-msg hook). The directive reads --cached diff; we stage without
# committing so the change is visible.
mkdir -p receipts
printf '# Receipt\n\n## Verification\n\nok\n' > receipts/issue-7-thing.md
git add receipts/issue-7-thing.md

msg="$(mktemp)"

# pass — subject (#7) matches the staged receipt's issue-7 token
printf 'feat: do a thing (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID match" expect_pass "$CHECK" "$msg"

# fail — subject (#8) does not match the staged receipt (issue-7)
printf 'feat: do a thing (#8)\n' > "$msg"
EVAL_LABEL="$EVAL_ID mismatch" expect_fail "$CHECK" "$msg"

# pass — subject carries a PR id (#99) that has no receipt, but a folded
# sub-commit's `Issue: #7` trailer anchors to the staged issue-7 receipt.
# Mirrors post-squash-merge history where the PR number differs from the
# underlying issue number.
cat > "$msg" <<'EOF'
feat: squash-merged PR (#99)

* feat: sub-commit one (#7)

Agent: codex
Issue: #7
Session: s1
Token-Input: 10
Token-Output: 5
Token-Total: 15
Cost-Key: codex-s1-1

* feat: sub-commit two (#7)

Agent: codex
Issue: #7
Session: s1
Token-Input: 20
Token-Output: 10
Token-Total: 30
Cost-Key: codex-s1-2
EOF
EVAL_LABEL="$EVAL_ID squash-body-anchor" expect_pass "$CHECK" "$msg"

# fail — subject has issue number but no receipt in staged changes
git reset --quiet HEAD receipts/issue-7-thing.md
rm receipts/issue-7-thing.md
printf 'feat: no receipt (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-receipt-touch" expect_fail "$CHECK" "$msg"

# pass — waiver line allows a cross-issue commit
printf 'feat: cross-cutting (#9)\n\ngovernance: allow-commit-issue-receipt-match needed for one-time migration\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK" "$msg"

rm -f "$msg"
eval_done

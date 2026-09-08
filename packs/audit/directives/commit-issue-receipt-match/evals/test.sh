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

mkdir -p receipts
printf '# Receipt\n\n## Verification\n\nok\n' > receipts/issue-7-thing.md
git add receipts/issue-7-thing.md

msg="$(mktemp)"

# Mode A on default: receipt staged → pass
printf 'feat: do a thing (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID default-receipt-touched" expect_pass "$CHECK" "$msg"

# File-first: subject number is not cross-checked
printf 'feat: squash-merged PR (#99)\n' > "$msg"
EVAL_LABEL="$EVAL_ID subject-number-not-cross-checked" expect_pass "$CHECK" "$msg"

# Mode A on default: no receipt → fail (direct-to-default completion)
git reset --quiet HEAD receipts/issue-7-thing.md
rm -f receipts/issue-7-thing.md
printf 'placeholder\n' > src.txt
git add src.txt
printf 'feat: forgot the receipt (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID default-no-receipt" expect_fail "$CHECK" "$msg"

# Waiver
printf 'chore(release): cut v1.2.3\n\ngovernance: allow-commit-issue-receipt-match release commits carry no receipt\n' > "$msg"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK" "$msg"

# Revert exempt
printf 'Revert "feat: do a thing (#7)"\n' > "$msg"
EVAL_LABEL="$EVAL_ID revert-exempt" expect_pass "$CHECK" "$msg"

# Mode A on a feature branch: intermediate, no receipt required
git checkout -q -b wip
printf 'feat: wip without receipt (#9)\n' > "$msg"
EVAL_LABEL="$EVAL_ID intermediate-no-receipt" expect_pass "$CHECK" "$msg"

# Mode B: two commits, only the last touches a receipt — aggregate passes
git checkout -q main
git add src.txt
commit_quiet "chore: keep src on main"
git checkout -q -b feature
printf 'a\n' > a.txt
git add a.txt
commit_quiet "feat: first commit no receipt (#9)"
mkdir -p receipts
printf '# Receipt\n\n## What changed\n\ndone\n' > receipts/issue-9.md
git add receipts/issue-9.md
commit_quiet "docs: receipt on last commit (#9)"
EVAL_LABEL="$EVAL_ID modeB-aggregate-receipt" expect_pass "$CHECK"

# Mode B: feature branch with no receipt in the aggregate
git checkout -q main
git checkout -q -b no-receipt
printf 'b\n' > b.txt
git add b.txt
commit_quiet "feat: still no receipt (#9)"
EVAL_LABEL="$EVAL_ID modeB-no-receipt" expect_fail "$CHECK"

rm -f "$msg"
eval_done

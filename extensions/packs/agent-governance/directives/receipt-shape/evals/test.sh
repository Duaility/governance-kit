#!/usr/bin/env bash
set -u
EVAL_ID="receipt-shape"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — no receipts/ directory, directive is a no-op
EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

# pass — two receipts, distinct issue numbers, each with a Verification section
mkdir -p receipts
cat > receipts/issue-1-alpha.md <<'EOF'
# Receipt: alpha

## Verification

Directive evals pass.
EOF
cat > receipts/issue-2-beta.md <<'EOF'
# Receipt: beta

## Verification

Reviewer confirms behavior on the test fixture.
EOF
stage_all
commit_quiet "docs: add two receipts"
EVAL_LABEL="$EVAL_ID distinct" expect_pass "$CHECK"

# fail — a receipt filename missing the issue token
printf '# Rogue receipt\n\n## Verification\n\nok\n' > receipts/rogue.md
stage_all
commit_quiet "docs: add untokened receipt"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$CHECK"

# fail — duplicate issue number across two receipts
rm receipts/rogue.md
cat > receipts/issue-1-duplicate.md <<'EOF'
# Receipt: duplicate

## Verification

done.
EOF
stage_all
commit_quiet "docs: dup receipt"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$CHECK"

# fail — Verification section missing
rm receipts/issue-1-duplicate.md
printf '# Receipt gamma\n\nbody without verification heading.\n' > receipts/issue-3-gamma.md
stage_all
commit_quiet "docs: receipt without verification"
EVAL_LABEL="$EVAL_ID missing-verification" expect_fail "$CHECK"

eval_done

#!/usr/bin/env bash
set -u
EVAL_ID="receipt-per-issue"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — no receipts/ directory, directive is a no-op
EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

# pass — two receipts, distinct issue numbers, each with all three required sections
mkdir -p receipts
cat > receipts/issue-1-alpha.md <<'EOF'
# Receipt: alpha

## What changed

Added the alpha module.

## Out of scope

Beta module is deferred.

## Verification

Directive evals pass.
EOF
cat > receipts/issue-2-beta.md <<'EOF'
# Receipt: beta

## What changed

Added the beta module.

## Out of scope

Gamma is deferred.

## Verification

Reviewer confirms behavior on the test fixture.
EOF
stage_all
commit_quiet "docs: add two receipts"
EVAL_LABEL="$EVAL_ID distinct" expect_pass "$CHECK"

# fail — a receipt filename missing the issue token
cat > receipts/rogue.md <<'EOF'
# Rogue receipt

## What changed

Stuff.

## Out of scope

Things.

## Verification

ok
EOF
stage_all
commit_quiet "docs: add untokened receipt"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$CHECK"

# fail — duplicate issue number across two receipts
rm receipts/rogue.md
cat > receipts/issue-1-duplicate.md <<'EOF'
# Receipt: duplicate

## What changed

Stuff.

## Out of scope

Things.

## Verification

done.
EOF
stage_all
commit_quiet "docs: dup receipt"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$CHECK"

# fail — Verification section missing
rm receipts/issue-1-duplicate.md
cat > receipts/issue-3-gamma.md <<'EOF'
# Receipt gamma

## What changed

Body.

## Out of scope

Things.
EOF
stage_all
commit_quiet "docs: receipt without verification"
EVAL_LABEL="$EVAL_ID missing-verification" expect_fail "$CHECK"

# fail — What changed section missing
rm receipts/issue-3-gamma.md
cat > receipts/issue-4-delta.md <<'EOF'
# Receipt delta

## Out of scope

Things.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without what-changed"
EVAL_LABEL="$EVAL_ID missing-what-changed" expect_fail "$CHECK"

# fail — Out of scope section missing
rm receipts/issue-4-delta.md
cat > receipts/issue-5-epsilon.md <<'EOF'
# Receipt epsilon

## What changed

Body.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without out-of-scope"
EVAL_LABEL="$EVAL_ID missing-out-of-scope" expect_fail "$CHECK"

eval_done

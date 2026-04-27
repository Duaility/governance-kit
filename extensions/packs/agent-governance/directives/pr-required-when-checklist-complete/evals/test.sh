#!/usr/bin/env bash
set -u
EVAL_ID="pr-required-when-checklist-complete"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — no commits yet, directive is a no-op
EVAL_LABEL="$EVAL_ID no-head" expect_pass "$CHECK"

# Make a commit so HEAD exists, then put the fixture on a feature branch.
stage_all
commit_quiet "chore: seed fixture"
git checkout -b feature/test-branch >/dev/null 2>&1

# pass — no receipts/ directory
EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

mkdir -p receipts

# pass — receipt with unchecked items remaining (work not yet done)
cat > receipts/issue-1-alpha.md <<'EOF'
# Receipt: alpha

## Checklist

- [x] Wire the parser to the new lexer
- [ ] Document the migration steps

## What changed

Wire the parser to the new lexer.

## Out of scope

Docs deferred.

## Verification

Tests pass.
EOF
stage_all
commit_quiet "docs: receipt with unchecked items"
EVAL_LABEL="$EVAL_ID unchecked-remaining" expect_pass "$CHECK"

# pass — completed receipt AND a PR exists (test seam)
cat > receipts/issue-2-beta.md <<'EOF'
# Receipt: beta

## Checklist

- [x] Land the schema migration

## What changed

Land the schema migration in 0042_users.sql.

## Out of scope

None.

## Verification

Migration applied cleanly.
EOF
stage_all
commit_quiet "docs: completed receipt with PR"
EVAL_LABEL="$EVAL_ID completed-with-pr" \
    GOVERNANCE_TEST_PR_EXISTS=1 expect_pass "$CHECK"

# fail — completed receipt AND no PR exists
git rm receipts/issue-2-beta.md >/dev/null 2>&1
cat > receipts/issue-4-delta.md <<'EOF'
# Receipt: delta

## Checklist

- [x] Land the schema migration

## What changed

Land the schema migration.

## Out of scope

None.

## Verification

Migration applied.
EOF
stage_all
commit_quiet "docs: completed receipt no PR"
EVAL_LABEL="$EVAL_ID completed-no-pr" \
    GOVERNANCE_TEST_PR_EXISTS=0 expect_fail "$CHECK"

# pass — same fixture, but on main branch is a no-op
git checkout main >/dev/null 2>&1
EVAL_LABEL="$EVAL_ID main-branch-noop" \
    GOVERNANCE_TEST_PR_EXISTS=0 expect_pass "$CHECK"

eval_done

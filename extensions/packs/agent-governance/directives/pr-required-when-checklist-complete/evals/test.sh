#!/usr/bin/env bash
set -u
EVAL_ID="pr-required-when-checklist-complete"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# ── gh shim ────────────────────────────────────────────────────────────
# Mock the `gh` binary by prepending a temp dir to PATH. The shim handles
# the two invocations the check makes:
#   gh auth status                                         → exit 0 (or
#                                                            non-zero if
#                                                            MOCK_GH_AUTH=fail)
#   gh pr list --head <b> --state open --json number --jq length
#                                                          → echo
#                                                            $MOCK_GH_PR_COUNT,
#                                                            or exit non-zero
#                                                            if MOCK_GH_FAIL=1
# Any other invocation returns non-zero so unhandled cases surface loudly.
#
# This pattern keeps check.sh free of test-only branches: production code
# always calls the real `gh`, and the eval mocks the binary at the PATH
# level rather than via an env-var seam in the check.
MOCK_GH_DIR="$(mktemp -d)"
cat > "$MOCK_GH_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        if [[ "${MOCK_GH_AUTH:-ok}" == "fail" ]]; then
            exit 1
        fi
        exit 0
        ;;
    "pr list --head "*" --state open --json number --jq length")
        if [[ "${MOCK_GH_FAIL:-0}" == "1" ]]; then
            exit 1
        fi
        echo "${MOCK_GH_PR_COUNT:-0}"
        ;;
    *)
        echo "mock gh: unhandled invocation: $*" >&2
        exit 1
        ;;
esac
SHIM
chmod +x "$MOCK_GH_DIR/gh"
export PATH="$MOCK_GH_DIR:$PATH"
trap 'rm -rf "$MOCK_GH_DIR"' EXIT

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

# pass — completed receipt AND a PR exists (shim returns 1)
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
    MOCK_GH_PR_COUNT=1 expect_pass "$CHECK"

# fail — completed receipt AND no PR exists (shim returns 0)
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
    MOCK_GH_PR_COUNT=0 expect_fail "$CHECK"

# fail — completed receipt AND `gh pr list` errored (shim exits non-zero)
EVAL_LABEL="$EVAL_ID gh-api-error" \
    MOCK_GH_FAIL=1 expect_fail "$CHECK"

# pass — completed receipt but `gh auth status` fails → skip-with-warning
EVAL_LABEL="$EVAL_ID gh-not-authed" \
    MOCK_GH_AUTH=fail expect_pass "$CHECK"

# pass — same fixture on main branch is a no-op (PR check never reached)
git checkout main >/dev/null 2>&1
EVAL_LABEL="$EVAL_ID main-branch-noop" \
    MOCK_GH_PR_COUNT=0 expect_pass "$CHECK"

eval_done

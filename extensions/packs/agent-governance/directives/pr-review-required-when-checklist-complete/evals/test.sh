#!/usr/bin/env bash
set -u
EVAL_ID="pr-review-required-when-checklist-complete"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# The directive is local-only — guarantee CI is unset for the cases that
# need to exercise the body. The CI-skip case sets CI inline.
unset CI

# ── gh shim ────────────────────────────────────────────────────────────
# Mock the `gh` binary by prepending a temp dir to PATH. The shim handles:
#   gh auth status                            → exit 0 (or 1 if MOCK_GH_AUTH=fail)
#   gh pr list --head <b> --state open --json number --jq <expr>
#                                             → echo $MOCK_GH_PR_NUMBER (empty
#                                               for "no PR"), or exit non-zero
#                                               if MOCK_GH_LIST_FAIL=1
#   gh pr view <N> --json reviews --jq <expr> → echo $MOCK_GH_REVIEW_COUNT,
#                                               or exit non-zero if
#                                               MOCK_GH_VIEW_FAIL=1
# Any other invocation returns non-zero so unhandled cases surface loudly.
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
    "pr list --head "*" --state open --json number --jq "*)
        if [[ "${MOCK_GH_LIST_FAIL:-0}" == "1" ]]; then
            exit 1
        fi
        echo "${MOCK_GH_PR_NUMBER:-}"
        ;;
    "pr view "*" --json reviews --jq "*)
        if [[ "${MOCK_GH_VIEW_FAIL:-0}" == "1" ]]; then
            exit 1
        fi
        echo "${MOCK_GH_REVIEW_COUNT:-0}"
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

# pass — CI environment short-circuits the directive entirely (local-only).
# Run on main with no receipts so the only thing being tested is the CI gate.
EVAL_LABEL="$EVAL_ID ci-env-skip" CI=1 expect_pass "$CHECK"

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

# Add a completed receipt for the rest of the cases.
cat > receipts/issue-2-beta.md <<'EOF'
# Receipt: beta

## Checklist

- [x] Land the schema migration

## What changed

Land the schema migration.

## Out of scope

None.

## Verification

Migration applied cleanly.
EOF
stage_all
commit_quiet "docs: completed receipt"

# pass — completed receipt but no PR exists yet → defer to pr-required-when-
# checklist-complete (skip-with-info, exit 0).
EVAL_LABEL="$EVAL_ID no-pr-defer" \
    MOCK_GH_PR_NUMBER="" expect_pass "$CHECK"

# pass — completed receipt, PR exists, codex review exists.
EVAL_LABEL="$EVAL_ID review-present" \
    MOCK_GH_PR_NUMBER=42 MOCK_GH_REVIEW_COUNT=1 expect_pass "$CHECK"

# fail — completed receipt, PR exists, no codex review on it.
EVAL_LABEL="$EVAL_ID no-review" \
    MOCK_GH_PR_NUMBER=42 MOCK_GH_REVIEW_COUNT=0 expect_fail "$CHECK"

# fail — completed receipt, PR exists, gh pr view errors.
EVAL_LABEL="$EVAL_ID gh-view-error" \
    MOCK_GH_PR_NUMBER=42 MOCK_GH_VIEW_FAIL=1 expect_fail "$CHECK"

# fail — completed receipt, gh pr list errors (cannot determine PR existence).
EVAL_LABEL="$EVAL_ID gh-list-error" \
    MOCK_GH_LIST_FAIL=1 expect_fail "$CHECK"

# pass — gh not authenticated → skip-with-warning.
EVAL_LABEL="$EVAL_ID gh-not-authed" \
    MOCK_GH_AUTH=fail MOCK_GH_PR_NUMBER=42 MOCK_GH_REVIEW_COUNT=0 expect_pass "$CHECK"

# pass — same fixture on main branch is a no-op.
git checkout main >/dev/null 2>&1
EVAL_LABEL="$EVAL_ID main-branch-noop" \
    MOCK_GH_PR_NUMBER=42 MOCK_GH_REVIEW_COUNT=0 expect_pass "$CHECK"

eval_done

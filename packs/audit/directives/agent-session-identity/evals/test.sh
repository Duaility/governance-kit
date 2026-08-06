#!/usr/bin/env bash
set -u

EVAL_ID="agent-session-identity"
EVAL_ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
source "$EVAL_ROOT/kit/assets/packs/lib/eval-lib.sh"

fixture_init
install_directive "$EVAL_ROOT/packs/audit" "$EVAL_ID"
CHECK="$FIXTURE_DIR/.governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"
HOOK="$FIXTURE_DIR/.governance/packs/governance-kit/audit/directives/$EVAL_ID/hooks/pre-commit.sh"

printf '── session identity: stamp + validate ────────────────────\n'
set +e
(cd "$FIXTURE_DIR" && GOVERNANCE_HARNESS=codex GOVERNANCE_SESSION_ID=session-1 AGENT_ISSUE='#42' bash "$HOOK") >"$FIXTURE_DIR/eval.out" 2>&1
stamp_rc=$?
set -e
if [ "$stamp_rc" -eq 0 ]; then
    eval_assertions=$((eval_assertions + 1)); printf '  ✓ pre-commit stamps a session row\n'
else
    eval_failures=$((eval_failures + 1)); printf '  ✗ pre-commit failed to stamp a session row\n'; cat "$FIXTURE_DIR/eval.out"
fi

cat > "$FIXTURE_DIR/commit-msg" <<'EOF'
feat: record session (#42)
EOF
GOVERNANCE_HARNESS=codex GOVERNANCE_SESSION_ID=session-1 expect_pass "$CHECK" "$FIXTURE_DIR/commit-msg"

if grep -q '| .* | codex | session-1 |' "$FIXTURE_DIR/receipts/issue-42.md"; then
    eval_assertions=$((eval_assertions + 1)); printf '  ✓ receipt contains harness and session identifier\n'
else
    eval_failures=$((eval_failures + 1)); printf '  ✗ receipt is missing harness/session identifier\n'
fi

printf '── session identity: malformed row ───────────────────────\n'
cat > "$FIXTURE_DIR/receipts/issue-42.md" <<'EOF'
## Session

### Identifiers

| date | harness | session |
| --- | --- | --- |
| not-a-date | codex | session-1 |
EOF
GOVERNANCE_HARNESS=codex GOVERNANCE_SESSION_ID=session-1 expect_fail "$CHECK"

fixture_cleanup
if [ "$eval_failures" -eq 0 ]; then
    printf '✓ %s eval passed (%d assertions)\n' "$EVAL_ID" "$eval_assertions"
    exit 0
fi
printf '✗ %s eval failed (%d failures)\n' "$EVAL_ID" "$eval_failures" >&2
exit 1

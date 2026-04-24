#!/usr/bin/env bash
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
# install_rule copies the whole rule folder — lib/ (ledger, trailers, rates),
# hooks/ (pre-commit side effects + prepare-commit-msg stamping) and
# runtimes/ come with it. Nothing lives outside the rule folder.
install_rule "$PACK_DIR" "$EVAL_ID"

# Seed COSTS.md with a well-formed row.
cat > COSTS.md <<'EOF'
<!-- COSTS.md — append-only agent token-accounting ledger -->

# COSTS.md

---

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| eval-sess-1000 | claude-code | sess-abc | #7 |  | 100 | 200 | 0 | 50 | 350 |  | eval fixture |
EOF
stage_all
commit_quiet "chore: seed ledger"

msg="$(mktemp)"

# pass — trailers agree with the ledger row
cat > "$msg" <<'EOF'
feat: agent-authored change (#7)

Agent: claude-code
Issue: #7
Session: sess-abc
Token-Input: 300
Token-Output: 50
Token-Total: 350
Cost-Key: eval-sess-1000
EOF
EVAL_LABEL="$EVAL_ID match" expect_pass "$RULE" "$msg"

# fail — Token-Total disagrees with Token-Input + Token-Output
cat > "$msg" <<'EOF'
feat: broken totals (#7)

Agent: claude-code
Issue: #7
Session: sess-abc
Token-Input: 300
Token-Output: 50
Token-Total: 999
Cost-Key: eval-sess-1000
EOF
EVAL_LABEL="$EVAL_ID bad-total" expect_fail "$RULE" "$msg"

# fail — no Agent: trailer at all on a non-merge/revert commit
printf 'feat: untrailered (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-trailer" expect_fail "$RULE" "$msg"

# pass — revert commits are exempt
printf 'Revert "feat: something"\n' > "$msg"
EVAL_LABEL="$EVAL_ID revert" expect_pass "$RULE" "$msg"

rm -f "$msg"
eval_done

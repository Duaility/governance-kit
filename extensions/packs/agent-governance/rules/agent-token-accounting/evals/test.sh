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

# Seed COSTS.md with well-formed rows.
# Row 1 is a grandfathered legacy-ish v3 row (no model, no cost-usd) — exists
# purely to confirm the ledger-validator grandfather clause. No new commit
# points at it; new commits must target a priced row.
# Row 2 is model-priced so we can exercise the Cost-USD cross-check.
# 100 input + 200 cache-create + 50 output at claude-sonnet-4-6
# = (100·3 + 200·3.75 + 0·0.30 + 50·15) / 1e6 = 0.0018 USD.
cat > COSTS.md <<'EOF'
<!-- COSTS.md — append-only agent token-accounting ledger -->

# COSTS.md

---

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| eval-sess-1000 | claude-code | sess-abc | #7 |  | 100 | 200 | 0 | 50 | 350 |  | grandfathered legacy-ish fixture |
| eval-sess-2000 | claude-code | sess-xyz | #7 | claude-sonnet-4-6 | 100 | 200 | 0 | 50 | 350 | 0.0018 | priced fixture |
EOF
stage_all
commit_quiet "chore: seed ledger"

msg="$(mktemp)"

# fail — Token-Total disagrees with Token-Input + Token-Output
cat > "$msg" <<'EOF'
feat: broken totals (#7)

Agent: claude-code
Issue: #7
Session: sess-xyz
Token-Input: 300
Token-Output: 50
Token-Total: 999
Cost-Key: eval-sess-2000
Cost-USD: 0.0018
EOF
EVAL_LABEL="$EVAL_ID bad-total" expect_fail "$RULE" "$msg"

# fail — no Agent: trailer at all on a non-merge/revert commit
printf 'feat: untrailered (#7)\n' > "$msg"
EVAL_LABEL="$EVAL_ID no-trailer" expect_fail "$RULE" "$msg"

# pass — Cost-USD trailer matches the priced ledger row
cat > "$msg" <<'EOF'
feat: priced change (#7)

Agent: claude-code
Issue: #7
Session: sess-xyz
Token-Input: 300
Token-Output: 50
Token-Total: 350
Cost-Key: eval-sess-2000
Cost-USD: 0.0018
EOF
EVAL_LABEL="$EVAL_ID cost-usd match" expect_pass "$RULE" "$msg"

# fail — Cost-USD trailer disagrees with the priced ledger row
cat > "$msg" <<'EOF'
feat: tampered cost (#7)

Agent: claude-code
Issue: #7
Session: sess-xyz
Token-Input: 300
Token-Output: 50
Token-Total: 350
Cost-Key: eval-sess-2000
Cost-USD: 9.9999
EOF
EVAL_LABEL="$EVAL_ID cost-usd mismatch" expect_fail "$RULE" "$msg"

# fail — commit is missing the required Cost-USD trailer
cat > "$msg" <<'EOF'
feat: missing cost (#7)

Agent: claude-code
Issue: #7
Session: sess-xyz
Token-Input: 300
Token-Output: 50
Token-Total: 350
Cost-Key: eval-sess-2000
EOF
EVAL_LABEL="$EVAL_ID cost-usd missing" expect_fail "$RULE" "$msg"

# fail — commit claims ownership of a grandfathered row (empty cost_usd)
# but stamps a Cost-USD trailer; trailers.py flags the shape mismatch.
cat > "$msg" <<'EOF'
feat: points at grandfathered row (#7)

Agent: claude-code
Issue: #7
Session: sess-abc
Token-Input: 300
Token-Output: 50
Token-Total: 350
Cost-Key: eval-sess-1000
Cost-USD: 0.0018
EOF
EVAL_LABEL="$EVAL_ID grandfathered-row-mismatch" expect_fail "$RULE" "$msg"

# pass — revert commits are exempt
printf 'Revert "feat: something"\n' > "$msg"
EVAL_LABEL="$EVAL_ID revert" expect_pass "$RULE" "$msg"

rm -f "$msg"
eval_done

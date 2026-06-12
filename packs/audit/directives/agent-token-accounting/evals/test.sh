#!/usr/bin/env bash
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

git add -A .governance
git commit --quiet --no-verify -m "feat(governance): install directive (#1)"

# Per-fixture helpers. Cost rows now live in per-issue receipts (issue #201).
LEDGER_PY="$PWD/.governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/ledger.py"
SESSION_ID="abcdef0123456789fixture"
MODEL="claude-sonnet-4-5"

receipt_for() {  # receipt_for <issue e.g. #10>
    printf 'receipts/issue-%s.md' "${1#\#}"
}

# claude-sonnet-4-5 RATES: input $3.00, cache-create $3.75, cache-read $0.30, output $15.00 (per M tok).
append_priced_row() {
    # append_priced_row <cost-key> <issue> <input> <cache-create> <cache-read> <output>
    local key="$1" issue="$2" inp="$3" cc="$4" cr="$5" out="$6"
    mkdir -p receipts
    python3 "$LEDGER_PY" append-row "$(receipt_for "$issue")" \
        "$key" claude-code "$SESSION_ID" "$issue" "$MODEL" \
        "$inp" "$cc" "$cr" "$out" ""
}

# Computes cost-usd to 4dp the same way rates.compute_cost_usd does.
compute_cost_usd() {
    local inp="$1" cc="$2" cr="$3" out="$4"
    python3 -c "
inp, cc, cr, out = $inp, $cc, $cr, $out
cost = (inp*3.0 + cc*3.75 + cr*0.30 + out*15.0) / 1_000_000.0
print(f'{round(cost, 4):.4f}')
"
}

# write_block <cost-key> <issue> <input> <cache-create> <cache-read> <output>
# Stamps a single matched-row trailer block, derived from row arithmetic.
write_block() {
    local key="$1" issue="$2" inp="$3" cc="$4" cr="$5" out="$6"
    local t_in=$((inp + cc))
    local t_out=$out
    local t_total=$((inp + cc + out))
    local cost
    cost="$(compute_cost_usd "$inp" "$cc" "$cr" "$out")"
    printf 'Agent: claude-code\n'
    printf 'Issue: %s\n' "$issue"
    printf 'Session: %s\n' "$SESSION_ID"
    printf 'Token-Input: %s\n'  "$t_in"
    printf 'Token-Output: %s\n' "$t_out"
    printf 'Token-Total: %s\n'  "$t_total"
    printf 'Cost-Key: %s\n'     "$key"
    printf 'Cost-USD: %s\n'     "$cost"
}

reset_receipts() {
    rm -rf receipts
    git add -A receipts 2>/dev/null || true
    git commit --quiet --no-verify -m "chore: reset receipts" >/dev/null 2>&1 || true
}

# ──────────────────────────────────────────────────────────────
# Case 1 — pass: unsupported-runtime waiver with a reason
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-unsupported-ok <<'EOF'
feat: change from cursor (#3)

governance: allow-agent-token-accounting unsupported-runtime: cursor runtime has no runtimes/cursor.sh adapter yet
EOF
EVAL_LABEL="$EVAL_ID unsupported-runtime-pass" expect_pass "$CHECK" /tmp/msg-unsupported-ok

# ──────────────────────────────────────────────────────────────
# Case 2 — fail: unsupported-runtime waiver without a reason
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-unsupported-empty <<'EOF'
feat: change from cursor (#4)

governance: allow-agent-token-accounting unsupported-runtime:
EOF
EVAL_LABEL="$EVAL_ID unsupported-runtime-no-reason-fail" expect_fail "$CHECK" /tmp/msg-unsupported-empty

# ──────────────────────────────────────────────────────────────
# Case 3 — fail: no waiver, no trailers (existing missing-Agent: gate)
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-bare <<'EOF'
feat: bare commit (#5)
EOF
EVAL_LABEL="$EVAL_ID no-trailers-fail" expect_fail "$CHECK" /tmp/msg-bare

# ──────────────────────────────────────────────────────────────
# Case 4 — pass: single well-formed agent commit, row in the receipt
# ──────────────────────────────────────────────────────────────
reset_receipts
KEY1="ck-${SESSION_ID:0:12}-1800000100"
append_priced_row "$KEY1" "#10" 1000 0 0 500
{
    printf 'feat: priced agent commit (#10)\n\n'
    printf 'Body.\n\n'
    write_block "$KEY1" "#10" 1000 0 0 500
} > /tmp/msg-single-ok
EVAL_LABEL="$EVAL_ID single-block-matched-row" expect_pass "$CHECK" /tmp/msg-single-ok

# ──────────────────────────────────────────────────────────────
# Case 5 — fail: Cost-Key has no matching row in any receipt
# ──────────────────────────────────────────────────────────────
{
    printf 'feat: orphan trailer (#11)\n\n'
    printf 'Body.\n\n'
    write_block "ck-orphan-no-row" "#11" 1000 0 0 500
} > /tmp/msg-orphan
EVAL_LABEL="$EVAL_ID cost-key-missing-from-receipts" expect_fail "$CHECK" /tmp/msg-orphan

# ──────────────────────────────────────────────────────────────
# Case 6 — fail: trailer Token-Total disagrees with the receipt row
# ──────────────────────────────────────────────────────────────
{
    printf 'feat: token math wrong (#12)\n\n'
    printf 'Body.\n\n'
    printf 'Agent: claude-code\n'
    printf 'Issue: #12\n'
    printf 'Session: %s\n' "$SESSION_ID"
    printf 'Token-Input: 9999\n'
    printf 'Token-Output: 1\n'
    printf 'Token-Total: 10000\n'
    printf 'Cost-Key: %s\n' "$KEY1"
    printf 'Cost-USD: 0.0105\n'
} > /tmp/msg-bad-math
EVAL_LABEL="$EVAL_ID token-trailer-mismatch-with-row" expect_fail "$CHECK" /tmp/msg-bad-math

# ──────────────────────────────────────────────────────────────
# Case 7 — pass: squash-merge body with two stacked blocks, both rows
# present in the same receipt. The old last-wins parser would only verify
# the trailing block; per-block validation round-trips both.
# ──────────────────────────────────────────────────────────────
KEY2="ck-${SESSION_ID:0:12}-1800000200"
KEY3="ck-${SESSION_ID:0:12}-1800000300"
append_priced_row "$KEY2" "#13" 2000 0 0 1000
append_priced_row "$KEY3" "#13" 500 0 0 250
{
    printf 'feat: squashed pair (#13)\n\n'
    printf 'Body for sub-commit 1.\n\n'
    write_block "$KEY2" "#13" 2000 0 0 1000
    printf '\n'
    printf 'Body for sub-commit 2.\n\n'
    write_block "$KEY3" "#13" 500 0 0 250
} > /tmp/msg-squash-pair-ok
EVAL_LABEL="$EVAL_ID squash-merge-both-blocks-verified" expect_pass "$CHECK" /tmp/msg-squash-pair-ok

# ──────────────────────────────────────────────────────────────
# Case 8 — fail: squash body where the trailing block matches its row
# but an earlier block's row is missing.
# ──────────────────────────────────────────────────────────────
{
    printf 'feat: squashed pair, first row missing (#14)\n\n'
    printf 'Body for sub-commit 1.\n\n'
    write_block "ck-vanished-first-block" "#14" 100 0 0 50
    printf '\n'
    printf 'Body for sub-commit 2.\n\n'
    write_block "$KEY2" "#14" 2000 0 0 1000
} > /tmp/msg-squash-first-missing
EVAL_LABEL="$EVAL_ID squash-merge-earlier-row-missing" expect_fail "$CHECK" /tmp/msg-squash-first-missing

# ──────────────────────────────────────────────────────────────
# Case 9 — fail: agent commit but no trailer block parsed (all
# trailer lines mixed into a prose paragraph).
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-mixed <<EOF
feat: prose-then-trailers (#15)

Agent: claude-code is the runtime. Cost-Key: $KEY1 was emitted.
Token-Total: 1500 etc.
EOF
EVAL_LABEL="$EVAL_ID prose-mixed-with-trailers" expect_fail "$CHECK" /tmp/msg-mixed

# ──────────────────────────────────────────────────────────────
# Case 10 — pass: Mode B on `main` validates HEAD's trailers when
# `base..HEAD` is empty.
# ──────────────────────────────────────────────────────────────
reset_receipts
KEY_MB="ck-${SESSION_ID:0:12}-1800000900"
append_priced_row "$KEY_MB" "#16" 750 0 0 250
git add receipts
{
    printf 'feat: post-squash on main (#16)\n\n'
    printf 'Body.\n\n'
    write_block "$KEY_MB" "#16" 750 0 0 250
} > /tmp/msg-mode-b-pass
git commit --quiet --no-verify -F /tmp/msg-mode-b-pass
EVAL_LABEL="$EVAL_ID mode-b-on-main-valid" expect_pass "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 11 — fail: Mode B on `main` flags a HEAD commit missing Agent:
# ──────────────────────────────────────────────────────────────
git commit --allow-empty --quiet --no-verify -m "chore: trailerless squash (#17)"
EVAL_LABEL="$EVAL_ID mode-b-on-main-missing-agent" expect_fail "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 12 — receipt cost row lands under `## Accounting` → `### Costs`,
# create-if-absent, and validate-dir accepts a well-formed table.
# ──────────────────────────────────────────────────────────────
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
append_priced_row "ck-${SESSION_ID:0:12}-1900000001" "#20" 100 0 0 50
if grep -q '^## Accounting$' receipts/issue-20.md \
    && grep -q '^### Costs$' receipts/issue-20.md \
    && python3 "$LEDGER_PY" validate-dir receipts >/dev/null; then
    printf '    ✓ %s — cost row homed under ## Accounting / ### Costs\n' "$EVAL_ID"
else
    printf '    ✗ %s — receipt accounting section not created correctly\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ──────────────────────────────────────────────────────────────
# Case 13 — fail: validate-dir flags a malformed receipt cost row
# (new_work that does not equal input+cache_create+output).
# ──────────────────────────────────────────────────────────────
reset_receipts
mkdir -p receipts
cat > receipts/issue-21.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-bad-1 | claude-code | s | #21 | claude-sonnet-4-5 | 100 | 0 | 0 | 50 | 999 | 0.0001 | bad |
EOF
{ printf 'feat: bad receipt row (#21)\n\n'; printf 'Body.\n\n'; write_block "ck-x" "#21" 1 0 0 1; } > /tmp/msg-badrow
EVAL_LABEL="$EVAL_ID malformed-receipt-row" expect_fail "$CHECK" /tmp/msg-badrow
reset_receipts

# ──────────────────────────────────────────────────────────────
# Case 14 — cost-key counter closes the same-second window: two commits
# in one session within the same epoch mint distinct keys (issue #201).
# ──────────────────────────────────────────────────────────────
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
PREFIX="claude-code-${SESSION_ID:0:12}-1900000000-"
N1="$(python3 "$LEDGER_PY" next-cost-index receipts "$PREFIX")"
append_priced_row "${PREFIX}${N1}" "#22" 100 0 0 50
N2="$(python3 "$LEDGER_PY" next-cost-index receipts "$PREFIX")"
append_priced_row "${PREFIX}${N2}" "#22" 100 0 0 50
N3="$(python3 "$LEDGER_PY" next-cost-index receipts "$PREFIX")"
if [[ "$N1" == "1" && "$N2" == "2" && "$N3" == "3" ]] \
    && python3 "$LEDGER_PY" validate-dir receipts >/dev/null; then
    printf '    ✓ %s — same-second cost-keys are distinct (%s, %s)\n' "$EVAL_ID" "${PREFIX}${N1}" "${PREFIX}${N2}"
else
    printf '    ✗ %s — cost-key counter did not increment (got %s/%s/%s)\n' "$EVAL_ID" "$N1" "$N2" "$N3" >&2
    eval_failures=$(( eval_failures + 1 ))
fi
reset_receipts

# ──────────────────────────────────────────────────────────────
# Case 15 — rates.py honors the user price-override conf ($EVAL_CONF).
# ──────────────────────────────────────────────────────────────
RATES_PY=".governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/rates.py"
mkdir -p .governance/conf
rate_assert() {  # <label> <expected-cost> <model> <inp> <cc> <cr> <out>
    local label="$1" want="$2"; shift 2
    local got rc
    got="$(python3 "$RATES_PY" cost "$@" 2>/dev/null)"; rc=$?
    if [[ $rc -eq 0 && "$got" == "$want" ]]; then
        printf '    ✓ %s\n' "$label"
    else
        printf '    ✗ %s — want %s got %q (rc=%s)\n' "$label" "$want" "$got" "$rc" >&2
        eval_failures=$(( eval_failures + 1 ))
    fi
}
# With NO overlay, prices come from the pack-owned defaults.conf rate card.
rm -f $EVAL_CONF
# Exact default row (sonnet-4-5: base 3 / output 15): 1M in + 1M out = $18.0000.
rate_assert "$EVAL_ID defaults.conf prices a built-in model" 18.0000 claude-sonnet-4-5 1000000 0 0 1000000
# Family-prefix fallback from defaults.conf (claude-opus -> 5.00): 1M in = $5.0000.
rate_assert "$EVAL_ID defaults.conf family fallback resolves" 5.0000 claude-opus-4-99 1000000 0 0 0
# Override an existing model (base 1 / output 1): 1M in + 1M out = $2.0000.
printf 'rate claude-sonnet-4-5 1 1 0.1 1\n' > $EVAL_CONF
rate_assert "$EVAL_ID conf overrides a built-in price" 2.0000 claude-sonnet-4-5 1000000 0 0 1000000
# Add a brand-new model (base 2): 1M in = $2.0000.
printf 'rate my-model 2 2 0.2 8\n' >> $EVAL_CONF
rate_assert "$EVAL_ID conf adds a new model" 2.0000 my-model 1000000 0 0 0
# Malformed row → non-zero exit so the commit blocks.
printf 'rate broken 1 2\n' > $EVAL_CONF
if python3 "$RATES_PY" cost claude-sonnet-4-5 1 0 0 0 >/dev/null 2>&1; then
    printf '    ✗ %s malformed conf should block pricing\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
else
    printf '    ✓ %s malformed conf blocks pricing\n' "$EVAL_ID"
fi
rm -f $EVAL_CONF

eval_done

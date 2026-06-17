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

# Per-fixture helpers. Cost rows live in per-issue receipts (issue #201).
LEDGER_PY="$PWD/.governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/ledger.py"
ENDPOINT_PY="$PWD/.governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/endpoint.py"
SESSION_ID="abcdef0123456789fixture"
MODEL="claude-sonnet-4-5"

receipt_for() {  # receipt_for <issue e.g. #10>
    printf 'receipts/issue-%s.md' "${1#\#}"
}

# claude-sonnet-4-5 RATES: input $3.00, cache-create $3.75, cache-read $0.30, output $15.00 (per M tok).
append_priced_row() {
    # append_priced_row <cost-key> <issue> <input> <cache-create> <cache-read> <output> \
    #                   [cum-in cum-cc cum-cr cum-out] [session]
    # v4 (issue #229): each row carries the four cumulative coordinates. By
    # default a row stands alone in its own synthetic session (cum == delta → a
    # clean first-of-session row). The reconciliation cases below pass
    # cumulatives and a shared session explicitly.
    local key="$1" issue="$2" inp="$3" cc="$4" cr="$5" out="$6"
    local ci="${7:-$inp}" ccc="${8:-$cc}" ccr="${9:-$cr}" co="${10:-$out}"
    local ses="${11:-sess-$key}"
    mkdir -p receipts
    python3 "$LEDGER_PY" append-row "$(receipt_for "$issue")" \
        "$key" claude-code "$ses" "$issue" "$MODEL" \
        "$inp" "$cc" "$cr" "$out" "$ci" "$ccc" "$ccr" "$co" ""
}

# append_cum_row <cost-key> <issue> <session> <input> <cc> <cr> <out> <cum-in> <cum-cc> <cum-cr> <cum-out>
# Direct v4 append with an explicit shared session + cumulative coordinates,
# for the reconciliation and endpoint fixtures (issues #229, #293).
append_cum_row() {
    local key="$1" issue="$2" ses="$3" inp="$4" cc="$5" cr="$6" out="$7"
    local ci="$8" ccc="$9" ccr="${10}" co="${11}"
    mkdir -p receipts
    python3 "$LEDGER_PY" append-row "$(receipt_for "$issue")" \
        "$key" claude-code "$ses" "$issue" "$MODEL" \
        "$inp" "$cc" "$cr" "$out" "$ci" "$ccc" "$ccr" "$co" ""
}

write_endpoint_for_tree() {
    # write_endpoint_for_tree <session> <cum-in> <cum-cc> <cum-cr> <cum-out> <receipt> <cost-key>
    git add -A receipts
    local tree endpoint
    tree="$(git write-tree)"
    endpoint="$(git rev-parse --git-path "governance-token-endpoints/${tree}.json")"
    python3 "$ENDPOINT_PY" write "$endpoint" "$@"
}

reset_receipts() {
    rm -rf receipts
    git add -A receipts 2>/dev/null || true
    git commit --quiet --no-verify -m "chore: reset receipts" >/dev/null 2>&1 || true
}

# Simulate an agent runtime via the `manual` adapter (lib/runtime.sh): the env
# carries the session's cumulative coordinate the transcript reader would
# otherwise produce. This is the real commit-time path check.sh takes.
clear_runtime() {
    # Also clears CLAUDECODE / CODEX_THREAD_ID so the eval is deterministic when
    # run inside a live agent session (where CLAUDECODE=1 is ambient).
    unset AGENT_NAME AGENT_SESSION_ID AGENT_CUM_INPUT \
          AGENT_CUM_CACHE_CREATE AGENT_CUM_CACHE_READ AGENT_CUM_OUTPUT \
          CLAUDECODE CODEX_THREAD_ID 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════
# Endpoint reconciliation (issues #293, #305) — the trailer-free completeness
# check. At commit time, with a runtime detected, the staged receipt row must
# match the frozen endpoint that pre-commit wrote for this exact staged tree.
# ══════════════════════════════════════════════════════════════
ESES="endpoint-sess-293"

# ── Case 1 — pass: no runtime detected (human / manual-git commit) → no-op ──
reset_receipts
clear_runtime
printf 'feat: human commit (#30)\n' > /tmp/msg-token-no-runtime
EVAL_LABEL="$EVAL_ID no-runtime-no-op" expect_pass "$CHECK" /tmp/msg-token-no-runtime

# ── Case 2 — pass: receipt matches frozen endpoint even if live runtime moved ──
reset_receipts
append_cum_row ck-ep-1 "#30" "$ESES" 1000 0 0 500  1000 0 0 500
write_endpoint_for_tree "$ESES" 1000 0 0 500 receipts/issue-30.md ck-ep-1
printf 'feat: priced agent commit (#30)\n' > /tmp/msg-token-match
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1200 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=300 AGENT_CUM_OUTPUT=550
EVAL_LABEL="$EVAL_ID frozen-endpoint-survives-live-movement" expect_pass "$CHECK" /tmp/msg-token-match
clear_runtime

# ── Case 3 — fail: endpoint exists but staged receipt row does not match it ──
reset_receipts
append_cum_row ck-ep-2 "#31" "$ESES" 500 0 0 250  500 0 0 250
write_endpoint_for_tree "$ESES" 1000 0 0 500 receipts/issue-31.md ck-ep-2
printf 'feat: ledger lags (#31)\n' > /tmp/msg-token-lag
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1000 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=0 AGENT_CUM_OUTPUT=500
EVAL_LABEL="$EVAL_ID frozen-endpoint-mismatch-fails" expect_fail "$CHECK" /tmp/msg-token-lag
clear_runtime

# ── Case 4 — fail: runtime detected but no frozen endpoint for staged tree ──
reset_receipts
printf 'feat: no row written (#32)\n' > /tmp/msg-token-norow
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1000 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=0 AGENT_CUM_OUTPUT=500
EVAL_LABEL="$EVAL_ID frozen-endpoint-missing-fails" expect_fail "$CHECK" /tmp/msg-token-norow
clear_runtime

# ── Case 5 — pass: a body waiver bypasses the endpoint check ──
reset_receipts
append_cum_row ck-ep-5 "#33" "$ESES" 500 0 0 250  500 0 0 250
{ printf 'feat: out-of-hook commit (#33)\n\n'; printf 'governance: allow-agent-token-accounting committed outside the runtime hook for a one-off\n'; } > /tmp/msg-token-waiver
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1000 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=0 AGENT_CUM_OUTPUT=500
EVAL_LABEL="$EVAL_ID endpoint-waiver" expect_pass "$CHECK" /tmp/msg-token-waiver
clear_runtime

# ── Case 6 — fail: runtime detected but its cumulative is unreadable (rc=2) ──
reset_receipts
printf 'feat: unreadable runtime (#34)\n' > /tmp/msg-token-rc2
export AGENT_NAME=eval-manual   # AGENT_SESSION_ID / AGENT_CUM_* deliberately unset
EVAL_LABEL="$EVAL_ID runtime-unreadable-fails" expect_fail "$CHECK" /tmp/msg-token-rc2
clear_runtime

# ── Case 7 — pass: unreadable runtime, but waived ──
reset_receipts
{ printf 'feat: unreadable runtime, waived (#35)\n\n'; printf 'governance: allow-agent-token-accounting runtime cumulative unavailable in this environment\n'; } > /tmp/msg-token-rc2-waiver
export AGENT_NAME=eval-manual
EVAL_LABEL="$EVAL_ID runtime-unreadable-waived" expect_pass "$CHECK" /tmp/msg-token-rc2-waiver
clear_runtime

# ── Case 8 — pass: revert commits are exempt ──
reset_receipts
printf 'Revert "feat: something (#36)"\n' > /tmp/msg-token-revert
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1000 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=0 AGENT_CUM_OUTPUT=500
EVAL_LABEL="$EVAL_ID revert-exempt" expect_pass "$CHECK" /tmp/msg-token-revert
clear_runtime

# ══════════════════════════════════════════════════════════════
# Receipt-shape integrity (validate-dir) — runtime-independent, unchanged.
# ══════════════════════════════════════════════════════════════

# ── Case 9 — cost row lands under `## Accounting` → `### Costs`, validate-dir clean ──
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

# ── Case 10 — fail: validate-dir flags a malformed receipt cost row ──
# No runtime → Mode A no-ops; the failure comes purely from the repo-wide
# receipt-shape check at the top of check.sh.
reset_receipts
clear_runtime
mkdir -p receipts
cat > receipts/issue-21.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-bad-1 | claude-code | s | #21 | claude-sonnet-4-5 | 100 | 0 | 0 | 50 | 999 | 0.0001 | bad |
EOF
printf 'feat: bad receipt row (#21)\n' > /tmp/msg-token-badrow
EVAL_LABEL="$EVAL_ID malformed-receipt-row" expect_fail "$CHECK" /tmp/msg-token-badrow
reset_receipts

# ── Case 11 — cost-key counter closes the same-second window (issue #201) ──
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

# ── Case 12 — endpoint helper: session-cum reports the latest cumulative ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
append_cum_row sc-1 "#37" "sc-session" 100 0 0 50   100 0 0 50
append_cum_row sc-2 "#37" "sc-session" 200 0 0 100  300 0 0 150
SC_OUT="$(python3 "$LEDGER_PY" session-cum receipts "sc-session")"
if [[ "$SC_OUT" == "300 0 0 150" ]]; then
    printf '    ✓ %s — session-cum returns the latest cumulative coordinate\n' "$EVAL_ID"
else
    printf '    ✗ %s — session-cum returned %q (expected "300 0 0 150")\n' "$EVAL_ID" "$SC_OUT" >&2
    eval_failures=$(( eval_failures + 1 ))
fi
reset_receipts

# ── Case 13 — rates.py honors the user price-override conf ($EVAL_CONF) ──
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
rm -f $EVAL_CONF
rate_assert "$EVAL_ID defaults.conf prices a built-in model" 18.0000 claude-sonnet-4-5 1000000 0 0 1000000
rate_assert "$EVAL_ID defaults.conf family fallback resolves" 5.0000 claude-opus-4-99 1000000 0 0 0
printf 'rate claude-sonnet-4-5 1 1 0.1 1\n' > $EVAL_CONF
rate_assert "$EVAL_ID conf overrides a built-in price" 2.0000 claude-sonnet-4-5 1000000 0 0 1000000
printf 'rate my-model 2 2 0.2 8\n' >> $EVAL_CONF
rate_assert "$EVAL_ID conf adds a new model" 2.0000 my-model 1000000 0 0 0
printf 'rate broken 1 2\n' > $EVAL_CONF
if python3 "$RATES_PY" cost claude-sonnet-4-5 1 0 0 0 >/dev/null 2>&1; then
    printf '    ✗ %s malformed conf should block pricing\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
else
    printf '    ✓ %s malformed conf blocks pricing\n' "$EVAL_ID"
fi
rm -f $EVAL_CONF

# ── Case 14 — reconciliation flags exactly the inflated double-count row (#229) ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
RSES="recon-session-229"
append_cum_row recon-c1 "#310" "$RSES" 96900  0 0 0  96900  0 0 0
append_cum_row recon-c2 "#312" "$RSES" 55800  0 0 0  152700 0 0 0
append_cum_row recon-c3 "#310" "$RSES" 103400 0 0 0  200300 0 0 0   # Δ INFLATED
RECON_OUT="$(python3 "$LEDGER_PY" validate-dir receipts 2>&1)"; RECON_RC=$?
if [[ $RECON_RC -ne 0 ]] \
    && printf '%s' "$RECON_OUT" | grep -q "cost row 'recon-c3'" \
    && printf '%s' "$RECON_OUT" | grep -qi "double-count" \
    && ! printf '%s' "$RECON_OUT" | grep -qE "cost row 'recon-c1'|cost row 'recon-c2'"; then
    printf '    ✓ %s — reconciliation flags exactly the inflated C3 row post-merge\n' "$EVAL_ID"
else
    printf '    ✗ %s — reconciliation did not flag exactly C3 (rc=%s)\n%s\n' "$EVAL_ID" "$RECON_RC" "$RECON_OUT" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ── Case 15 — reconciliation passes for the correct delta against C2 ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
append_cum_row recon-c1 "#310" "$RSES" 96900 0 0 0  96900  0 0 0
append_cum_row recon-c2 "#312" "$RSES" 55800 0 0 0  152700 0 0 0
append_cum_row recon-c3 "#310" "$RSES" 47600 0 0 0  200300 0 0 0   # Δ correct
if python3 "$LEDGER_PY" validate-dir receipts >/dev/null 2>&1; then
    printf '    ✓ %s — reconciliation passes when the delta == cum(n) − cum(n−1)\n' "$EVAL_ID"
else
    printf '    ✗ %s — reconciliation false-flagged a correct delta\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ── Case 16 — branch-local correct delta is skipped (predecessor absent) ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
append_cum_row recon-c1 "#310" "$RSES" 96900 0 0 0  96900  0 0 0
append_cum_row recon-c3 "#310" "$RSES" 47600 0 0 0  200300 0 0 0   # C2 absent on this branch
if python3 "$LEDGER_PY" validate-dir receipts >/dev/null 2>&1; then
    printf '    ✓ %s — branch-local correct delta is skipped (predecessor absent), not flagged\n' "$EVAL_ID"
else
    printf '    ✗ %s — branch-local correct delta false-flagged with predecessor absent\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ── Case 17 — per-session monotonicity: a backwards cumulative is flagged ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
append_cum_row mono-1 "#40" "mono-session" 100 0 0 0  100 0 0 0
append_cum_row mono-2 "#40" "mono-session" 0   0 0 0  80  0 0 100
MONO_OUT="$(python3 "$LEDGER_PY" validate-dir receipts 2>&1)"; MONO_RC=$?
if [[ $MONO_RC -ne 0 ]] && printf '%s' "$MONO_OUT" | grep -qi "monotonic"; then
    printf '    ✓ %s — backwards cumulative counter flagged (monotonicity/tamper)\n' "$EVAL_ID"
else
    printf '    ✗ %s — monotonicity check missed a backwards cumulative (rc=%s)\n%s\n' "$EVAL_ID" "$MONO_RC" "$MONO_OUT" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ── Case 18 — legacy v3 (12-column) rows parse, validate, skip reconciliation ──
reset_receipts
eval_assertions=$(( eval_assertions + 1 ))
mkdir -p receipts
cat > receipts/issue-50.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-legacy-1 | claude-code | legacy-sess | #50 | claude-sonnet-4-5 | 1000 | 0 | 0 | 500 | 1500 | 0.0105 | legacy v3 row |
| ck-legacy-2 | claude-code | legacy-sess | #50 | claude-sonnet-4-5 | 2000 | 0 | 0 | 100 | 2100 | 0.0075 | legacy v3 row |
EOF
if python3 "$LEDGER_PY" validate-dir receipts >/dev/null 2>&1; then
    printf '    ✓ %s — legacy v3 rows parse, validate, and skip reconciliation\n' "$EVAL_ID"
else
    printf '    ✗ %s — legacy v3 rows broke under the v4 validator\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
fi
reset_receipts

eval_done

#!/usr/bin/env bash
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

git add -A .governance
git commit --quiet --no-verify -m "feat(governance): install directive (#1)"

DIR="$PWD/.governance/packs/governance-kit/audit/directives/$EVAL_ID"
LIB="$DIR/lib"
RUNTIMES="$PWD/.governance/runtimes"   # kit-level adapter registry (issue #355)
SESSION_ID="abcdef0123456789fixture"
MODEL="claude-sonnet-4-5"

# The directive's own bash stack, sourced straight into the eval so fixtures
# write rows through exactly the code the hook uses (issue #355 — no python).
# shellcheck disable=SC1090
source "$LIB/receipt.sh"
# shellcheck disable=SC1090
source "$LIB/costs.sh"
# shellcheck disable=SC1090
source "$LIB/validate.sh"
# shellcheck disable=SC1090
source "$LIB/endpoint.sh"

receipt_for() {  # receipt_for <issue e.g. #10>
    printf 'receipts/issue-%s.md' "${1#\#}"
}

# append_v5 <cost-key> <issue> <session> <in> <cc> <cr> <out> \
#           <cum-in> <cum-cc> <cum-cr> <cum-out> [cost-usd] [source]
append_v5() {
    local key="$1" issue="$2" ses="$3" inp="$4" cc="$5" cr="$6" out="$7"
    local ci="$8" ccc="$9" ccr="${10}" co="${11}"
    local cost="${12:--}" src="${13:-claude-code}"
    mkdir -p receipts
    costs_append_row "$(receipt_for "$issue")" \
        "$key" claude-code "$ses" "$issue" "$MODEL" \
        "$inp" "$cc" "$cr" "$out" "$ci" "$ccc" "$ccr" "$co" "$cost" "$src" ""
}

# append_standalone <cost-key> <issue> <in> <cc> <cr> <out>
#   A row that stands alone in its own synthetic session (cum == delta → a
#   clean first-of-session row), for the shape-only fixtures.
append_standalone() {
    append_v5 "$1" "$2" "sess-$1" "$3" "$4" "$5" "$6" "$3" "$4" "$5" "$6"
}

write_endpoint_for_tree() {
    # write_endpoint_for_tree <session> <cum-in> <cum-cc> <cum-cr> <cum-out> <receipt> <cost-key>
    git add -A receipts
    local tree endpoint
    tree="$(git write-tree)"
    endpoint="$(git rev-parse --git-path "governance-token-endpoints/${tree}.endpoint")"
    endpoint_write "$endpoint" "$@"
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
          AGENT_MODEL AGENT_COST_USD \
          CLAUDECODE CODEX_THREAD_ID 2>/dev/null || true
}

pass_assert() {  # pass_assert <label> <condition-already-evaluated-rc>
    eval_assertions=$(( eval_assertions + 1 ))
    if [[ "$1" -eq 0 ]]; then
        printf '    ✓ %s — %s\n' "$EVAL_ID" "$2"
    else
        printf '    ✗ %s — %s\n' "$EVAL_ID" "$2" >&2
        eval_failures=$(( eval_failures + 1 ))
    fi
}

# ══════════════════════════════════════════════════════════════
# Endpoint reconciliation (issues #293, #305, #355) — the trailer-free
# completeness check, now over the flat `<tree>.endpoint` file. At commit time,
# with a runtime detected, the staged receipt row must match the frozen
# endpoint pre-commit wrote for this exact staged tree.
# ══════════════════════════════════════════════════════════════
ESES="endpoint-sess-293"

# ── Case 1 — pass: no runtime detected (human / manual-git commit) → no-op ──
reset_receipts
clear_runtime
printf 'feat: human commit (#30)\n' > /tmp/msg-token-no-runtime
EVAL_LABEL="$EVAL_ID no-runtime-no-op" expect_pass "$CHECK" /tmp/msg-token-no-runtime

# ── Case 2 — pass: receipt matches frozen endpoint even if live runtime moved ──
reset_receipts
append_v5 ck-ep-1 "#30" "$ESES" 1000 0 0 500  1000 0 0 500
write_endpoint_for_tree "$ESES" 1000 0 0 500 receipts/issue-30.md ck-ep-1
printf 'feat: accounted agent commit (#30)\n' > /tmp/msg-token-match
export AGENT_NAME=eval-manual AGENT_SESSION_ID="$ESES" \
       AGENT_CUM_INPUT=1200 AGENT_CUM_CACHE_CREATE=0 AGENT_CUM_CACHE_READ=300 AGENT_CUM_OUTPUT=550
EVAL_LABEL="$EVAL_ID frozen-endpoint-survives-live-movement" expect_pass "$CHECK" /tmp/msg-token-match
clear_runtime

# ── Case 3 — fail: endpoint exists but staged receipt row does not match it ──
reset_receipts
append_v5 ck-ep-2 "#31" "$ESES" 500 0 0 250  500 0 0 250
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
append_v5 ck-ep-5 "#33" "$ESES" 500 0 0 250  500 0 0 250
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

# ── Case 9 — endpoint write/verify round-trips through the flat file ──
reset_receipts
append_v5 ck-ep-9 "#38" "ep-sess-9" 100 0 0 50  100 0 0 50
EP="$(git rev-parse --git-path 'governance-token-endpoints/probe.endpoint')"
endpoint_write "$EP" "ep-sess-9" 100 0 0 50 receipts/issue-38.md ck-ep-9
endpoint_verify "$EP" "$PWD" >/dev/null 2>&1
pass_assert $? "endpoint_verify accepts a row matching the frozen coordinate"
endpoint_write "$EP" "ep-sess-9" 999 0 0 50 receipts/issue-38.md ck-ep-9
if endpoint_verify "$EP" "$PWD" >/dev/null 2>&1; then rc=1; else rc=0; fi
pass_assert $rc "endpoint_verify rejects a row that drifted from the frozen coordinate"
reset_receipts

# ── Case 10 — checkpoint round-trips and yields the per-commit delta ──
CPDIR="$(git rev-parse --git-path governance-token-checkpoints)"
CP_OUT="$(checkpoint_get "$CPDIR" "cp-sess")"
rc=0; [[ "$CP_OUT" == "0 0 0 0" ]] || rc=1
pass_assert $rc "checkpoint_get returns zeros for an unseen session"
checkpoint_set "$CPDIR" "cp-sess" 1000 20 300 400
CP_OUT="$(checkpoint_get "$CPDIR" "cp-sess")"
rc=0; [[ "$CP_OUT" == "1000 20 300 400" ]] || rc=1
pass_assert $rc "checkpoint_set/get round-trip the cumulative coordinate"

# ══════════════════════════════════════════════════════════════
# Receipt-shape integrity (validate-dir) — runtime-independent.
# ══════════════════════════════════════════════════════════════

# ── Case 11 — a v5 row lands under `## Accounting` → `### Costs`, 17 cells ──
reset_receipts
append_standalone "ck-${SESSION_ID:0:12}-1900000001" "#20" 100 0 0 50
CELLS="$(costs_rows receipts/issue-20.md | tail -n1 | awk -F'[|]' '{print NF - 2}')"
rc=0
grep -q '^## Accounting$' receipts/issue-20.md || rc=1
grep -q '^### Costs$' receipts/issue-20.md || rc=1
grep -q '^| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |$' receipts/issue-20.md || rc=1
[[ "$CELLS" == "17" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "v5 row homed under ## Accounting / ### Costs with the 17-column header"

# ── Case 12 — a blank cost-usd is accepted and the source column is present ──
rc=0
costs_rows receipts/issue-20.md | tail -n1 | grep -qE '\| 150 \|[[:space:]]+\| 100 \| 0 \| 0 \| 50 \| claude-code \|' || rc=1
pass_assert $rc "an unreported cost writes an empty cost-usd cell next to a named source"

# ── Case 13 — a harness-reported cost is copied through verbatim ──
reset_receipts
append_v5 ck-native "#23" sess-native 10 0 0 5  10 0 0 5 "1.2345" codex
rc=0
grep -q '| 1.2345 |' receipts/issue-23.md || rc=1
grep -q '| codex |' receipts/issue-23.md || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "a harness-reported cost-usd is written verbatim with its source adapter"
reset_receipts

# ── Case 14 — the manual seam passes AGENT_COST_USD / AGENT_MODEL through ──
# shellcheck disable=SC1090
source "$LIB/runtime.sh"
(
    clear_runtime
    export AGENT_NAME=eval-manual AGENT_SESSION_ID=native-sess \
           AGENT_CUM_INPUT=10 AGENT_CUM_OUTPUT=5 \
           AGENT_MODEL=some-model-9 AGENT_COST_USD=0.4200
    resolve_runtime_cumulative || exit 1
    [[ "$MODEL" == "some-model-9" && "$COST_USD" == "0.4200" ]] || exit 1
)
pass_assert $? "manual runtime carries AGENT_MODEL + AGENT_COST_USD through verbatim"
(
    clear_runtime
    export AGENT_NAME=eval-manual AGENT_SESSION_ID=native-sess \
           AGENT_CUM_INPUT=10 AGENT_CUM_OUTPUT=5
    resolve_runtime_cumulative || exit 1
    [[ "$COST_USD" == "-" ]] || exit 1
)
pass_assert $? "manual runtime defaults an unreported cost to '-' (never an estimate)"
clear_runtime

# ── Case 15 — fail: validate-dir flags a malformed receipt cost row ──
# No runtime → Mode A no-ops; the failure comes purely from the repo-wide
# receipt-shape check at the top of check.sh.
reset_receipts
clear_runtime
mkdir -p receipts
cat > receipts/issue-21.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-bad-1 | claude-code | s | #21 | claude-sonnet-4-5 | 100 | 0 | 0 | 50 | 999 | | 100 | 0 | 0 | 50 | claude-code | bad |
EOF
printf 'feat: bad receipt row (#21)\n' > /tmp/msg-token-badrow
EVAL_LABEL="$EVAL_ID malformed-receipt-row" expect_fail "$CHECK" /tmp/msg-token-badrow
reset_receipts

# ── Case 16 — fail: a v5 row with no source column value ──
mkdir -p receipts
cat > receipts/issue-24.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-nosrc-1 | claude-code | s24 | #24 | claude-sonnet-4-5 | 100 | 0 | 0 | 50 | 150 | | 100 | 0 | 0 | 50 | | no source |
EOF
printf 'feat: sourceless v5 row (#24)\n' > /tmp/msg-token-nosrc
EVAL_LABEL="$EVAL_ID v5-row-needs-a-source" expect_fail "$CHECK" /tmp/msg-token-nosrc
reset_receipts

# ── Case 17 — cost-key counter closes the same-second window (issue #201) ──
reset_receipts
PREFIX="claude-code-${SESSION_ID:0:12}-1900000000-"
N1="$(costs_next_index receipts "$PREFIX")"
append_standalone "${PREFIX}${N1}" "#22" 100 0 0 50
N2="$(costs_next_index receipts "$PREFIX")"
append_standalone "${PREFIX}${N2}" "#22" 100 0 0 50
N3="$(costs_next_index receipts "$PREFIX")"
rc=0
[[ "$N1" == "1" && "$N2" == "2" && "$N3" == "3" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "same-second cost-keys are distinct (${PREFIX}${N1}, ${PREFIX}${N2})"
reset_receipts

# ── Case 18 — fail: a duplicate cost-key across two receipts ──
reset_receipts
append_v5 ck-dup-1 "#25" sess-dup-a 10 0 0 5  10 0 0 5
append_v5 ck-dup-1 "#26" sess-dup-b 10 0 0 5  10 0 0 5
DUP_OUT="$(costs_validate_dir receipts 2>&1)"; DUP_RC=$?
rc=0
[[ $DUP_RC -ne 0 ]] || rc=1
printf '%s' "$DUP_OUT" | grep -q "globally unique" || rc=1
pass_assert $rc "a cost-key reused across receipts is flagged as non-unique"
reset_receipts

# ── Case 19 — reconciliation flags exactly the inflated double-count row (#229) ──
reset_receipts
RSES="recon-session-229"
append_v5 recon-c1 "#310" "$RSES" 96900  0 0 0  96900  0 0 0
append_v5 recon-c2 "#312" "$RSES" 55800  0 0 0  152700 0 0 0
append_v5 recon-c3 "#310" "$RSES" 103400 0 0 0  200300 0 0 0   # Δ INFLATED
RECON_OUT="$(costs_validate_dir receipts 2>&1)"; RECON_RC=$?
rc=0
[[ $RECON_RC -ne 0 ]] || rc=1
printf '%s' "$RECON_OUT" | grep -q "cost row 'recon-c3'" || rc=1
printf '%s' "$RECON_OUT" | grep -qi "double-count" || rc=1
printf '%s' "$RECON_OUT" | grep -qE "cost row 'recon-c1'|cost row 'recon-c2'" && rc=1
pass_assert $rc "reconciliation flags exactly the inflated C3 row post-merge"

# ── Case 20 — reconciliation passes for the correct delta against C2 ──
reset_receipts
append_v5 recon-c1 "#310" "$RSES" 96900 0 0 0  96900  0 0 0
append_v5 recon-c2 "#312" "$RSES" 55800 0 0 0  152700 0 0 0
append_v5 recon-c3 "#310" "$RSES" 47600 0 0 0  200300 0 0 0   # Δ correct
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "reconciliation passes when the delta == cum(n) − cum(n−1)"

# ── Case 21 — branch-local correct delta is skipped (predecessor absent) ──
reset_receipts
append_v5 recon-c1 "#310" "$RSES" 96900 0 0 0  96900  0 0 0
append_v5 recon-c3 "#310" "$RSES" 47600 0 0 0  200300 0 0 0   # C2 absent on this branch
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "branch-local correct delta is skipped (predecessor absent), not flagged"

# ── Case 22 — per-session monotonicity: a backwards cumulative is flagged ──
reset_receipts
append_v5 mono-1 "#40" "mono-session" 100 0 0 0  100 0 0 0
append_v5 mono-2 "#40" "mono-session" 0   0 0 0  80  0 0 100
MONO_OUT="$(costs_validate_dir receipts 2>&1)"; MONO_RC=$?
rc=0
[[ $MONO_RC -ne 0 ]] || rc=1
printf '%s' "$MONO_OUT" | grep -qi "monotonic" || rc=1
pass_assert $rc "backwards cumulative counter flagged (monotonicity/tamper)"

# ── Case 23 — legacy v4 (16-col) and v3 (12-col) rows still parse and validate ──
reset_receipts
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
cat > receipts/issue-51.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-v4-1 | claude-code | v4-sess | #51 | claude-sonnet-4-5 | 1000 | 0 | 0 | 500 | 1500 | 0.0105 | legacy v4 row |
| ck-v4-2 | claude-code | v4-sess | #51 | claude-sonnet-4-5 | 500 | 0 | 0 | 100 | 600 | 0.0030 | 1500 | 0 | 0 | 600 | legacy v4 row |
EOF
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "legacy v3 + v4 rows keep parsing and validating alongside v5"
reset_receipts

# ── Case 24 — a v5 row and a legacy v4 row coexist in one session ──
reset_receipts
mkdir -p receipts
cat > receipts/issue-52.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-mix-v4 | claude-code | mix-sess | #52 | claude-sonnet-4-5 | 1000 | 0 | 0 | 500 | 1500 | 0.0105 | v4 |
EOF
append_v5 ck-mix-v5 "#52" mix-sess 200 0 0 100  1200 0 0 600
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "a v5 row reconciles against its legacy v4 predecessor in the same session"
reset_receipts

# ══════════════════════════════════════════════════════════════
# Runtime adapters — the `cost` verb, exercised against synthetic transcripts.
# These pin the awk extraction that replaced the python readers (issue #355).
# ══════════════════════════════════════════════════════════════

# ── Case 25 — claude-code adapter sums usage and passes native cost through ──
mkdir -p fixtures
cat > fixtures/claude.jsonl <<'EOF'
{"type":"user","sessionId":"cc-sess-1","message":{"role":"user","content":"hi"}}
{"type":"assistant","sessionId":"cc-sess-1","costUSD":0.25,"message":{"role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5}}}
not json at all
{"type":"assistant","sessionId":"cc-sess-1","costUSD":0.5,"message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":3}}}
EOF
CC_OUT="$(CLAUDE_TRANSCRIPT_PATH="$PWD/fixtures/claude.jsonl" bash "$RUNTIMES/claude-code.sh" cost)"
rc=0; [[ "$CC_OUT" == "cc-sess-1 17 100 3000 8 claude-opus-4-7 0.7500" ]] || rc=1
pass_assert $rc "claude-code adapter: cumulative usage + latest model + summed native cost ($CC_OUT)"

# ── Case 26 — a bare invocation behaves as `cost` (continuity) ──
CC_BARE="$(CLAUDE_TRANSCRIPT_PATH="$PWD/fixtures/claude.jsonl" bash "$RUNTIMES/claude-code.sh")"
rc=0; [[ "$CC_BARE" == "$CC_OUT" ]] || rc=1
pass_assert $rc "claude-code adapter: a bare invocation defaults to the cost verb"

# ── Case 27 — no native cost field → the literal `-`, never an estimate ──
cat > fixtures/claude-nocost.jsonl <<'EOF'
{"type":"assistant","sessionId":"cc-sess-2","message":{"role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}
EOF
CC_NC="$(CLAUDE_TRANSCRIPT_PATH="$PWD/fixtures/claude-nocost.jsonl" bash "$RUNTIMES/claude-code.sh" cost)"
rc=0; [[ "$CC_NC" == "cc-sess-2 10 0 0 5 claude-sonnet-4-5 -" ]] || rc=1
pass_assert $rc "claude-code adapter: an unreported cost is '-' ($CC_NC)"

# ── Case 28 — an unreadable transcript exits 2 (runtime present, surface gone) ──
if CLAUDE_TRANSCRIPT_PATH="$PWD/fixtures/nope.jsonl" bash "$RUNTIMES/claude-code.sh" cost >/dev/null 2>&1; then
    rc=1
else
    [[ $? -eq 2 ]] && rc=0 || rc=1
fi
pass_assert $rc "claude-code adapter: a missing transcript exits 2"

# ── Case 29 — codex adapter reads the latest cumulative total, splits cache ──
cat > fixtures/codex.jsonl <<'EOF'
{"type":"session_meta","payload":{"id":"codex-sess-1"}}
{"type":"turn_context","payload":{"collaboration_mode":{"settings":{"model":"gpt-5.5"}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":30,"output_tokens":7},"last_token_usage":{"input_tokens":50,"cached_input_tokens":10,"output_tokens":3}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":220,"cached_input_tokens":80,"output_tokens":11},"last_token_usage":{"input_tokens":120,"cached_input_tokens":50,"output_tokens":4}}}}
EOF
CX_OUT="$(CODEX_TRANSCRIPT_PATH="$PWD/fixtures/codex.jsonl" bash "$RUNTIMES/codex.sh" cost)"
rc=0; [[ "$CX_OUT" == "codex-sess-1 140 0 80 11 gpt-5.5 -" ]] || rc=1
pass_assert $rc "codex adapter: latest total_token_usage, cached split out, no native cost ($CX_OUT)"

# ── Case 30 — codex adapter passes a native cost through when the stream has one ──
cat > fixtures/codex-cost.jsonl <<'EOF'
{"type":"session_meta","payload":{"id":"codex-sess-2"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":2},"total_cost_usd":0.0301}}}
EOF
CX_COST="$(CODEX_TRANSCRIPT_PATH="$PWD/fixtures/codex-cost.jsonl" bash "$RUNTIMES/codex.sh" cost)"
rc=0; [[ "$CX_COST" == "codex-sess-2 10 0 0 2 unknown 0.0301" ]] || rc=1
pass_assert $rc "codex adapter: a native total_cost_usd is passed through ($CX_COST)"
rm -rf fixtures

# ══════════════════════════════════════════════════════════════
# Hardening: no python is reachable from the commit path (issue #355).
# ══════════════════════════════════════════════════════════════
rc=0
if grep -rnE '(^|[^[:alnum:]_])python3?[[:space:]]' \
    "$DIR/check.sh" "$DIR/hooks" "$RUNTIMES" "$DIR/lib"/*.sh 2>/dev/null \
    | grep -vE ':[[:space:]]*#' | grep -q .; then
    rc=1
fi
pass_assert $rc "no python invocation remains in check.sh / hooks / runtimes / lib"

eval_done

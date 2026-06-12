#!/usr/bin/env bash
set -u
EVAL_ID="agent-steering-accounting"
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

# ──────────────────────────────────────────────────────────────
# Case 0 — sanity: lib/argv.py round-trips UTF-8 commit subjects (#140).
# ──────────────────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
    eval_assertions=$(( eval_assertions + 1 ))
    ARGV_HELPER=".governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/argv.py"
    /bin/sh -c 'while :; do sleep 1; done' steering-argv-probe \
        $'feat: em-dash \xe2\x80\x94 arrow \xe2\x86\x92 (#1)' &
    PROBE_PID=$!
    sleep 0.3
    if probe_out="$(LC_ALL=C python3 "$ARGV_HELPER" "$PROBE_PID" 2>/dev/null)" \
        && printf '%s' "$probe_out" | grep -q $'\xe2\x80\x94' \
        && printf '%s' "$probe_out" | grep -q $'\xe2\x86\x92'; then
        printf '    ✓ %s — argv.py preserves UTF-8 argv on macOS (#140)\n' "$EVAL_ID"
    else
        printf '    ✗ %s — argv.py mangled UTF-8 — issue #140 regression\n' "$EVAL_ID"
        eval_failures=$(( eval_failures + 1 ))
    fi
    kill "$PROBE_PID" 2>/dev/null
    wait "$PROBE_PID" 2>/dev/null
else
    printf '    ⊘ %s — argv.py macOS round-trip skipped (uname=%s)\n' \
        "$EVAL_ID" "$(uname -s)"
fi

# Steering rows now live in receipts/issue-<N>.md under ## Accounting →
# ### Steering (issue #201). All fixture rows belong to issue #1.
RECEIPT="receipts/issue-1.md"
SESSION_ID="abc123def456fixture"
SS="abc123def456"
EPOCH=1800000000

agent_block() {
    printf 'Agent: claude-code\n'
    printf 'Session: %s\n' "$SESSION_ID"
}

write_msg() {
    # write_msg <file> <subject> [count] [types-summary] [tiers-summary]
    local file="$1" subject="$2"
    local count="${3:-0}"
    local types="${4:-none}"
    local tiers="${5:-none}"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        agent_block
        printf 'Steer-Count: %s\n' "$count"
        printf 'Steer-Types: %s\n' "$types"
        printf 'Steer-Tiers: %s\n' "$tiers"
    } > "$file"
}

write_msg_raw() {
    local file="$1" subject="$2" body="$3"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        agent_block
        printf '%s\n' "$body"
    } > "$file"
}

write_msg_human() {
    local file="$1" subject="$2"
    local count="${3:-0}"
    local types="${4:-none}"
    local tiers="${5:-none}"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        printf 'Steer-Count: %s\n' "$count"
        printf 'Steer-Types: %s\n' "$types"
        printf 'Steer-Tiers: %s\n' "$tiers"
    } > "$file"
}

write_msg_human_bare() {
    local file="$1" subject="$2"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
    } > "$file"
}

ensure_receipt() {
    # Seed receipts/issue-1.md with the ## Accounting → ### Steering shape if
    # absent, so direct row appends (including malformed fixtures the ledger
    # CLI would refuse to mint) land in the right sub-table.
    mkdir -p receipts
    if [[ ! -f "$RECEIPT" ]]; then
        cat > "$RECEIPT" <<EOF
# Receipt: issue 1

## Accounting

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
EOF
    fi
}

append_row() {
    # append_row <steer-key> <type> <reason> [commit-cell] [tier]
    local key="$1" typ="$2" reason="$3" commit_cell="${4:-feat: x}" tier="${5:-structural}"
    ensure_receipt
    printf '| %s | %s | #1 | %s | %s | %s | %s |\n' \
        "$key" "$SESSION_ID" "$typ" "$tier" "$reason" "$commit_cell" >> "$RECEIPT"
}

reset_ledger() {
    rm -rf receipts
    git add -A receipts 2>/dev/null || true
    git commit --quiet --no-verify -m "chore: reset receipts" >/dev/null 2>&1 || true
}

# ──────────────────────────────────────────────────────────────
# Case 1 — pass: agent commit, zero events, summary triple stamped
# ──────────────────────────────────────────────────────────────
write_msg /tmp/msg-no-events "feat: no steering"
EVAL_LABEL="$EVAL_ID no-events" expect_pass "$CHECK" /tmp/msg-no-events

# ──────────────────────────────────────────────────────────────
# Case 2 — pass: clean (row staged + summary triple agrees)
# ──────────────────────────────────────────────────────────────
KEY1="steer-${SS}-${EPOCH}-1"
append_row "$KEY1" "interrupt" "" "feat: with steering"
git add receipts
write_msg /tmp/msg-pass "feat: with steering" 1 "interrupt=1" "structural=1"
EVAL_LABEL="$EVAL_ID pass-clean" expect_pass "$CHECK" /tmp/msg-pass
git commit --quiet --no-verify -m "feat: persisted clean row"

# ──────────────────────────────────────────────────────────────
# Case 3 — fail: receipt rows out of order (append-only invariant)
# ──────────────────────────────────────────────────────────────
reset_ledger
append_row "steer-${SS}-1800000100-1" "interrupt" "later epoch first"
append_row "steer-${SS}-1700000000-1" "interrupt" "earlier epoch second"
git add receipts
write_msg /tmp/msg-reorder "feat: reordered ledger" 2 "interrupt=2" "structural=2"
EVAL_LABEL="$EVAL_ID reordered" expect_fail "$CHECK" /tmp/msg-reorder

# ──────────────────────────────────────────────────────────────
# Case 4 — fail: Steer-Count disagrees with newly-added row count
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_A="steer-${SS}-${EPOCH}-1"
append_row "$KEY_A" "interrupt" "ok" "feat: bad count"
git add receipts
write_msg /tmp/msg-bad-count "feat: bad count" 99 "interrupt=99" "structural=99"
EVAL_LABEL="$EVAL_ID bad-count" expect_fail "$CHECK" /tmp/msg-bad-count

# ──────────────────────────────────────────────────────────────
# Case 5 — fail: summary trailers missing entirely (Agent: present)
# ──────────────────────────────────────────────────────────────
write_msg_raw /tmp/msg-no-summary "feat: no summary" ""
EVAL_LABEL="$EVAL_ID missing-summary" expect_fail "$CHECK" /tmp/msg-no-summary

# ──────────────────────────────────────────────────────────────
# Case 6 — fail: Steer-Types breakdown disagrees with matched row's type
# ──────────────────────────────────────────────────────────────
write_msg /tmp/msg-bad-types "feat: bad count" 1 "correction=1" "structural=1"
EVAL_LABEL="$EVAL_ID bad-types" expect_fail "$CHECK" /tmp/msg-bad-types

# ──────────────────────────────────────────────────────────────
# Case 7 — pass: commit with no `Agent:` trailer still satisfies the
# universal contract when the summary triple is stamped.
# ──────────────────────────────────────────────────────────────
reset_ledger
write_msg_human /tmp/msg-no-agent "fix: standalone steering"
EVAL_LABEL="$EVAL_ID no-agent-with-triple" expect_pass "$CHECK" /tmp/msg-no-agent

# ──────────────────────────────────────────────────────────────
# Case 8 — fail: Steer-Count: 0 but Steer-Types totals to 1
# ──────────────────────────────────────────────────────────────
write_msg_raw /tmp/msg-zero-mismatch "feat: zero mismatch" \
    "Steer-Count: 0
Steer-Types: interrupt=1
Steer-Tiers: structural=1"
EVAL_LABEL="$EVAL_ID zero-mismatch" expect_fail "$CHECK" /tmp/msg-zero-mismatch

# ──────────────────────────────────────────────────────────────
# Case 9 — fail: receipt row uses retired `tool-denial` type
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_DEN="steer-${SS}-1800000200-1"
append_row "$KEY_DEN" "tool-denial" "should be rejected" "feat: retired type"
git add receipts
write_msg /tmp/msg-retired-type "feat: retired type" 1 "tool-denial=1" "structural=1"
EVAL_LABEL="$EVAL_ID retired-tool-denial-type" expect_fail "$CHECK" /tmp/msg-retired-type

# ──────────────────────────────────────────────────────────────
# Case 9b — fail: a steering row with an empty issue (issue #201, decision 6:
# every accounted event must resolve to an issue — no issue-less rows).
# ──────────────────────────────────────────────────────────────
reset_ledger
ensure_receipt
printf '| steer-%s-1800000250-1 | %s |  | interrupt | structural | no issue | feat: x |\n' \
    "$SS" "$SESSION_ID" >> "$RECEIPT"
git add receipts
write_msg /tmp/msg-no-issue "feat: issueless steering" 1 "interrupt=1" "structural=1"
EVAL_LABEL="$EVAL_ID issueless-row-rejected" expect_fail "$CHECK" /tmp/msg-no-issue

# ──────────────────────────────────────────────────────────────
# Case 10 — pass: retry-after-failed-commit-msg (#66)
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_RETRY="steer-${SS}-1800000300-1"
append_row "$KEY_RETRY" "correction" "redirected" "feat: retry case"
git add receipts
write_msg /tmp/msg-retry "feat: retry case" 1 "correction=1" "structural=1"
EVAL_LABEL="$EVAL_ID retry-after-failed-commit-msg" expect_pass "$CHECK" /tmp/msg-retry

# ──────────────────────────────────────────────────────────────
# Case 11 — fail: commit with no `Agent:` trailer AND no summary triple.
# ──────────────────────────────────────────────────────────────
reset_ledger
write_msg_human_bare /tmp/msg-bare "chore: bare commit"
EVAL_LABEL="$EVAL_ID bare-commit-no-triple" expect_fail "$CHECK" /tmp/msg-bare

# ──────────────────────────────────────────────────────────────
# Case 12 — pass: per-commit waiver bypasses the trailer + ledger checks.
# ──────────────────────────────────────────────────────────────
reset_ledger
{
    printf 'fix(ledger): repair epoch ordering\n\n'
    printf 'Body line.\n\n'
    printf 'governance: allow-agent-steering-accounting reorder-repair after squash-merge inversion\n'
} > /tmp/msg-waiver
EVAL_LABEL="$EVAL_ID waiver-bypasses-cross-checks" expect_pass "$CHECK" /tmp/msg-waiver

# ──────────────────────────────────────────────────────────────
# Case 13 — fail: waiver token with no reason.
# ──────────────────────────────────────────────────────────────
{
    printf 'fix(ledger): bare waiver\n\n'
    printf 'Body line.\n\n'
    printf 'governance: allow-agent-steering-accounting\n'
} > /tmp/msg-waiver-bare
EVAL_LABEL="$EVAL_ID waiver-without-reason-fails" expect_fail "$CHECK" /tmp/msg-waiver-bare

# ──────────────────────────────────────────────────────────────
# Case 14 — pass: Mode B on `main` validates HEAD's trailers (no base).
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_OK="steer-${SS}-1800000900-1"
append_row "$KEY_OK" "interrupt" "" "feat: post-squash on main"
git add receipts
{
    printf 'feat: post-squash on main\n\n'
    printf 'Body.\n\n'
    agent_block
    printf 'Steer-Count: 1\n'
    printf 'Steer-Types: interrupt=1\n'
    printf 'Steer-Tiers: structural=1\n'
} > /tmp/msg-mode-b-pass
git commit --quiet --no-verify -F /tmp/msg-mode-b-pass
EVAL_LABEL="$EVAL_ID mode-b-on-main-valid" expect_pass "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 15 — fail: Mode B on `main` with a missing summary triple on HEAD.
# ──────────────────────────────────────────────────────────────
reset_ledger
{
    printf 'chore: bad squash-merge commit\n\n'
    printf 'Body without summary trailers.\n'
} > /tmp/msg-mode-b-fail
git commit --allow-empty --quiet --no-verify -F /tmp/msg-mode-b-fail
EVAL_LABEL="$EVAL_ID mode-b-on-main-missing-triple" expect_fail "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 16 — pass: squash-merge body with two stacked trailer triples (#136).
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_S1="steer-${SS}-1800001000-1"
KEY_S2="steer-${SS}-1800001100-1"
append_row "$KEY_S1" "interrupt" "" "feat: squashed pair"
append_row "$KEY_S2" "correction" "" "feat: squashed pair"
git add receipts
{
    printf 'feat: squashed pair\n\n'
    printf 'Body line.\n\n'
    agent_block
    printf 'Steer-Count: 1\n'
    printf 'Steer-Types: interrupt=1\n'
    printf 'Steer-Tiers: structural=1\n\n'
    printf 'Steer-Count: 1\n'
    printf 'Steer-Types: correction=1\n'
    printf 'Steer-Tiers: structural=1\n'
} > /tmp/msg-squash-aggregate
git commit --quiet --no-verify -F /tmp/msg-squash-aggregate
EVAL_LABEL="$EVAL_ID squash-merge-sums-stacked-triples" expect_pass "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 17 — pass: squashed body where the trailing sub-commit's triple is
# the all-zero default (sum-across-occurrences, not last-wins).
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_S3="steer-${SS}-1800001200-1"
KEY_S4="steer-${SS}-1800001300-1"
append_row "$KEY_S3" "interrupt" "" "feat: squashed with trailing zero"
append_row "$KEY_S4" "interrupt" "" "feat: squashed with trailing zero"
git add receipts
{
    printf 'feat: squashed with trailing zero\n\n'
    printf 'Body line.\n\n'
    agent_block
    printf 'Steer-Count: 2\n'
    printf 'Steer-Types: interrupt=2\n'
    printf 'Steer-Tiers: structural=2\n\n'
    printf 'Steer-Count: 0\n'
    printf 'Steer-Types: none\n'
    printf 'Steer-Tiers: none\n'
} > /tmp/msg-squash-trailing-zero
git commit --quiet --no-verify -F /tmp/msg-squash-trailing-zero
EVAL_LABEL="$EVAL_ID squash-merge-trailing-zero-block" expect_pass "$CHECK"

reset_ledger

# ──────────────────────────────────────────────────────────────
# Case 18 — conf overlay drives the lexical fallback list + CANDIDATE_MAX_LEN.
# ──────────────────────────────────────────────────────────────
eval_assertions=$(( eval_assertions + 1 ))
CONF_LIB=".governance/packs/governance-kit/audit/directives/$EVAL_ID/lib"
mkdir -p .governance/conf
printf 'scratch that\n!back up\nCANDIDATE_MAX_LEN=4000\n' \
    > $EVAL_CONF
if python3 - "$CONF_LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import conf
phrases = conf.effective_list()
assert "scratch that" in phrases, "overlay add missing"
assert "back up" not in phrases, "!back up not dropped"
assert "no" in phrases, "default 'no' lost"
assert conf.get_int("CANDIDATE_MAX_LEN", 2000) == 4000, "scalar override ignored"
rx = conf.lexical_fallback_re()
assert rx.match("scratch that idea"), "added phrase does not match"
assert not rx.match("back up please"), "dropped phrase still matches"
PY
then
    printf '    ✓ %s conf-overlay — defaults+overlay drive triggers and CANDIDATE_MAX_LEN\n' "$EVAL_ID"
else
    printf '    ✗ %s conf-overlay — loader did not honor the overlay\n' "$EVAL_ID"
    eval_failures=$(( eval_failures + 1 ))
fi
eval_assertions=$(( eval_assertions + 1 ))
if GOVERNANCE_CANDIDATE_MAX_LEN=7777 python3 - "$CONF_LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import conf
assert conf.get_int("CANDIDATE_MAX_LEN", 2000) == 7777, "env did not win"
PY
then
    printf '    ✓ %s conf-env — GOVERNANCE_CANDIDATE_MAX_LEN overrides the overlay\n' "$EVAL_ID"
else
    printf '    ✗ %s conf-env — env did not override the overlay scalar\n' "$EVAL_ID"
    eval_failures=$(( eval_failures + 1 ))
fi
eval_assertions=$(( eval_assertions + 1 ))
printf 'CANDIDATE_MAX_LEN=lots\n' > $EVAL_CONF
if python3 - "$CONF_LIB" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import conf
try:
    conf.get_int("CANDIDATE_MAX_LEN", 2000)
except ValueError:
    sys.exit(0)
sys.exit(1)
PY
then
    printf '    ✓ %s conf-malformed — non-integer scalar raises\n' "$EVAL_ID"
else
    printf '    ✗ %s conf-malformed — bad scalar did not raise\n' "$EVAL_ID"
    eval_failures=$(( eval_failures + 1 ))
fi
rm -f $EVAL_CONF

eval_done

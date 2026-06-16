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

# Issue #293 retired the per-commit summary trailers. The directive's only
# contract now is the ledger-shape check (validate-dir), which check.sh runs in
# both modes. Steering rows live in receipts/issue-<N>.md under ## Accounting →
# ### Steering (issue #201).
STEER_LEDGER=".governance/packs/governance-kit/audit/directives/$EVAL_ID/lib/ledger.py"
SS2="sess229abcdef"

reset_ledger() {
    rm -rf receipts
    git add -A receipts 2>/dev/null || true
    git commit --quiet --no-verify -m "chore: reset receipts" >/dev/null 2>&1 || true
}

add_v2() {
    # add_v2 <receipt> <steer-key> <issue> <type> <tier> <ordinal> <timestamp>
    mkdir -p receipts
    python3 "$STEER_LEDGER" append-row "$1" "$2" "$SS2" "$3" "$4" "$5" "" "feat: v2 row" "$6" "$7"
}

seed_raw() {
    # seed_raw <issue-file-basename> <raw-table-row> — write a malformed row the
    # ledger CLI would refuse to mint, so check.sh's validate-dir can reject it.
    mkdir -p receipts
    local file="receipts/$1"
    if [[ ! -f "$file" ]]; then
        cat > "$file" <<'EOF'
# Receipt

## Accounting

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
EOF
    fi
    printf '%s\n' "$2" >> "$file"
}

# ── Case 1 — pass: no receipts at all (nothing to validate) ──
reset_ledger
EVAL_LABEL="$EVAL_ID empty-repo" expect_pass "$CHECK"

# ── Case 2 — pass: clean v2 rows across receipts validate cleanly ──
reset_ledger
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002000-1" "#1" interrupt  structural 1 "2026-06-12T00:00:01Z"
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002001-2" "#1" correction classifier 2 "2026-06-12T00:00:02Z"
add_v2 "receipts/issue-2.md" "steer-${SS2:0:12}-1800002002-1" "#2" interrupt  structural 3 "2026-06-12T00:00:03Z"
EVAL_LABEL="$EVAL_ID clean-v2-rows" expect_pass "$CHECK"

# ── Case 3 — fail: retired `tool-denial` type ──
reset_ledger
seed_raw "issue-1.md" "| steer-x-1800000200-1 | $SS2 | #1 | tool-denial | structural | should be rejected | feat: retired type |"
EVAL_LABEL="$EVAL_ID retired-tool-denial-type" expect_fail "$CHECK"

# ── Case 4 — fail: a steering row with an empty issue (issue #201, decision 6) ──
reset_ledger
seed_raw "issue-1.md" "| steer-x-1800000250-1 | $SS2 |  | interrupt | structural | no issue | feat: x |"
EVAL_LABEL="$EVAL_ID issueless-row-rejected" expect_fail "$CHECK"

# ── Case 5 — fail: cross-branch duplicate (session, ordinal) post-merge ──
# Branch B re-recorded branch A's event under its own receipt; post-merge both
# carry the same (session, ordinal). Pre-fix (positional dedup) this was
# structurally undetectable (issue #229).
reset_ledger
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002100-1" "#1" interrupt structural 1 "2026-06-12T01:00:01Z"
add_v2 "receipts/issue-2.md" "steer-${SS2:0:12}-1800002200-1" "#2" interrupt structural 1 "2026-06-12T01:00:01Z"
EVAL_LABEL="$EVAL_ID cross-branch-duplicate" expect_fail "$CHECK"

# ── Case 6 — fail: non-monotonic ordinals within a session ──
reset_ledger
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002300-1" "#1" interrupt structural 5 "2026-06-12T02:00:05Z"
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002301-2" "#1" interrupt structural 2 "2026-06-12T02:00:02Z"
EVAL_LABEL="$EVAL_ID non-monotonic-ordinals" expect_fail "$CHECK"

# ── Case 7 — identity dedup boundary: existing-ordinals reports recorded ones ──
reset_ledger
eval_assertions=$(( eval_assertions + 1 ))
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002400-1" "#1" interrupt structural 1 "2026-06-12T03:00:01Z"
add_v2 "receipts/issue-1.md" "steer-${SS2:0:12}-1800002401-2" "#1" interrupt structural 3 "2026-06-12T03:00:03Z"
ORDS="$(python3 "$STEER_LEDGER" existing-ordinals receipts "$SS2" | tr '\n' ',' )"
if [[ "$ORDS" == "1,3," ]]; then
    printf '    ✓ %s — existing-ordinals reports the recorded identity set (dedup boundary)\n' "$EVAL_ID"
else
    printf '    ✗ %s — existing-ordinals returned %q (expected 1,3,)\n' "$EVAL_ID" "$ORDS" >&2
    eval_failures=$(( eval_failures + 1 ))
fi
reset_ledger

# ── Case 8 — conf overlay drives the lexical fallback list + CANDIDATE_MAX_LEN ──
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
reset_ledger

eval_done

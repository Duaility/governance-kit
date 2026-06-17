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

# The directive's contract is two-fold (issue #325):
#   1. validate-dir — the repo-wide ledger-shape check (cases 2–7 below). Steering
#      rows live in receipts/issue-<N>.md under ## Accounting → ### Steering.
#   2. the `## Steering` attestation gate — on receipts ADDED in the change set, a
#      fresh-context sub-agent must record a present, verdict-bearing section
#      (cases 8–11). The hook makes no `claude -p` / network call.
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

# ── Hardening: the commit path makes no `claude -p` shell-out (issue #325) ──
# The classifier that did is gone; assert its source files are not shipped and
# that no shipped CODE (lib/*.py — prose comments are allowed to describe the
# retired behavior) invokes a headless CLI.
eval_assertions=$(( eval_assertions + 1 ))
DIR=".governance/packs/governance-kit/audit/directives/$EVAL_ID"
if [[ ! -e "$DIR/lib/classifier.py" && ! -e "$DIR/lib/extract.py" \
      && ! -e "$DIR/hooks" && ! -e "$DIR/runtimes" ]] \
    && ! grep -rqE 'claude[[:space:]]+-p|codex[[:space:]]+exec' "$DIR"/lib/*.py 2>/dev/null; then
    printf '    ✓ %s — no in-hook classifier / `claude -p` shell-out remains\n' "$EVAL_ID"
else
    printf '    ✗ %s — a classifier / headless-CLI shell-out is still present\n' "$EVAL_ID" >&2
    eval_failures=$(( eval_failures + 1 ))
fi

# ── Case 1 — pass: no receipts at all (nothing to validate) ──
reset_ledger
EVAL_LABEL="$EVAL_ID empty-repo" expect_pass "$CHECK"

# ── Case 2 — pass: clean v2 rows across receipts validate cleanly ──
# (Receipts are written but NOT staged, so they are not in the change set and the
#  attestation gate does not apply — this case isolates validate-dir.)
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

# ── Case 8 — fail: a NEW (staged) receipt missing the `## Steering` attestation ──
# The change set adds a receipt with no `## Steering` section; the sub-agent
# attestation has not been recorded, so the gate fires.
reset_ledger
mkdir -p receipts
cat > receipts/issue-70-no-steering.md <<'EOF'
# Receipt seventy

## Notes

Work happened on issue 70.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-missing-steering" expect_fail "$CHECK"

# ── Case 9 — pass: a NEW (staged) receipt whose `## Steering` carries a verdict ──
reset_ledger
mkdir -p receipts
cat > receipts/issue-71-with-steering.md <<'EOF'
# Receipt seventy-one

## Notes

Work happened on issue 71.

## Steering

Fresh-context sub-agent reviewed the session transcript:

- PASS — no human-steering events (no interrupts, no corrections) in this session.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-steering-verdict-ok" expect_pass "$CHECK"

# ── Case 10 — fail: `## Steering` present but records no PASS/REFUTED verdict ──
reset_ledger
mkdir -p receipts
cat > receipts/issue-72-steering-no-verdict.md <<'EOF'
# Receipt seventy-two

## Notes

Work happened on issue 72.

## Steering

I looked at the transcript and it seemed fine.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-steering-no-verdict" expect_fail "$CHECK"

# ── Case 11 — pass: a pre-existing (committed) receipt without `## Steering` is
#                grandfathered (not in the change set) ──
reset_ledger
mkdir -p receipts
cat > receipts/issue-73-grandfathered.md <<'EOF'
# Receipt seventy-three

## Notes

Pre-existing work, no steering section.
EOF
stage_all
git commit --quiet --no-verify -m "docs: grandfathered receipt" >/dev/null 2>&1 || true
EVAL_LABEL="$EVAL_ID grandfathered-no-steering" expect_pass "$CHECK"

# ── Case 12 — pass: a per-receipt waiver exempts a staged receipt ──
reset_ledger
mkdir -p receipts
cat > receipts/issue-74-waivered.md <<'EOF'
<!-- governance: allow-agent-steering-accounting transcript unavailable in this context -->
# Receipt seventy-four

## Notes

Steering attestation waived for this commit.
EOF
stage_all
EVAL_LABEL="$EVAL_ID waiver-exempts" expect_pass "$CHECK"
reset_ledger

eval_done

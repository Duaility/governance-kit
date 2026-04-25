#!/usr/bin/env bash
set -u
EVAL_ID="agent-steering-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Seed the ledger with the install-assets header so the file shape is real.
cp "$PACK_DIR/directives/$EVAL_ID/install-assets/STEERING.md" STEERING.md

# Stable ids used across cases. SESSION_ID is the per-session column value;
# SS is the session-short slice that's mirrored into steer-keys.
SESSION_ID="abc123def456fixture"
SS="abc123def456"
EPOCH=1800000000

# Fixture commits all carry an `Agent:` trailer so the always-on summary
# rule kicks in. A non-agent fixture is added as Case 9 to verify the exempt
# branch.
agent_block() {
    printf 'Agent: claude-code\n'
    printf 'Session: %s\n' "$SESSION_ID"
}

write_msg() {
    # write_msg <file> <subject> [trailer-key ...]
    # Always stamps the summary triple; with zero keys, summaries are
    # `Steer-Count: 0` / `Steer-Types: none` / `Steer-Tiers: none`.
    # append_row uses type=interrupt / tier=structural for fixtures.
    local file="$1"; shift
    local subject="$1"; shift
    local n=$#
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        agent_block
        if (( n > 0 )); then
            printf 'Steer-Count: %d\n' "$n"
            printf 'Steer-Types: interrupt=%d\n' "$n"
            printf 'Steer-Tiers: structural=%d\n' "$n"
            for k in "$@"; do
                printf 'Steer-Key: %s\n' "$k"
            done
        else
            printf 'Steer-Count: 0\n'
            printf 'Steer-Types: none\n'
            printf 'Steer-Tiers: none\n'
        fi
    } > "$file"
}

write_msg_raw() {
    # Direct trailer body for cases that test malformed summary trailers.
    # Includes an Agent: trailer so the always-on rule is in scope.
    local file="$1" subject="$2" body="$3"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        agent_block
        printf '%s\n' "$body"
    } > "$file"
}

write_msg_human() {
    # Non-agent commit — no Agent: trailer, no Steer-* trailers expected.
    local file="$1" subject="$2"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
    } > "$file"
}

append_row() {
    # append_row <steer-key> <type> <reason>
    # 7-col schema: steer-key | session | issue | type | tier | user-reason | commit
    local key="$1" typ="$2" reason="$3"
    printf '| %s | %s | #1 | %s | structural | %s | feat: x |\n' \
        "$key" "$SESSION_ID" "$typ" "$reason" >> STEERING.md
}

reset_ledger() {
    cp "$PACK_DIR/directives/$EVAL_ID/install-assets/STEERING.md" STEERING.md
    git add STEERING.md
    git commit --quiet --no-verify -m "chore: reset ledger" >/dev/null 2>&1 || true
}

# ──────────────────────────────────────────────────────────────
# Case 1 — pass: agent commit, zero events, summary triple stamped
# ──────────────────────────────────────────────────────────────
git add STEERING.md
git commit --quiet --no-verify -m "chore: seed ledger"

write_msg /tmp/msg-no-events "feat: no steering"
EVAL_LABEL="$EVAL_ID no-events" expect_pass "$CHECK" /tmp/msg-no-events

# ──────────────────────────────────────────────────────────────
# Case 2 — pass: clean (row + matching trailer + summaries)
# ──────────────────────────────────────────────────────────────
KEY1="steer-${SS}-${EPOCH}-1"
append_row "$KEY1" "interrupt" ""
git add STEERING.md
write_msg /tmp/msg-pass "feat: with steering" "$KEY1"
EVAL_LABEL="$EVAL_ID pass-clean" expect_pass "$CHECK" /tmp/msg-pass
git commit --quiet --no-verify -m "feat: persisted clean row"

# ──────────────────────────────────────────────────────────────
# Case 3 — fail: missing trailer (row added, commit message has none)
# ──────────────────────────────────────────────────────────────
KEY2="steer-${SS}-${EPOCH}-2"
append_row "$KEY2" "interrupt" ""
git add STEERING.md
write_msg /tmp/msg-no-trailer "feat: forgot trailer"
EVAL_LABEL="$EVAL_ID missing-trailer" expect_fail "$CHECK" /tmp/msg-no-trailer
# Don't commit — leave staged for cleanup via reset.
git restore --staged STEERING.md
git checkout -- STEERING.md

# ──────────────────────────────────────────────────────────────
# Case 4 — fail: missing row (trailer present, no row in ledger)
# ──────────────────────────────────────────────────────────────
PHANTOM_KEY="steer-${SS}-${EPOCH}-99"
git add STEERING.md  # no-op stage; ensures clean diff
write_msg /tmp/msg-phantom "feat: phantom trailer" "$PHANTOM_KEY"
EVAL_LABEL="$EVAL_ID missing-row" expect_fail "$CHECK" /tmp/msg-phantom

# ──────────────────────────────────────────────────────────────
# Case 5 — fail: ledger rows out of order (append-only invariant)
# ──────────────────────────────────────────────────────────────
# Reset ledger, then write two rows where the second's epoch < first's.
reset_ledger
append_row "steer-${SS}-1800000100-1" "interrupt" "later epoch first"
append_row "steer-${SS}-1700000000-1" "interrupt" "earlier epoch second"
git add STEERING.md
write_msg /tmp/msg-reorder "feat: reordered ledger" \
    "steer-${SS}-1800000100-1" "steer-${SS}-1700000000-1"
EVAL_LABEL="$EVAL_ID reordered" expect_fail "$CHECK" /tmp/msg-reorder

# ──────────────────────────────────────────────────────────────
# Case 6 — fail: Steer-Count disagrees with Steer-Key trailer count
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_A="steer-${SS}-${EPOCH}-1"
append_row "$KEY_A" "interrupt" "ok"
git add STEERING.md
write_msg_raw /tmp/msg-bad-count "feat: bad count" \
    "Steer-Count: 99
Steer-Types: interrupt=99
Steer-Tiers: structural=99
Steer-Key: $KEY_A"
EVAL_LABEL="$EVAL_ID bad-count" expect_fail "$CHECK" /tmp/msg-bad-count

# ──────────────────────────────────────────────────────────────
# Case 7 — fail: agent commit, summary trailers missing entirely
# ──────────────────────────────────────────────────────────────
# Even with no Steer-Key, an agent commit must still stamp Steer-Count: 0.
write_msg_raw /tmp/msg-no-summary "feat: no summary" ""
EVAL_LABEL="$EVAL_ID missing-summary-agent" expect_fail "$CHECK" /tmp/msg-no-summary

# ──────────────────────────────────────────────────────────────
# Case 8 — fail: Steer-Types breakdown disagrees with matched row's type
# ──────────────────────────────────────────────────────────────
write_msg_raw /tmp/msg-bad-types "feat: wrong types" \
    "Steer-Count: 1
Steer-Types: correction=1
Steer-Tiers: structural=1
Steer-Key: $KEY_A"
EVAL_LABEL="$EVAL_ID bad-types" expect_fail "$CHECK" /tmp/msg-bad-types

# ──────────────────────────────────────────────────────────────
# Case 9 — pass: non-agent (human) commit, no Steer-* trailers required
# ──────────────────────────────────────────────────────────────
# Reset to a clean ledger so the human commit has no row diff.
reset_ledger
write_msg_human /tmp/msg-human "fix: typo by hand"
EVAL_LABEL="$EVAL_ID human-commit-exempt" expect_pass "$CHECK" /tmp/msg-human

# ──────────────────────────────────────────────────────────────
# Case 10 — fail: Steer-Count: 0 but Steer-Types totals to 1
# ──────────────────────────────────────────────────────────────
# Catches the zero-count-with-stale-types shape that the matched_rows
# cross-check skips on empty event sets.
write_msg_raw /tmp/msg-zero-mismatch "feat: zero mismatch" \
    "Steer-Count: 0
Steer-Types: interrupt=1
Steer-Tiers: structural=1"
EVAL_LABEL="$EVAL_ID zero-mismatch" expect_fail "$CHECK" /tmp/msg-zero-mismatch

# ──────────────────────────────────────────────────────────────
# Case 11 — fail: ledger row uses retired `tool-denial` type
# ──────────────────────────────────────────────────────────────
# Tool denials were removed; the validator should now reject any row
# carrying that type as malformed.
reset_ledger
KEY_DEN="steer-${SS}-1800000200-1"
append_row "$KEY_DEN" "tool-denial" "should be rejected"
git add STEERING.md
write_msg /tmp/msg-retired-type "feat: retired type" "$KEY_DEN"
EVAL_LABEL="$EVAL_ID retired-tool-denial-type" expect_fail "$CHECK" /tmp/msg-retired-type

eval_done

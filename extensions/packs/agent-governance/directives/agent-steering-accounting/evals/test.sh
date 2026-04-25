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

write_msg() {
    # write_msg <file> <subject> [trailer-key ...]
    # Stamps Steer-Count/Types/Tiers automatically from the keys + this
    # eval's hard-coded type ("tool-denial") and tier ("structural") that
    # append_row uses. Cases that need other shapes call write_msg_raw.
    local file="$1"; shift
    local subject="$1"; shift
    local n=$#
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
        if (( n > 0 )); then
            printf 'Steer-Count: %d\n' "$n"
            printf 'Steer-Types: tool-denial=%d\n' "$n"
            printf 'Steer-Tiers: structural=%d\n' "$n"
            for k in "$@"; do
                printf 'Steer-Key: %s\n' "$k"
            done
        fi
    } > "$file"
}

write_msg_raw() {
    # Direct trailer body for cases that test malformed summary trailers.
    local file="$1" subject="$2" body="$3"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
        printf '%s\n' "$body"
    } > "$file"
}

append_row() {
    # append_row <steer-key> <type> <reason>
    local key="$1" typ="$2" reason="$3"
    printf '| %s | %s | #1 | %s | structural | Bash | rm -rf / | %s | feat: x |\n' \
        "$key" "$SESSION_ID" "$typ" "$reason" >> STEERING.md
}

reset_ledger() {
    cp "$PACK_DIR/directives/$EVAL_ID/install-assets/STEERING.md" STEERING.md
    git add STEERING.md
    git commit --quiet --no-verify -m "chore: reset ledger" >/dev/null 2>&1 || true
}

# ──────────────────────────────────────────────────────────────
# Case 1 — pass: no events (clean ledger, no trailers, no diff)
# ──────────────────────────────────────────────────────────────
git add STEERING.md
git commit --quiet --no-verify -m "chore: seed ledger"

write_msg /tmp/msg-no-events "feat: no steering"
EVAL_LABEL="$EVAL_ID no-events" expect_pass "$CHECK" /tmp/msg-no-events

# ──────────────────────────────────────────────────────────────
# Case 2 — pass: clean (row + matching trailer)
# ──────────────────────────────────────────────────────────────
KEY1="steer-${SS}-${EPOCH}-1"
append_row "$KEY1" "tool-denial" "verbatim user reason"
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
append_row "steer-${SS}-1800000100-1" "tool-denial" "later epoch first"
append_row "steer-${SS}-1700000000-1" "tool-denial" "earlier epoch second"
git add STEERING.md
write_msg /tmp/msg-reorder "feat: reordered ledger" \
    "steer-${SS}-1800000100-1" "steer-${SS}-1700000000-1"
EVAL_LABEL="$EVAL_ID reordered" expect_fail "$CHECK" /tmp/msg-reorder

# ──────────────────────────────────────────────────────────────
# Case 6 — fail: Steer-Count disagrees with Steer-Key trailer count
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_A="steer-${SS}-${EPOCH}-1"
append_row "$KEY_A" "tool-denial" "ok"
git add STEERING.md
write_msg_raw /tmp/msg-bad-count "feat: bad count" \
    "Steer-Count: 99
Steer-Types: tool-denial=99
Steer-Tiers: structural=99
Steer-Key: $KEY_A"
EVAL_LABEL="$EVAL_ID bad-count" expect_fail "$CHECK" /tmp/msg-bad-count

# ──────────────────────────────────────────────────────────────
# Case 7 — fail: Steer-Key present but summary trailers missing
# ──────────────────────────────────────────────────────────────
write_msg_raw /tmp/msg-no-summary "feat: no summary" "Steer-Key: $KEY_A"
EVAL_LABEL="$EVAL_ID missing-summary" expect_fail "$CHECK" /tmp/msg-no-summary

# ──────────────────────────────────────────────────────────────
# Case 8 — fail: Steer-Types breakdown disagrees with matched row's type
# ──────────────────────────────────────────────────────────────
write_msg_raw /tmp/msg-bad-types "feat: wrong types" \
    "Steer-Count: 1
Steer-Types: interrupt=1
Steer-Tiers: structural=1
Steer-Key: $KEY_A"
EVAL_LABEL="$EVAL_ID bad-types" expect_fail "$CHECK" /tmp/msg-bad-types

eval_done

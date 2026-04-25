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
    # write_msg <subject> [trailer-key ...]
    local file="$1"; shift
    local subject="$1"; shift
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
        for k in "$@"; do
            printf 'Steer-Key: %s\n' "$k"
        done
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
    git commit --quiet --no-verify -m "chore: reset ledger" || true
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

eval_done

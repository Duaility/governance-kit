#!/usr/bin/env bash
set -u
EVAL_ID="agent-steering-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Seed the ledger with the install-assets header so the file shape is real.
cp "$PACK_DIR/directives/$EVAL_ID/install-assets/STEERING.md" STEERING.md

# Stable ids used across cases.
SESSION_ID="abc123def456fixture"
SS="abc123def456"
EPOCH=1800000000

# Most fixtures carry an `Agent:` trailer to mirror real agent-driven repos
# where `agent-token-accounting` ships alongside this directive. The
# directive itself is independent — Cases 7/11 below exercise the contract
# without an `Agent:` trailer.
agent_block() {
    printf 'Agent: claude-code\n'
    printf 'Session: %s\n' "$SESSION_ID"
}

write_msg() {
    # write_msg <file> <subject> [count] [types-summary] [tiers-summary]
    # With no extra args, stamps `Steer-Count: 0` / `none` / `none`.
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
    # Direct trailer body for cases that test malformed summary trailers.
    local file="$1" subject="$2" body="$3"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n\n'
        agent_block
        printf '%s\n' "$body"
    } > "$file"
}

write_msg_human() {
    # write_msg_human <file> <subject> [count] [types-summary] [tiers-summary]
    # Non-agent commit (no `Agent:`/`Session:` trailers). With no extra args,
    # stamps `Steer-Count: 0` / `none` / `none` — the universal contract
    # applies regardless of whether agent-token-accounting is installed.
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
    # Non-agent commit with NO summary triple — exercises the universal
    # contract failure mode (every commit must stamp the triple).
    local file="$1" subject="$2"
    {
        printf '%s\n\n' "$subject"
        printf 'Body line.\n'
    } > "$file"
}

append_row() {
    # append_row <steer-key> <type> <reason> [commit-cell]
    # 7-col schema: steer-key | session | issue | type | tier | user-reason | commit
    local key="$1" typ="$2" reason="$3" commit_cell="${4:-feat: x}"
    printf '| %s | %s | #1 | %s | structural | %s | %s |\n' \
        "$key" "$SESSION_ID" "$typ" "$reason" "$commit_cell" >> STEERING.md
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
# Case 2 — pass: clean (row staged + summary triple agrees)
# ──────────────────────────────────────────────────────────────
KEY1="steer-${SS}-${EPOCH}-1"
append_row "$KEY1" "interrupt" "" "feat: with steering"
git add STEERING.md
write_msg /tmp/msg-pass "feat: with steering" 1 "interrupt=1" "structural=1"
EVAL_LABEL="$EVAL_ID pass-clean" expect_pass "$CHECK" /tmp/msg-pass
git commit --quiet --no-verify -m "feat: persisted clean row"

# ──────────────────────────────────────────────────────────────
# Case 3 — fail: ledger rows out of order (append-only invariant)
# ──────────────────────────────────────────────────────────────
reset_ledger
append_row "steer-${SS}-1800000100-1" "interrupt" "later epoch first"
append_row "steer-${SS}-1700000000-1" "interrupt" "earlier epoch second"
git add STEERING.md
write_msg /tmp/msg-reorder "feat: reordered ledger" 2 "interrupt=2" "structural=2"
EVAL_LABEL="$EVAL_ID reordered" expect_fail "$CHECK" /tmp/msg-reorder

# ──────────────────────────────────────────────────────────────
# Case 4 — fail: Steer-Count disagrees with newly-added row count
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_A="steer-${SS}-${EPOCH}-1"
append_row "$KEY_A" "interrupt" "ok" "feat: bad count"
git add STEERING.md
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
# universal contract when the summary triple is stamped. Demonstrates
# independence from agent-token-accounting.
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
# Case 9 — fail: ledger row uses retired `tool-denial` type
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_DEN="steer-${SS}-1800000200-1"
append_row "$KEY_DEN" "tool-denial" "should be rejected" "feat: retired type"
git add STEERING.md
write_msg /tmp/msg-retired-type "feat: retired type" 1 "tool-denial=1" "structural=1"
EVAL_LABEL="$EVAL_ID retired-tool-denial-type" expect_fail "$CHECK" /tmp/msg-retired-type

# ──────────────────────────────────────────────────────────────
# Case 10 — pass: retry-after-failed-commit-msg
# ──────────────────────────────────────────────────────────────
# Simulates the scenario from issue #66: pre-commit's first attempt appended
# a row + summary trailers, the commit-msg check downstream rejected the
# message (e.g. an over-length subject), and the user retries `git commit`.
# Under the old per-event-trailer contract the second attempt re-stamped
# zero Steer-Key trailers because the row already counted as "existing".
# Under the new summary-only contract the row is still staged, the
# commit message carries the full summary triple agreeing with that row,
# and the check passes without manual trailer stamping.
reset_ledger
KEY_RETRY="steer-${SS}-1800000300-1"
append_row "$KEY_RETRY" "correction" "redirected" "feat: retry case"
git add STEERING.md
write_msg /tmp/msg-retry "feat: retry case" 1 "correction=1" "structural=1"
EVAL_LABEL="$EVAL_ID retry-after-failed-commit-msg" expect_pass "$CHECK" /tmp/msg-retry

# ──────────────────────────────────────────────────────────────
# Case 11 — fail: commit with no `Agent:` trailer AND no summary triple.
# The universal contract requires the triple on every in-scope commit;
# the absence of agent-token-accounting trailers does not exempt it.
# ──────────────────────────────────────────────────────────────
reset_ledger
write_msg_human_bare /tmp/msg-bare "chore: bare commit"
EVAL_LABEL="$EVAL_ID bare-commit-no-triple" expect_fail "$CHECK" /tmp/msg-bare

# ──────────────────────────────────────────────────────────────
# Case 12 — pass: per-commit waiver bypasses the trailer + ledger
# cross-checks. Used for ledger-repair commits (e.g. restoring epoch
# monotonicity after a squash-merge interleaved rows from two sessions
# in the wrong order — see issue #131).
# ──────────────────────────────────────────────────────────────
reset_ledger
{
    printf 'fix(ledger): repair epoch ordering\n\n'
    printf 'Body line.\n\n'
    printf 'governance: allow-agent-steering-accounting reorder-repair after squash-merge inversion\n'
} > /tmp/msg-waiver
EVAL_LABEL="$EVAL_ID waiver-bypasses-cross-checks" expect_pass "$CHECK" /tmp/msg-waiver

# ──────────────────────────────────────────────────────────────
# Case 13 — fail: waiver token with no reason. A bare token does not
# waive — every existing kit waiver requires a non-empty reason for the
# audit trail.
# ──────────────────────────────────────────────────────────────
{
    printf 'fix(ledger): bare waiver\n\n'
    printf 'Body line.\n\n'
    printf 'governance: allow-agent-steering-accounting\n'
} > /tmp/msg-waiver-bare
EVAL_LABEL="$EVAL_ID waiver-without-reason-fails" expect_fail "$CHECK" /tmp/msg-waiver-bare

# ──────────────────────────────────────────────────────────────
# Case 14 — pass: Mode B on `main` validates HEAD's trailers when no base
# ref is available. Squash-merge produces a fresh commit on main whose
# trailers must be checked — without the HEAD fallback the squash slips
# past the trailer contract because the local commit-msg hook only runs
# pre-squash on the feature branch.
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_OK="steer-${SS}-1800000900-1"
append_row "$KEY_OK" "interrupt" "" "feat: post-squash on main"
git add STEERING.md
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
# Demonstrates that the HEAD fallback actively enforces — a malformed
# squash-merge commit does NOT slip through.
# ──────────────────────────────────────────────────────────────
reset_ledger
{
    printf 'chore: bad squash-merge commit\n\n'
    printf 'Body without summary trailers.\n'
} > /tmp/msg-mode-b-fail
git commit --allow-empty --quiet --no-verify -F /tmp/msg-mode-b-fail
EVAL_LABEL="$EVAL_ID mode-b-on-main-missing-triple" expect_fail "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 16 — pass: squash-merge body with two stacked trailer triples.
# GitHub squash-merge concatenates each sub-commit's body into the
# resulting commit message, so the summary triple appears N times. The
# parser must sum across occurrences so the trailer total agrees with the
# cumulative STEERING.md diff. Issue #136.
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_S1="steer-${SS}-1800001000-1"
KEY_S2="steer-${SS}-1800001100-1"
append_row "$KEY_S1" "interrupt" "" "feat: squashed pair"
append_row "$KEY_S2" "correction" "" "feat: squashed pair"
git add STEERING.md
{
    printf 'feat: squashed pair\n\n'
    printf 'Body line.\n\n'
    agent_block
    # Sub-commit 1 trailer block — added KEY_S1.
    printf 'Steer-Count: 1\n'
    printf 'Steer-Types: interrupt=1\n'
    printf 'Steer-Tiers: structural=1\n\n'
    # Sub-commit 2 trailer block — added KEY_S2.
    printf 'Steer-Count: 1\n'
    printf 'Steer-Types: correction=1\n'
    printf 'Steer-Tiers: structural=1\n'
} > /tmp/msg-squash-aggregate
git commit --quiet --no-verify -F /tmp/msg-squash-aggregate
EVAL_LABEL="$EVAL_ID squash-merge-sums-stacked-triples" expect_pass "$CHECK"

# ──────────────────────────────────────────────────────────────
# Case 17 — pass: squashed body where the trailing sub-commit's triple
# is the all-zero default. Under the old last-wins parse this would
# incorrectly drop to `Steer-Count: 0` and disagree with the row added
# by the earlier sub-commit. Mirrors run 25950635716's failure shape.
# ──────────────────────────────────────────────────────────────
reset_ledger
KEY_S3="steer-${SS}-1800001200-1"
KEY_S4="steer-${SS}-1800001300-1"
append_row "$KEY_S3" "interrupt" "" "feat: squashed with trailing zero"
append_row "$KEY_S4" "interrupt" "" "feat: squashed with trailing zero"
git add STEERING.md
{
    printf 'feat: squashed with trailing zero\n\n'
    printf 'Body line.\n\n'
    agent_block
    # First sub-commit added two rows.
    printf 'Steer-Count: 2\n'
    printf 'Steer-Types: interrupt=2\n'
    printf 'Steer-Tiers: structural=2\n\n'
    # Trailing sub-commit was a no-op for STEERING.md.
    printf 'Steer-Count: 0\n'
    printf 'Steer-Types: none\n'
    printf 'Steer-Tiers: none\n'
} > /tmp/msg-squash-trailing-zero
git commit --quiet --no-verify -F /tmp/msg-squash-trailing-zero
EVAL_LABEL="$EVAL_ID squash-merge-trailing-zero-block" expect_pass "$CHECK"

eval_done

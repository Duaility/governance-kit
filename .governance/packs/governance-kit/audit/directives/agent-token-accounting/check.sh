#!/usr/bin/env bash
# Directive: every agent-authored commit's token cost is recorded in the
# issue's receipt (`receipts/issue-<N>.md`, under `## Accounting` → `### Costs`)
# and the receipt's recorded cumulative never silently falls behind the
# transcript. This repo is agent-driven only — an unaccounted commit is a bug.
#
# Issue #293 retired the per-commit token trailers
# (Agent/Issue/Session/Token-*/Cost-Key/Cost-USD). They were a denormalised
# copy of the receipt cost row stamped onto the commit, kept honest by a
# bidirectional cross-check whose only consumer was the cross-check itself. The
# receipt is the durable, doc-integrity-frozen ledger; completeness is now
# proven by reading the transcript directly instead of a stamped copy:
#
#   Endpoint reconciliation (Mode A, commit time): when an agent runtime is
#   detected, re-derive the session's cumulative token counters from the
#   transcript and assert the receipt's recorded `cum-*` for that session
#   equals it. Because cost rows store *absolute* coordinates, a ledger that
#   lags the transcript is exactly the signature of a commit whose cost row was
#   never written — the failure mode the mandatory `Agent:` trailer used to
#   catch. The pre-commit hook writes the row (and advances the per-session
#   checkpoint) just before this runs, so a clean commit reconciles by
#   construction; a `--no-verify` / hook-skipped commit lags and fails here.
#
# Receipt Costs sub-table format — v4, one row per agent-authored commit:
#   | cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
# Legacy v3 (12 cols) / v2 / v1 rows still parse and validate to their rules;
# they carry no `cum-*` and are excluded from reconciliation / monotonicity.
#
# Modes:
#   Mode A — commit-msg hook:  bash check.sh <path-to-msg-file>
#       Runs the repo-wide receipt-shape check (below) then, when a runtime is
#       detected, the endpoint reconciliation for the active session. Skips
#       revert commits. The endpoint check is *commit-time only* — running it
#       off the commit path (e.g. a mid-session `run.sh`) would false-fail
#       because the transcript legitimately leads the not-yet-committed work.
#   Mode B — CI / run.sh:      bash check.sh
#       Receipt-shape check only: every receipt's Costs sub-table is well-formed
#       (shape + global cost-key uniqueness + cumulative reconciliation /
#       monotonicity). Per-commit completeness is a write-time property — on the
#       trunk the receipt *is* the record, and its internal consistency is what
#       CI guards.
#
# Ledger parsing / append / queries live in sibling lib/ledger.py; receipt
# validation in lib/validate.py; cumulative reconciliation + checkpoint in
# lib/reconcile.py; pricing in lib/rates.py; runtime detection + transcript
# cumulative in lib/runtime.sh (shared with hooks/pre-commit.sh).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "agent-token-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
RECEIPTS_DIR="$ROOT/receipts"
LIB="$HERE/lib"

if [[ ! -f "$LIB/ledger.py" || ! -f "$LIB/runtime.sh" ]]; then
    violation "directive folder is missing lib/ledger.py or lib/runtime.sh — cannot validate"
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Receipt-accounting integrity check (independent of any commit). Runs in both
# modes so repo-wide shape problems (bad row shape, duplicate cost-keys,
# double-counted deltas, non-monotonic cumulatives) are reported everywhere.
# ──────────────────────────────────────────────────────────────
if [[ -d "$RECEIPTS_DIR" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(python3 "$LIB/ledger.py" validate-dir "$RECEIPTS_DIR" || true)
fi

# Returns 0 if the commit message carries a valid escape-hatch waiver.
# `governance: allow-agent-token-accounting <reason>` — reason required. Covers
# the rare legitimate out-of-hook commit and unrecoverable-predecessor repairs.
msg_has_waiver() {
    printf '%s\n' "$1" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-agent-token-accounting[[:space:]]+.+'
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook: endpoint reconciliation for the active session.
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        directive_end
    fi
    # Skip revert commits — git's auto-format starts with `Revert "..."`.
    pending_subject=$(grep -vE '^[[:space:]]*($|#)' "$msg_file" | head -n1)
    if [[ "$pending_subject" == Revert\ \"* ]]; then
        directive_end
    fi
    msg="$(cat "$msg_file")"
    if msg_has_waiver "$msg"; then
        directive_end
    fi

    # shellcheck disable=SC1090
    source "$LIB/runtime.sh"
    resolve_runtime_cumulative
    rc=$?
    if [[ $rc -eq 1 ]]; then
        # No agent runtime detected — a human / manual-git commit. Nothing to
        # reconcile (no transcript, no cost to account). Pass.
        directive_end
    fi
    if [[ $rc -eq 2 ]]; then
        violation "pending commit — agent runtime '$RUNTIME' detected but its transcript/cumulative counters were unreadable; the pre-commit cost row could not be verified (set CLAUDE_TRANSCRIPT_PATH, or use a 'governance: allow-agent-token-accounting <reason>' waiver)"
        directive_end
    fi

    # rc == 0: compare the receipt's recorded cumulative for this session
    # against the transcript's live cumulative. Equality holds by construction
    # once the pre-commit hook has written this commit's row.
    read -r R_IN R_CC R_CR R_OUT < <(python3 "$LIB/ledger.py" session-cum "$RECEIPTS_DIR" "$SESSION_ID")
    if [[ "$R_IN" != "$CUM_INPUT" || "$R_CC" != "$CUM_CACHE_CREATE" \
       || "$R_CR" != "$CUM_CACHE_READ" || "$R_OUT" != "$CUM_OUTPUT" ]]; then
        violation "pending commit — token ledger for session '${SESSION_ID:0:16}…' records cumulative (input=$R_IN cache_create=$R_CC cache_read=$R_CR output=$R_OUT) but the transcript is at (input=$CUM_INPUT cache_create=$CUM_CACHE_CREATE cache_read=$CUM_CACHE_READ output=$CUM_OUTPUT) — this commit's cost row was not written to its receipt. Commit through the runtime-aware pre-commit hook (a plain \`git commit\`, not --no-verify / SKIP_GOVERNANCE), or add a 'governance: allow-agent-token-accounting <reason>' waiver."
    fi
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh: receipt-shape integrity only (ran above).
# ──────────────────────────────────────────────────────────────
directive_end

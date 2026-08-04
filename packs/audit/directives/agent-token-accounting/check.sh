#!/usr/bin/env bash
# Directive: every agent-authored commit's token cost is recorded in the
# issue's receipt (`receipts/issue-<N>.md`, under `## Accounting` → `### Costs`)
# and the receipt's recorded cumulative never silently falls behind what the
# runtime reported. This repo is agent-driven only — an unaccounted commit is a
# bug.
#
# Issue #293 retired the per-commit token trailers; completeness is proven by
# freezing the writer's sampled endpoint instead of stamping a copy onto the
# commit:
#
#   Endpoint reconciliation (Mode A, commit time): when an agent runtime is
#   detected, read the frozen endpoint keyed by the post-pre-commit staged tree
#   and assert the staged receipt row for that endpoint's cost-key carries the
#   same session cumulative coordinate. The pre-commit hook writes the row and
#   then freezes the exact coordinate it sampled, so later transcript movement
#   belongs to a later row instead of invalidating this commit.
#
# Issue #355 took python off this path entirely and made the harness the only
# source of dollars. Receipt Costs sub-table — v5, one row per agent-authored
# commit:
#   | cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |
# `source` names the runtime adapter that produced the row; `cost-usd` is the
# harness-reported figure verbatim, or EMPTY when the harness reported none —
# the kit no longer owns a rate card, so it never prices and never blocks a
# commit over an unpriced model. Legacy v4 (16 cols) / v3 (12) rows still parse
# and validate to their own rules.
#
# Modes:
#   Mode A — commit-msg hook:  bash check.sh <path-to-msg-file>
#       Runs the repo-wide receipt-shape check (below) then, when a runtime is
#       detected, the endpoint reconciliation for the staged tree. Skips
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
# Markdown/table plumbing lives in sibling lib/receipt.sh; the row schema and
# append in lib/costs.sh; validation in lib/validate.sh; frozen endpoint +
# session checkpoint in lib/endpoint.sh; runtime detection in lib/runtime.sh.
# All bash + POSIX awk.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "agent-token-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
RECEIPTS_DIR="$ROOT/receipts"
LIB="$HERE/lib"

for _f in receipt.sh costs.sh validate.sh endpoint.sh runtime.sh; do
    if [[ ! -f "$LIB/$_f" ]]; then
        violation "directive folder is missing lib/$_f — cannot validate"
        directive_end
    fi
done
# shellcheck disable=SC1090
source "$LIB/receipt.sh"
# shellcheck disable=SC1090
source "$LIB/costs.sh"
# shellcheck disable=SC1090
source "$LIB/validate.sh"
# shellcheck disable=SC1090
source "$LIB/endpoint.sh"

# ──────────────────────────────────────────────────────────────
# Receipt-accounting integrity check (independent of any commit). Runs in both
# modes so repo-wide shape problems (bad row shape, duplicate cost-keys,
# double-counted deltas, non-monotonic cumulatives) are reported everywhere.
# ──────────────────────────────────────────────────────────────
if [[ -d "$RECEIPTS_DIR" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(costs_validate_dir "$RECEIPTS_DIR" || true)
fi

# Returns 0 if the commit message carries a valid escape-hatch waiver.
# `governance: allow-agent-token-accounting <reason>` — reason required. Covers
# the rare legitimate out-of-hook commit and unrecoverable-predecessor repairs.
msg_has_waiver() {
    printf '%s\n' "$1" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-agent-token-accounting[[:space:]]+.+'
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook: endpoint reconciliation for the staged tree.
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
        violation "pending commit — agent runtime '$RUNTIME' detected but its session usage was unreadable; the pre-commit cost row could not be verified (set CLAUDE_TRANSCRIPT_PATH, or use a 'governance: allow-agent-token-accounting <reason>' waiver)"
        directive_end
    fi

    # rc == 0: an agent runtime is active, so pre-commit must have written a
    # tree-keyed endpoint. Do not compare to the live CUM_* values here: the
    # transcript may have legitimately advanced after pre-commit sampled it.
    TREE_ID="$(git write-tree)"
    ENDPOINT="$(git rev-parse --git-path "governance-token-endpoints/${TREE_ID}.endpoint")"
    if [[ ! -f "$ENDPOINT" ]]; then
        violation "pending commit — agent runtime '$RUNTIME' detected but no frozen token endpoint exists for staged tree $TREE_ID; the pre-commit cost row was not verified. Commit through the runtime-aware pre-commit hook (a plain \`git commit\`, not --no-verify / SKIP_GOVERNANCE), or add a 'governance: allow-agent-token-accounting <reason>' waiver."
        directive_end
    fi
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(endpoint_verify "$ENDPOINT" "$ROOT" || true)
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh: receipt-shape integrity only (ran above).
# ──────────────────────────────────────────────────────────────
directive_end

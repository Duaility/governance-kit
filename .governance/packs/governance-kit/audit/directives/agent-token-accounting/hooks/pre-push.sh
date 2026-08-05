#!/usr/bin/env bash
# Agent token accounting — the resolver's last local chance (issue #355).
#
# Same resolve sweep as hooks/post-commit.sh, run once more before the work
# leaves the machine: this is the last moment the harness's own surfaces are
# reachable, since nothing in CI can measure a session that ran on a laptop.
#
# Best-effort and unconditionally successful — a push is NEVER blocked for a
# measurement reason. When a receipt row is now behind its sidecar, the hook
# says so in one line and moves on; the number folds into the row on the next
# commit, which is exactly the self-healing convergence the v6 row exists for.
#
# Receives git's pre-push argv (`<remote-name> <remote-url>`) and the ref list
# on stdin. Neither is used — the sweep is per-session, not per-ref.

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 0
RULE_DIR="$(cd "$HERE/.." && pwd)" || exit 0
LIB="$RULE_DIR/lib"

STALE=""
{
    ROOT="$(git rev-parse --show-toplevel)" || exit 0
    GOV_LIB="$RULE_DIR/../../../../../lib.sh"
    if [[ -f "$GOV_LIB" ]]; then
        # shellcheck disable=SC1090
        source "$GOV_LIB"
    fi
    # shellcheck disable=SC1090
    source "$LIB/receipt.sh"
    # shellcheck disable=SC1090
    source "$LIB/costs.sh"
    # shellcheck disable=SC1090
    source "$LIB/runtime.sh"
    # shellcheck disable=SC1090
    source "$LIB/resolve.sh"

    resolve_sweep

    # Which receipt rows the sweep just left behind. Purely informational.
    for receipt in "$ROOT"/receipts/issue-*.md; do
        [[ -f "$receipt" ]] || continue
        keys="$(costs_session_keys "$receipt")"
        while IFS=$'\t' read -r harness session; do
            [[ -z "$harness" ]] && continue
            side="$(sidecar_file "$harness" "$session")" || continue
            snap="$(costs_fold_snapshot "$side")"
            [[ -z "$snap" ]] && continue
            [[ "$snap" == "$(costs_row_snapshot "$receipt" "$harness" "$session")" ]] && continue
            STALE="$STALE $harness/$session"
        done <<< "$keys"
    done
} 2>/dev/null || true

if [[ -n "${STALE// /}" ]]; then
    printf 'agent-accounting: newer session totals available for%s — they fold into the receipt on the next commit.\n' \
        "$STALE" >&2
fi

exit 0

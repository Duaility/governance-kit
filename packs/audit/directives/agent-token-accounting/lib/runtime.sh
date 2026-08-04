#!/usr/bin/env bash
# Shared runtime detection + native-cost resolution for agent-token-accounting.
# Sourced by hooks/pre-commit.sh (the write path) and check.sh (runtime
# detection before commit-time endpoint reconciliation).
#
# The writer reads the runtime's own reported usage and freezes that coordinate
# under a staged-tree endpoint. The checker calls this only to decide whether an
# agent runtime is active; it then verifies the staged receipt row against the
# frozen endpoint rather than a moving live transcript.
#
# resolve_runtime_cumulative
#   Detects the active agent runtime from the environment and asks its adapter
#   for the session's cumulative counters. On success sets the globals:
#     RUNTIME SESSION_ID CUM_INPUT CUM_CACHE_CREATE CUM_CACHE_READ CUM_OUTPUT
#     MODEL COST_USD
#   COST_USD is the harness-reported dollar figure VERBATIM, or the literal `-`
#   when the harness reports none. The kit never prices (issue #355) — a `-`
#   becomes an empty cost cell, never an estimate, and never blocks a commit.
#   Return codes:
#     0 — runtime detected, usage resolved
#     1 — no agent runtime detected (a human / manual-git commit; caller no-ops)
#     2 — runtime detected but its adapter could not read the session
#
# Detection mirrors the historical pre-commit contract:
#   AGENT_NAME set            → manual   (explicit AGENT_SESSION_ID / AGENT_CUM_*
#                                         / AGENT_MODEL / AGENT_COST_USD)
#   CLAUDECODE=1              → claude-code
#   CODEX_THREAD_ID or CODEX_TRANSCRIPT_PATH set → codex
#
# Adapters are KIT-level, not pack-level (issue #355): one registry at
# `.governance/runtimes/<runtime>.sh`, shared by this directive's `cost` verb and
# lib.sh's `judge` verb, because "which harness am I talking to" is one fact
# about the repo, not a per-directive one. Each adapter answers `cost` with
#   <session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>
# Stdlib bash; Bash 3.2 compatible (macOS /bin/bash). No python.

# _runtime_adapter_dir
#   Where the adapter registry lives, in resolution order:
#     1. GOVERNANCE_RUNTIMES_DIR   — explicit override (tests, unusual layouts)
#     2. $GOVERNANCE_ROOT/runtimes — when the runner exports a governance root
#     3. <repo>/.governance/runtimes — the installed location
#     4. the kit source tree       — running this pack straight out of the
#                                    governance-kit checkout, uninstalled
#   Prints the directory, or nothing (return 1) when no registry is reachable.
_runtime_adapter_dir() {
    local here root cand
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    for cand in \
        "${GOVERNANCE_RUNTIMES_DIR:-}" \
        "${GOVERNANCE_ROOT:+$GOVERNANCE_ROOT/runtimes}" \
        "${root:+$root/.governance/runtimes}" \
        "$here/../../../../../kit/assets/dot-governance/runtimes"
    do
        [[ -n "$cand" && -d "$cand" ]] || continue
        (cd "$cand" && pwd) && return 0
    done
    return 1
}

resolve_runtime_cumulative() {
    local runtimes out
    runtimes="$(_runtime_adapter_dir)" || runtimes=""

    RUNTIME=""
    SESSION_ID=""
    CUM_INPUT=0
    CUM_CACHE_CREATE=0
    CUM_CACHE_READ=0
    CUM_OUTPUT=0
    MODEL=""
    COST_USD="-"

    if [[ -n "${AGENT_NAME:-}" ]]; then
        RUNTIME="manual"
    elif [[ "${CLAUDECODE:-}" == "1" ]]; then
        RUNTIME="claude-code"
    elif [[ -n "${CODEX_THREAD_ID:-}" || -n "${CODEX_TRANSCRIPT_PATH:-}" ]]; then
        RUNTIME="codex"
    fi

    [[ -z "$RUNTIME" ]] && return 1

    local adapter=""
    [[ -n "$runtimes" && -f "$runtimes/$RUNTIME.sh" ]] && adapter="$runtimes/$RUNTIME.sh"

    if [[ -n "$adapter" ]]; then
        # `bash <adapter>` rather than executing it directly: the registry is a
        # copied tree, and a lost exec bit must not silently disable accounting.
        out="$(bash "$adapter" cost)" || return 2
        read -r SESSION_ID CUM_INPUT CUM_CACHE_CREATE CUM_CACHE_READ \
                CUM_OUTPUT MODEL COST_USD <<<"$out"
    elif [[ "$RUNTIME" == "manual" ]]; then
        # No registry on disk (a consumed tree from before the adapters were
        # kit-level): the manual seam is pure environment, so read it inline
        # rather than losing the escape hatch. `manual.sh cost` is byte-for-byte
        # this logic — the two are pinned together by the directive's evals.
        [[ -n "${AGENT_SESSION_ID:-}" && -n "${AGENT_CUM_INPUT:-}" && -n "${AGENT_CUM_OUTPUT:-}" ]] || return 2
        SESSION_ID="$AGENT_SESSION_ID"
        CUM_INPUT="$AGENT_CUM_INPUT"
        CUM_CACHE_CREATE="${AGENT_CUM_CACHE_CREATE:-0}"
        CUM_CACHE_READ="${AGENT_CUM_CACHE_READ:-0}"
        CUM_OUTPUT="$AGENT_CUM_OUTPUT"
        MODEL="${AGENT_MODEL:-unknown}"
        COST_USD="${AGENT_COST_USD:--}"
    else
        return 2
    fi

    MODEL="${MODEL:-unknown}"
    COST_USD="${COST_USD:--}"

    # Cumulative counters must be non-negative integers.
    local var val
    for var in CUM_INPUT CUM_CACHE_CREATE CUM_CACHE_READ CUM_OUTPUT; do
        val="${!var}"
        [[ "$val" =~ ^[0-9]+$ ]] || return 2
    done
    # A reported cost is passed through verbatim; anything that is not a plain
    # decimal degrades to `-` (an unreported cost), never to a guess.
    [[ "$COST_USD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || COST_USD="-"
    return 0
}

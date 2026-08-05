#!/usr/bin/env bash
# Identity detection + kit-owned artifact locations for agent-token-accounting.
#
# The split this file exists to enforce (issue #355): **identity at commit,
# measurement at rest.** A pre-commit hook is the worst possible measurement
# point — synchronous, blocking, unretryable, and racing a session whose cost
# is not even final yet. But *identity* is cheap and only knowable there: the
# harness announces itself in the environment. So the commit path resolves WHO
# is committing and nothing else. It never opens a harness file, never parses a
# transcript, never does arithmetic on tokens.
#
# The second half of the rule is just as hard: **the kit never guesses
# identity.** Every "newest file wins" / mtime heuristic is gone. No identity
# means no session, which means no numbers — the row says `-` and `unresolved`
# and a later resolve sweep fills it in. A guessed session id is worse than a
# blank one: it silently bills one agent's spend to another.
#
# detect_runtime_identity
#   Sets the globals RUNTIME, SESSION_ID and DECLARED from the environment,
#   falling back to the kit-owned identity file (below) only when no env signal
#   matched. SESSION_ID is the literal `-` when the harness is present but does
#   not name its session. DECLARED is a harness-handed absolute path, or empty.
#   Return codes:
#     0 — an agent runtime is present (RUNTIME set)
#     1 — no agent runtime (a human / plain-git commit; every caller no-ops)
#   There is no "unreadable" return code any more: reading a harness surface is
#   not this file's job, so it has nothing to fail at.
#
# Kit-owned artifacts, both under the per-worktree git dir (a worktree is the
# natural session-disambiguation boundary — two worktrees never collide):
#
#   <git-dir>/governance/session-identity
#       Flat `key=value` written by wired harness hooks (SessionStart and
#       friends) or by an adapter's `emit` verb: harness=, session=,
#       declared=, epoch=. Last writer wins. Optional — env detection works
#       without it, and it is how a harness that exports nothing (grok) still
#       gets identified. Trusted only while it is younger than
#       COSTS_IDENTITY_MAX_AGE_HOURS.
#
#   <git-dir>/governance/costs/<harness>-<session>
#       The snapshot sidecar: APPEND-only, one snapshot per line,
#       `v1 <epoch> <input> <cache_create> <cache_read> <output> <model>
#        <cost_usd|-> <source>`. Written off the commit path by adapter `emit`
#       (live push) and adapter `resolve` (pull); read by the pre-commit stamp
#       step. Numbers are the harness's own session-cumulatives, never deltas.
#
# Stdlib bash, Bash 3.2 compatible (macOS /bin/bash). No python anywhere.

# _runtime_adapter_dir
#   Where the kit-level adapter registry lives, in resolution order:
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
        [ -n "$cand" ] && [ -d "$cand" ] || continue
        (cd "$cand" && pwd) && return 0
    done
    return 1
}

# adapter_for <runtime>  → the adapter path, or nothing (return 1).
#   Adapters are invoked as `bash <adapter> <verb>`, never executed directly:
#   the registry is a copied tree and a lost exec bit must not silently
#   disable accounting.
adapter_for() {
    local dir
    dir="$(_runtime_adapter_dir)" || return 1
    [ -f "$dir/$1.sh" ] || return 1
    printf '%s\n' "$dir/$1.sh"
}

# adapter_names  → every registered adapter name, one per line.
adapter_names() {
    local dir f
    dir="$(_runtime_adapter_dir)" || return 0
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        f="$(basename "$f")"
        printf '%s\n' "${f%.sh}"
    done
}

# _gov_git_dir  → the absolute per-worktree git dir.
_gov_git_dir() {
    local d
    d="$(git rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$d" ] && {
        printf '%s\n' "$d"
        return 0
    }
    d="$(git rev-parse --git-dir 2>/dev/null)" || return 1
    case "$d" in
        /*) printf '%s\n' "$d" ;;
        *)  printf '%s/%s\n' "$(pwd)" "$d" ;;
    esac
}

# identity_file  → path to the kit-owned identity file (may not exist).
identity_file() {
    local d
    d="$(_gov_git_dir)" || return 1
    printf '%s/governance/session-identity\n' "$d"
}

# identity_get <key>  → the value of a flat `key=value` row, or empty.
identity_get() {
    local f
    f="$(identity_file)" || return 0
    [ -f "$f" ] || return 0
    IDENTITY_KEY="$1" awk '
BEGIN { k = ENVIRON["IDENTITY_KEY"] }
index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
' "$f"
}

# _identity_max_age_hours
#   The identity-file trust window. Resolved through the standard conf ladder
#   (env GOVERNANCE_COSTS_IDENTITY_MAX_AGE_HOURS > user overlay > the
#   pack-owned defaults.conf row) when lib.sh is in scope; check.sh and both
#   hook helpers source it, so it always is in a real install. An
#   unresolvable / non-numeric window returns 1 and the identity-file fallback
#   is skipped entirely — fail-safe in the direction of "no identity", never
#   toward a guessed one.
_identity_max_age_hours() {
    local defaults value=""
    defaults="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/defaults.conf"
    if declare -F conf_get >/dev/null 2>&1; then
        value="$(conf_get agent-token-accounting COSTS_IDENTITY_MAX_AGE_HOURS "$defaults")" || value=""
    else
        value="$(grep -E '^COSTS_IDENTITY_MAX_AGE_HOURS=' "$defaults" 2>/dev/null | head -n 1)"
        value="${value#*=}"
    fi
    case "$value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$value"
}

# _identity_fresh  → 0 when the identity file exists and is inside the trust
#   window. A file with no parseable `epoch=` is never fresh.
_identity_fresh() {
    local f epoch max now
    f="$(identity_file)" || return 1
    [ -f "$f" ] || return 1
    epoch="$(identity_get epoch)"
    case "$epoch" in
        ''|*[!0-9]*) return 1 ;;
    esac
    max="$(_identity_max_age_hours)" || return 1
    now="$(date +%s)"
    [ $(( now - epoch )) -lt $(( max * 3600 )) ]
}

# _sidecar_safe <text>  → a filesystem-safe path component.
_sidecar_safe() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# sidecar_dir  → the kit-owned snapshot sidecar directory (may not exist).
sidecar_dir() {
    local d
    d="$(_gov_git_dir)" || return 1
    printf '%s/governance/costs\n' "$d"
}

# sidecar_file <harness> <session>  → the session's sidecar path.
sidecar_file() {
    local d
    d="$(sidecar_dir)" || return 1
    printf '%s/%s-%s\n' "$d" "$(_sidecar_safe "$1")" "$(_sidecar_safe "$2")"
}

# sidecar_last <harness> <session>  → the sidecar's last raw snapshot line.
#   The chronological tail. The *authoritative* snapshot is the one
#   `costs_fold_snapshot` (lib/costs.sh) picks, which prefers a full-token
#   `session-file` / `server` reading over a same-or-newer `harness-feed` push.
sidecar_last() {
    local f
    f="$(sidecar_file "$1" "$2")" || return 0
    [ -f "$f" ] || return 0
    tail -n 1 "$f"
}

# detect_runtime_identity  → sets RUNTIME / SESSION_ID / DECLARED. See header.
detect_runtime_identity() {
    RUNTIME=""
    SESSION_ID="-"
    DECLARED=""

    local id_harness="" id_session="" id_declared=""
    if _identity_fresh; then
        id_harness="$(identity_get harness)"
        id_session="$(identity_get session)"
        id_declared="$(identity_get declared)"
    fi

    if [ -n "${AGENT_NAME:-}" ]; then
        RUNTIME="manual"
        SESSION_ID="${AGENT_SESSION_ID:-manual}"
    elif [ "${CLAUDECODE:-}" = "1" ]; then
        RUNTIME="claude-code"
        SESSION_ID="${CLAUDE_CODE_SESSION_ID:--}"
        DECLARED="${CLAUDE_TRANSCRIPT_PATH:-}"
    elif [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_TRANSCRIPT_PATH:-}" ]; then
        RUNTIME="codex"
        SESSION_ID="${CODEX_THREAD_ID:--}"
        DECLARED="${CODEX_TRANSCRIPT_PATH:-}"
    elif [ "${PI_CODING_AGENT:-}" = "true" ] || [ -n "${PI_SESSION_ID:-}" ]; then
        RUNTIME="pi"
        SESSION_ID="${PI_SESSION_ID:--}"
        DECLARED="${PI_SESSION_FILE:-}"
    elif [ "${CURSOR_AGENT:-}" = "1" ]; then
        RUNTIME="cursor-agent"
    elif [ "${OPENCODE:-}" = "1" ] || [ -n "${OPENCODE_SERVER:-}" ]; then
        RUNTIME="opencode"
        SESSION_ID="${OPENCODE_SESSION_ID:--}"
    elif [ -n "$id_harness" ]; then
        # No env signal at all, but a wired harness hook left a fresh identity
        # file. This is the seam that identifies a harness which exports
        # nothing to its child processes.
        RUNTIME="$id_harness"
        SESSION_ID="${id_session:--}"
        DECLARED="$id_declared"
    fi

    [ -n "$RUNTIME" ] || return 1

    # Env identity beats the identity file — except that the file may fill a
    # session (or a declared path) the environment left blank, and only when it
    # names the same harness.
    if [ "$id_harness" = "$RUNTIME" ]; then
        if [ "$SESSION_ID" = "-" ] && [ -n "$id_session" ]; then
            SESSION_ID="$id_session"
        fi
        if [ -z "$DECLARED" ] && [ -n "$id_declared" ]; then
            DECLARED="$id_declared"
        fi
    fi
    [ -n "$SESSION_ID" ] || SESSION_ID="-"
    return 0
}

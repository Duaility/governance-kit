#!/usr/bin/env bash
# governance-kit:managed kit-version=0.13.0
# Cursor Agent runtime adapter — one file per harness, two verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <session-id> [<declared-path>] — ALWAYS exits 2. Cursor exposes no
#     documented per-session usage surface (no session-file convention, no
#     local server, nothing this adapter is allowed to guess at) — the
#     `cost-in-json` usage payload Cursor's own CLI issue tracker has floated
#     is upstream-pending and unshipped as of this writing. Rather than reach
#     for an undocumented file or heuristic, this adapter reports honestly:
#     the row stays `-`/unresolved until Cursor ships something documented to
#     read. This is intentional, not a stub to fill in later without a source.
#
#   emit — Cursor's hooks.json `afterFileEdit`/`stop`-style hook payloads carry
#     a `conversation_id` field; this adapter treats that as the session id
#     and does IDENTITY ONLY — no sidecar snapshot, because (per `resolve`
#     above) there is nothing to measure yet, and a zero-valued snapshot would
#     just be noise with no `resolve` ever able to supersede it. Refreshes the
#     commit-path identity file when a `conversation_id` is present and the
#     payload's cwd (or $PWD) is inside a git working tree; otherwise silently
#     exits 0.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# ALWAYS for `resolve` (see above). `emit` never exits 2. Exit 2 is never fatal
# to the caller: an unattributable session is a row the ledger simply does not
# carry.
#
# Environment overrides:
#

set -u

VERB="${1:-}"

do_resolve() {
    # Drain any piped stdin so a caller that reused a redirection never SIGPIPEs.
    cat >/dev/null 2>&1 || true
    return 2
}

parse_hook() {
    awk '
function jstr(line, key,   p, rest, e) {
    p = index(line, "\"" key "\":\"")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "\"")
    if (e == 0) { return "" }
    return substr(rest, 1, e - 1)
}
{ buf = buf $0 "\n" }
END {
    sid = jstr(buf, "conversation_id")
    cwd = jstr(buf, "cwd")
    printf "%s\t%s\n", sid, cwd
}
'
}

do_emit() {
    local payload
    payload="$(cat)"
    [[ -n "$payload" ]] || return 0

    local parsed session cwd
    parsed="$(printf '%s\n' "$payload" | parse_hook)"
    IFS=$'\t' read -r session cwd <<EOF_PARSED
$parsed
EOF_PARSED
    [[ -n "$session" ]] || return 0

    [[ -n "$cwd" ]] || cwd="$PWD"
    local gitd
    gitd="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -n "$gitd" ]] || return 0

    mkdir -p "$gitd/governance" 2>/dev/null || return 0
    {
        printf 'harness=cursor-agent\n'
        printf 'session=%s\n' "$session"
        printf 'declared=\n'
        printf 'epoch=%s\n' "$(date +%s)"
    } > "$gitd/governance/session-identity"
    return 0
}

case "$VERB" in
    resolve)
        do_resolve
        exit $?
        ;;
    emit)
        do_emit
        exit $?
        ;;
    "")
        printf 'cursor-agent adapter: usage: cursor-agent.sh {resolve <session> [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'cursor-agent adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

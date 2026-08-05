#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Manual runtime adapter — the environment seam, as a first-class adapter
# (issue #355 v2: identity at commit, measurement at rest). Same two verbs
# as every other adapter; the difference is that the "harness" it reads is a
# set of environment variables the caller sets.
#
# It is the escape hatch for a runtime the kit ships no adapter for: export what
# your harness reports and the accounting lane works unchanged. (It used to be
# the judge seam too; judging left the adapters entirely in issue #355 — a
# directive names its judge COMMAND, and the eval seam is now a stub command on
# PATH, which needs no adapter at all.)
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve [<session-id>] [<declared-path>] — env passthrough, one line to
#     stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> manual
#     Requires AGENT_CUM_INPUT, AGENT_CUM_OUTPUT; optional
#     AGENT_CUM_CACHE_CREATE, AGENT_CUM_CACHE_READ (0), AGENT_MODEL (`unknown`),
#     AGENT_COST_USD (`-`). <session-id>/<declared-path> are accepted for
#     interface parity with every other adapter but unused: there is no file
#     to pin — the "declared" measurement IS the environment. Like every
#     adapter it reports, never prices.
#
#   emit — identity-only: if AGENT_SESSION_ID is set and the caller is inside
#     a git working tree ($PWD, since a manual harness has no payload to read
#     a cwd from), refreshes the commit-path identity file. No session id →
#     silently exits 0 (nothing to attribute).
#
# Exit codes: 0 ok · 2 the seam is not configured (the caller degrades).
# `emit` never exits 2 — see above.

set -u

VERB="${1:-}"

do_resolve() {
    [[ -n "${AGENT_CUM_INPUT:-}" && -n "${AGENT_CUM_OUTPUT:-}" ]] || return 2
    printf '%s %s %s %s %s %s manual\n' \
        "$AGENT_CUM_INPUT" \
        "${AGENT_CUM_CACHE_CREATE:-0}" \
        "${AGENT_CUM_CACHE_READ:-0}" \
        "$AGENT_CUM_OUTPUT" \
        "${AGENT_MODEL:-unknown}" \
        "${AGENT_COST_USD:--}"
    return 0
}

do_emit() {
    [[ -n "${AGENT_SESSION_ID:-}" ]] || return 0
    local gitd
    gitd="$(git -C "$PWD" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -n "$gitd" ]] || return 0
    mkdir -p "$gitd/governance" 2>/dev/null || return 0
    {
        printf 'harness=manual\n'
        printf 'session=%s\n' "$AGENT_SESSION_ID"
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
        printf 'manual adapter: usage: manual.sh {resolve [<session>] [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'manual adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

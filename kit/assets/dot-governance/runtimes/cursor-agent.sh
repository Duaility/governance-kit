#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Cursor Agent runtime adapter — one file per harness, three verbs
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
#   judge [<tier>] [<model>] — read a fully-built adjudication prompt on stdin,
#     run the `cursor-agent` CLI non-interactively, and print exactly:
#         VERDICT: PASS            (or VERDICT: REFUTED)
#         REASON: <text>           (zero or more lines)
#     <tier> is the capability tier (low | medium | high; empty → low) and picks
#     this adapter's own default model; <model> overrides it outright. Uses
#     cursor-agent's documented `-p` (print, non-interactive) mode.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# ALWAYS for `resolve` (see above), or a missing CLI / transport failure /
# unparseable answer for `judge`. `emit` never exits 2. Exit 2 is never fatal
# to the caller: the commit lane degrades to the harness (sub-agent) path
# rather than blocking on a broken side channel.
#
# Environment overrides:
#   AGENT_JUDGE_TIMEOUT seconds to allow the judge CLI (default 120), when a
#                       `timeout` binary is available.
#
# Self-contained by design: an adapter is one droppable file resolved by name,
# so the small verdict normalizer below is duplicated per adapter rather than
# sourced from a sibling.

set -u

VERB="${1:-}"

judge_env_clean() {
    env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX \
        -u GIT_COMMON_DIR -u GIT_AUTHOR_DATE -u GIT_COMMITTER_DATE \
        -u CURSOR_AGENT \
        "$@"
}

# Normalize raw CLI stdout to the judge contract: the first well-formed VERDICT
# line, then any REASON lines. No verdict → exit 2 (the caller degrades).
emit_verdict() {
    awk '
        !v && $0 ~ /^[ \t]*VERDICT:[ \t]*(PASS|REFUTED)[ \t]*\r?$/ {
            line = $0
            sub(/^[ \t]*VERDICT:[ \t]*/, "", line)
            sub(/[ \t\r]*$/, "", line)
            v = line
            print "VERDICT: " v
            next
        }
        v && $0 ~ /^[ \t]*REASON:/ {
            line = $0
            sub(/^[ \t]*/, "", line)
            sub(/[ \t\r]*$/, "", line)
            print line
        }
        END { if (!v) { exit 2 } }
    '
}

do_judge() {
    local tier="${1:-low}" model="${2:-}"
    command -v cursor-agent >/dev/null 2>&1 || {
        printf 'cursor-agent adapter: no `cursor-agent` CLI on PATH\n' >&2
        return 2
    }
    if [[ -z "$model" ]]; then
        case "$tier" in
            high)   model="opus-4.1" ;;
            medium) model="sonnet-4.5" ;;
            *)      model="auto" ;;
        esac
    fi
    local prompt
    prompt="$(cat)"
    [[ -n "$prompt" ]] || return 2

    local -a runner=()
    if command -v timeout >/dev/null 2>&1; then
        runner=(timeout "${AGENT_JUDGE_TIMEOUT:-120}")
    elif command -v gtimeout >/dev/null 2>&1; then
        runner=(gtimeout "${AGENT_JUDGE_TIMEOUT:-120}")
    fi

    local out
    out="$(printf '%s\n' "$prompt" | judge_env_clean ${runner[@]+"${runner[@]}"} \
        cursor-agent -p --model "$model" 2>/dev/null)" || return 2
    printf '%s\n' "$out" | emit_verdict || return 2
    return 0
}

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
    judge)
        do_judge "${2:-}" "${3:-}"
        exit $?
        ;;
    resolve)
        do_resolve
        exit $?
        ;;
    emit)
        do_emit
        exit $?
        ;;
    "")
        printf 'cursor-agent adapter: usage: cursor-agent.sh {resolve <session> [<declared>]|emit|judge [<tier>] [<model>]}\n' >&2
        exit 2
        ;;
    *)
        printf 'cursor-agent adapter: unknown verb %s (supported: resolve, emit, judge)\n' "$VERB" >&2
        exit 2
        ;;
esac

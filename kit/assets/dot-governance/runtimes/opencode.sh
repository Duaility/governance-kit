#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# OpenCode runtime adapter — one file per harness, three verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <session-id> [<declared-path>] — OFF the commit path. Probes, in
#     order: $OPENCODE_SERVER, then http://127.0.0.1:4096 (OpenCode's
#     documented local server default), and asks it directly for the named
#     session — never a scan, never "whichever session the server happens to
#     be showing":
#         curl -sf --max-time 2 <base>/session/<session-id>
#     Any curl failure (no server, timeout, non-2xx, empty body) → exit 2 —
#     never a guess. On a success, parses `cost` and
#     `tokens.{input,output,cache.{read,write}}` with key-anchored awk and
#     prints one line to stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> server
#     `tokens.cache.write` maps to this adapter's `cache_create` column,
#     `tokens.cache.read` to `cache_read`. OpenCode also reports a reasoning-
#     token count on some models; it is deliberately DROPPED, not folded into
#     `output` — the sidecar's four columns are the whole contract, and
#     silently inflating one of them would misrepresent what the harness
#     itself reported.
#
#     TEST SEAM: when $OPENCODE_RESPONSE_FILE is set, this adapter reads that
#     file's contents as the server's response body instead of making any
#     network call at all — curl's transport behavior isn't something a
#     governance-kit test should depend on, so this lets tests exercise the
#     JSON parse and the probe-order/fallback logic deterministically and
#     offline. It is a test-only override: no released flow sets it.
#
#   emit — identity-only: if OPENCODE_SESSION_ID is set (or the payload on
#     stdin/argv[1] carries a `sessionId`/`session_id`) and the caller is
#     inside a git working tree, refreshes the commit-path identity file. No
#     sidecar snapshot — OpenCode's push surface, if any, is undocumented, so
#     this adapter records only what it is sure of: identity.
#
#   judge [<tier>] [<model>] — read a fully-built adjudication prompt on stdin,
#     run the `opencode` CLI non-interactively, and print exactly:
#         VERDICT: PASS            (or VERDICT: REFUTED)
#         REASON: <text>           (zero or more lines)
#     <tier> is the capability tier (low | medium | high; empty → low) and picks
#     this adapter's own default model; <model> overrides it outright. Uses
#     OpenCode's documented `opencode run` single-shot mode.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# the server is unreachable or the response is unparseable (`resolve`), or a
# missing CLI / transport failure / unparseable answer (`judge`). `emit` never
# exits 2. Exit 2 is never fatal to the caller: the commit lane degrades to
# the harness (sub-agent) path rather than blocking on a broken side channel.
#
# Environment overrides:
#   OPENCODE_SERVER         base URL of the local OpenCode server (default
#                           http://127.0.0.1:4096).
#   OPENCODE_SESSION_ID     the live session id (for `emit`'s identity refresh).
#   OPENCODE_RESPONSE_FILE  TEST SEAM ONLY — see `resolve` above.
#   AGENT_JUDGE_TIMEOUT     seconds to allow the judge CLI (default 120), when
#                           a `timeout` binary is available.
#
# Self-contained by design: an adapter is one droppable file resolved by name,
# so the small verdict normalizer below is duplicated per adapter rather than
# sourced from a sibling.

set -u

VERB="${1:-}"

judge_env_clean() {
    env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX \
        -u GIT_COMMON_DIR -u GIT_AUTHOR_DATE -u GIT_COMMITTER_DATE \
        -u OPENCODE -u OPENCODE_SERVER -u OPENCODE_SESSION_ID \
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
    command -v opencode >/dev/null 2>&1 || {
        printf 'opencode adapter: no `opencode` CLI on PATH\n' >&2
        return 2
    }
    if [[ -z "$model" ]]; then
        case "$tier" in
            high)   model="anthropic/claude-opus-4-5" ;;
            medium) model="anthropic/claude-sonnet-4-5" ;;
            *)      model="anthropic/claude-haiku-4-5" ;;
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
    out="$(judge_env_clean ${runner[@]+"${runner[@]}"} \
        opencode run --model "$model" "$prompt" 2>/dev/null)" || return 2
    printf '%s\n' "$out" | emit_verdict || return 2
    return 0
}

# Key-anchored extraction of the /session/<id> response body in POSIX awk
# (issue #355 — no python on any path). Reasoning tokens are read by no
# lookup here at all — dropping them is a parse-time omission, not a
# runtime decision.
parse_session_response() {
    awk '
function jnum(line, key,   p, rest, i, ch, out) {
    p = index(line, "\"" key "\":")
    if (p == 0) { return -1 }
    rest = substr(line, p + length(key) + 3)
    while (substr(rest, 1, 1) == " ") { rest = substr(rest, 2) }
    out = ""
    for (i = 1; i <= length(rest); i++) {
        ch = substr(rest, i, 1)
        if (ch ~ /[0-9.eE+-]/) { out = out ch } else { break }
    }
    if (out == "") { return -1 }
    return out + 0
}
function jobj(line, key,   p, rest, e) {
    p = index(line, "\"" key "\":{")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "}")
    if (e == 0) { return rest }
    return substr(rest, 1, e - 1)
}
{ buf = buf $0 "\n" }
END {
    cost = jnum(buf, "cost")
    tk = jobj(buf, "tokens")
    if (tk == "") { exit 2 }
    ti = jnum(tk, "input");  if (ti < 0) { ti = 0 }
    to = jnum(tk, "output"); if (to < 0) { to = 0 }
    ck = jobj(tk, "cache")
    cr = jnum(ck, "read");  if (cr < 0) { cr = 0 }
    cc = jnum(ck, "write"); if (cc < 0) { cc = 0 }
    c = (cost >= 0) ? sprintf("%.4f", cost) : "-"
    printf "%d %d %d %d unknown %s server\n", ti, cc, cr, to, c
}
'
}

do_resolve() {
    local session="${1:-}" declared="${2:-}"
    [[ -n "$session" ]] || return 2

    local body
    if [[ -n "${OPENCODE_RESPONSE_FILE:-}" ]]; then
        # Test seam only — see the header comment above.
        [[ -f "$OPENCODE_RESPONSE_FILE" ]] || return 2
        body="$(cat "$OPENCODE_RESPONSE_FILE")"
    else
        command -v curl >/dev/null 2>&1 || return 2
        local base="${OPENCODE_SERVER:-http://127.0.0.1:4096}"
        body="$(curl -sf --max-time 2 "${base%/}/session/${session}" 2>/dev/null)" || return 2
    fi
    [[ -n "$body" ]] || return 2

    printf '%s\n' "$body" | parse_session_response
}

parse_identity_payload() {
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
    sid = jstr(buf, "sessionId")
    if (sid == "") { sid = jstr(buf, "session_id") }
    cwd = jstr(buf, "cwd")
    printf "%s\t%s\n", sid, cwd
}
'
}

do_emit() {
    local session="${OPENCODE_SESSION_ID:-}"
    local cwd=""
    local payload
    payload="$(cat)"
    if [[ -n "$payload" ]]; then
        local parsed psid pcwd
        parsed="$(printf '%s\n' "$payload" | parse_identity_payload)"
        IFS=$'\t' read -r psid pcwd <<EOF_PARSED
$parsed
EOF_PARSED
        [[ -z "$session" && -n "$psid" ]] && session="$psid"
        [[ -n "$pcwd" ]] && cwd="$pcwd"
    fi
    [[ -n "$session" ]] || return 0

    [[ -n "$cwd" ]] || cwd="$PWD"
    local gitd
    gitd="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -n "$gitd" ]] || return 0

    mkdir -p "$gitd/governance" 2>/dev/null || return 0
    {
        printf 'harness=opencode\n'
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
        do_resolve "${2:-}" "${3:-}"
        exit $?
        ;;
    emit)
        do_emit
        exit $?
        ;;
    "")
        printf 'opencode adapter: usage: opencode.sh {resolve <session> [<declared>]|emit|judge [<tier>] [<model>]}\n' >&2
        exit 2
        ;;
    *)
        printf 'opencode adapter: unknown verb %s (supported: resolve, emit, judge)\n' "$VERB" >&2
        exit 2
        ;;
esac

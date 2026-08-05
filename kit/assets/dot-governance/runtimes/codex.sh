#!/usr/bin/env bash
# governance-kit:managed kit-version=0.13.0
# Codex runtime adapter — one file per harness, two verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <thread-id> [<declared-path>] — OFF the commit path. Prints one
#     line to stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> <source>
#     or exits 2 when the session cannot be resolved (caller records nothing —
#     never a guess). IDENTITY-PINNED ONLY: the only rollout file this adapter
#     will open is (a) the <declared-path> argument, (b) $CODEX_TRANSCRIPT_PATH,
#     or (c) a file under $CODEX_SESSIONS_DIR / $CODEX_ARCHIVED_SESSIONS_DIR
#     whose NAME ends with the exact `<thread-id>.jsonl`. No `ls -t`, no
#     newest-file selection of any kind.
#
#     `cost_usd` is the figure the HARNESS reported, verbatim, or the literal
#     `-` when it reports none. The current Codex stream carries no dollar
#     figure, so `-` is the normal answer; if a future stream adds
#     `total_cost_usd` to the token-count payload it is passed through
#     untouched. The adapter never prices anything (issue #355).
#
#   emit — accepts the Codex notify hook's payload, either as argv[1] (a JSON
#     string) or on stdin, and refreshes the commit-path identity file.
#     IDENTITY ONLY: this adapter records no sidecar snapshot from `emit` —
#     the notify payload carries no reliable session-cumulative token or cost
#     figures, so pushing a snapshot here would risk a `harness-feed` row of
#     zeros racing ahead of a real `resolve` at fold time. Session id is read
#     from a documented `thread_id` (or `session_id`) key; silently exits 0
#     when the payload names no session, or when the payload's `cwd` (or
#     $PWD) is not inside a git working tree.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable transcript (`resolve`), `emit` never exits 2 — a push that cannot be
# attributed is simply dropped (exit 0). Exit 2 is never fatal to the caller:
# the commit lane degrades to the harness (sub-agent) path rather than
# blocking on a broken side channel.
#
# Codex reports OpenAI cached input as a SUBSET of input tokens. The ledger
# wants lossless split columns, so this adapter records:
#   input        = input_tokens - cached_input_tokens
#   cache_read   = cached_input_tokens
#   cache_create = 0
# Keeping the shape identical to claude-code.sh lets the caller treat every
# adapter uniformly.
#
# Environment overrides:
#   CODEX_TRANSCRIPT_PATH    absolute path to the session JSONL — also the
#                            declared-path source `resolve` prefers when the
#                            caller passed no explicit <declared-path>.
#   CODEX_SESSIONS_DIR       override ~/.codex/sessions
#   CODEX_ARCHIVED_SESSIONS_DIR override ~/.codex/archived_sessions
#

set -u

VERB="${1:-}"

# JSONL extraction in POSIX awk (issue #355 — no python on any path). The
# Codex rollout transcript shape this reads:
#   - session_meta.payload.id                                    → session id
#   - turn_context.payload.collaboration_mode.settings.model     → model
#   - event_msg.payload.info.total_token_usage                   → cumulative
# The token lookup is scoped to the `total_token_usage` object, because the same
# line also carries `last_token_usage` with the per-turn numbers.
sum_transcript() {
    awk '
function jstr(line, key,   p, rest, e) {
    p = index(line, "\"" key "\":\"")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "\"")
    if (e == 0) { return "" }
    return substr(rest, 1, e - 1)
}
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
    # The flat object that follows "key":{ … } — cut at the first closing brace.
    p = index(line, "\"" key "\":{")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "}")
    if (e == 0) { return rest }
    return substr(rest, 1, e - 1)
}
BEGIN { have_total = 0 }
{
    if (sid == "" && index($0, "\"session_meta\"") > 0) {
        v = jstr($0, "id")
        if (v != "") { sid = v }
    }
    m = jstr($0, "model")
    if (m != "" && index($0, "\"collaboration_mode\"") > 0) { model = m }
    if (index($0, "\"token_count\"") > 0) {
        total = jobj($0, "total_token_usage")
        if (total != "") {
            ti = jnum(total, "input_tokens");        if (ti < 0) { ti = 0 }
            cr = jnum(total, "cached_input_tokens"); if (cr < 0) { cr = 0 }
            to = jnum(total, "output_tokens");       if (to < 0) { to = 0 }
            t_in = ti - cr
            if (t_in < 0) { t_in = 0 }
            t_cr = cr
            t_out = to
            have_total = 1
        }
        v = jnum($0, "total_cost_usd")
        if (v >= 0) { cost = v; have_cost = 1 }
    }
}
END {
    if (sid == "") { exit 2 }
    if (model == "") { model = "unknown" }
    if (!have_total) { t_in = 0; t_cr = 0; t_out = 0 }
    c = have_cost ? sprintf("%.4f", cost) : "-"
    printf "%d 0 %d %d %s %s session-file\n", t_in, t_cr, t_out, model, c
}
' "$1"
}

do_resolve() {
    local thread="${1:-}" declared="${2:-}"
    [[ -n "$thread" ]] || return 2

    local CODEX_SESSIONS CODEX_ARCHIVED_SESSIONS
    CODEX_SESSIONS="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"
    CODEX_ARCHIVED_SESSIONS="${CODEX_ARCHIVED_SESSIONS_DIR:-${HOME}/.codex/archived_sessions}"

    local transcript="$declared"
    [[ -z "$transcript" ]] && transcript="${CODEX_TRANSCRIPT_PATH:-}"
    if [[ -z "$transcript" ]]; then
        local dir
        for dir in "$CODEX_SESSIONS" "$CODEX_ARCHIVED_SESSIONS"; do
            [[ -d "$dir" ]] || continue
            transcript="$(find "$dir" -type f -name "*${thread}.jsonl" -print 2>/dev/null | LC_ALL=C sort | head -n1)"
            [[ -n "$transcript" ]] && break
        done
    fi

    [[ -n "$transcript" && -f "$transcript" ]] || return 2
    sum_transcript "$transcript"
}

# Extract identity fields from a Codex notify-hook payload. Field names are
# speculative-but-cheap (Codex documents no formal notify schema at the time
# of writing): a `thread_id` key is preferred, falling back to `session_id`;
# `cwd` locates the repo the hook fired in.
parse_notify() {
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
    sid = jstr(buf, "thread_id")
    if (sid == "") { sid = jstr(buf, "session_id") }
    cwd = jstr(buf, "cwd")
    printf "%s\t%s\n", sid, cwd
}
'
}

do_emit() {
    local raw="${1:-}"
    if [[ -n "$raw" ]]; then
        # Drain stdin anyway so a caller that also piped JSON doesn't SIGPIPE.
        cat >/dev/null 2>&1 || true
    else
        raw="$(cat)"
    fi
    [[ -n "$raw" ]] || return 0

    local parsed session cwd
    parsed="$(printf '%s\n' "$raw" | parse_notify)"
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
        printf 'harness=codex\n'
        printf 'session=%s\n' "$session"
        printf 'declared=%s\n' "${CODEX_TRANSCRIPT_PATH:-}"
        printf 'epoch=%s\n' "$(date +%s)"
    } > "$gitd/governance/session-identity"
    return 0
}

case "$VERB" in
    resolve)
        do_resolve "${2:-}" "${3:-}"
        exit $?
        ;;
    emit)
        do_emit "${2:-}"
        exit $?
        ;;
    "")
        printf 'codex adapter: usage: codex.sh {resolve <thread-id> [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'codex adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

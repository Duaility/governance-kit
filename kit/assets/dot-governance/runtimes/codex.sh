#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Codex runtime adapter — one file per harness, two verbs (issue #355).
#
# Verb interface (argv[1]; a bare invocation defaults to `cost`):
#
#   cost — the harness's OWN reported session usage, one line to stdout:
#       <session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>
#
#     `cost_usd` is the figure the HARNESS reported, verbatim, or the literal
#     `-` when it reports none. The current Codex stream carries no dollar
#     figure, so `-` is the normal answer; if a future stream adds
#     `total_cost_usd` to the token-count payload it is passed through
#     untouched. The adapter never prices anything (issue #355).
#
#   judge [<tier>] [<model>] — read a fully-built adjudication prompt on stdin,
#     run `codex exec` non-interactively, and print exactly:
#         VERDICT: PASS            (or VERDICT: REFUTED)
#         REASON: <text>           (zero or more lines)
#     <tier> is the capability tier (low | medium | high; empty → low); this
#     adapter carries no per-tier model table — it leaves the model unset so the
#     Codex CLI's own configured default applies — and <model> overrides that
#     outright (the caller's SUBAGENT_MODELS_<TIER> conf value).
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable transcript (`cost`), or a missing CLI / transport failure /
# unparseable answer (`judge`). Exit 2 is never fatal to the caller: the commit
# lane degrades to the harness (sub-agent) path rather than blocking on a
# broken side channel.
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
#   CODEX_TRANSCRIPT_PATH    absolute path to the session JSONL
#   CODEX_SESSIONS_DIR       override ~/.codex/sessions
#   CODEX_ARCHIVED_SESSIONS_DIR override ~/.codex/archived_sessions
#   CODEX_THREAD_ID          the live thread/session id (exported into the hook
#                            env by Codex) — names the transcript.
#   AGENT_JUDGE_TIMEOUT      seconds to allow the judge CLI (default 120), when
#                            a `timeout` binary is available.
#
# Self-contained by design: an adapter is one droppable file resolved by name,
# so the small verdict normalizer below is duplicated per adapter rather than
# sourced from a sibling.

set -u

VERB="${1:-cost}"

# Every environment handle that ties a nested CLI run to the CALLING session:
# the git plumbing a hook exports (which would make the judge operate on the
# caller's index) and the harness session ids (which would bill the audit to the
# session under audit and hand it that session's context). A judge that inherits
# the author's session is not an independent judge.
judge_env_clean() {
    env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX \
        -u GIT_COMMON_DIR -u GIT_AUTHOR_DATE -u GIT_COMMITTER_DATE \
        -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_TRANSCRIPT_PATH \
        -u CODEX_THREAD_ID -u CODEX_TRANSCRIPT_PATH \
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
    # $1 = capability tier — deliberately unused here: this adapter ships no
    # per-tier model table, so an unset model means "whatever the Codex CLI is
    # configured to use". $2 = the caller's explicit model override.
    local model="${2:-}"
    command -v codex >/dev/null 2>&1 || {
        printf 'codex adapter: no `codex` CLI on PATH\n' >&2
        return 2
    }
    local prompt
    prompt="$(cat)"
    [[ -n "$prompt" ]] || return 2

    local -a runner=() model_args=()
    if command -v timeout >/dev/null 2>&1; then
        runner=(timeout "${AGENT_JUDGE_TIMEOUT:-120}")
    elif command -v gtimeout >/dev/null 2>&1; then
        runner=(gtimeout "${AGENT_JUDGE_TIMEOUT:-120}")
    fi
    [[ -n "$model" ]] && model_args=(--model "$model")

    local out
    out="$(printf '%s\n' "$prompt" | judge_env_clean ${runner[@]+"${runner[@]}"} \
        codex exec ${model_args[@]+"${model_args[@]}"} 2>/dev/null)" || return 2
    printf '%s\n' "$out" | emit_verdict || return 2
    return 0
}

case "$VERB" in
    cost) ;;
    judge)
        do_judge "${2:-}" "${3:-}"
        exit $?
        ;;
    *)
        printf 'codex adapter: unknown verb %s (supported: cost, judge)\n' "$VERB" >&2
        exit 2
        ;;
esac

CODEX_SESSIONS="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"
CODEX_ARCHIVED_SESSIONS="${CODEX_ARCHIVED_SESSIONS_DIR:-${HOME}/.codex/archived_sessions}"

TRANSCRIPT="${CODEX_TRANSCRIPT_PATH:-}"
if [[ -z "$TRANSCRIPT" ]]; then
    [[ -n "${CODEX_THREAD_ID:-}" ]] || exit 2
    for dir in "$CODEX_SESSIONS" "$CODEX_ARCHIVED_SESSIONS"; do
        [[ -d "$dir" ]] || continue
        TRANSCRIPT="$(find "$dir" -type f -name "*${CODEX_THREAD_ID}.jsonl" -print 2>/dev/null | LC_ALL=C sort | head -n1)"
        [[ -n "$TRANSCRIPT" ]] && break
    done
fi

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 2

# JSONL extraction in POSIX awk (issue #355 — no python on the commit path).
# The Codex Desktop transcript shape this reads:
#   - session_meta.payload.id                                    → session id
#   - turn_context.payload.collaboration_mode.settings.model     → model
#   - event_msg.payload.info.total_token_usage                   → cumulative
# The token lookup is scoped to the `total_token_usage` object, because the same
# line also carries `last_token_usage` with the per-turn numbers.
CODEX_ENV_SID="${CODEX_THREAD_ID:-}" awk '
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
BEGIN { sid = ENVIRON["CODEX_ENV_SID"]; have_total = 0 }
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
    printf "%s %d 0 %d %d %s %s\n", sid, t_in, t_cr, t_out, model, c
}
' "$TRANSCRIPT"

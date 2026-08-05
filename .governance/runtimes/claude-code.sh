#!/usr/bin/env bash
# governance-kit:managed kit-version=0.13.0
# Claude Code runtime adapter — one file per harness, two verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <session-id> [<declared-path>] — OFF the commit path. Prints one
#     line to stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> <source>
#     or exits 2 when the session cannot be resolved (caller records nothing —
#     never a guess). IDENTITY-PINNED ONLY: the only transcript this adapter
#     will open is (a) the <declared-path> argument, (b) $CLAUDE_TRANSCRIPT_PATH,
#     or (c) a file whose NAME is exactly `<session-id>.jsonl` under
#     $CLAUDE_PROJECTS_DIR (or its default). No `ls -t`, no `-mmin`, no
#     "newest file" — those heuristics are deleted, not just avoided.
#     `cost_usd` is the harness's OWN reported figure — the sum of the
#     transcript's per-entry `costUSD` values — or the literal `-` when the
#     transcript carries none. This adapter never prices (issue #355).
#
#   emit — reads the Claude Code statusline hook's JSON payload on stdin
#     (one object; see https://docs.claude.com/… "Statusline" for the shape),
#     appends a `harness-feed` snapshot to the session's cost sidecar, and
#     refreshes the commit-path identity file. Cheap and safe to call on
#     every statusline refresh: one `>>` append, one identity-file rewrite,
#     no locks. Cost is the payload's cumulative `cost.total_cost_usd` — the
#     token fields in the statusline payload describe context-window state,
#     NOT session-cumulative usage, so `emit` never sums them; it records
#     tokens as `0 0 0 0` and trusts cost as the headline figure. A later
#     `resolve` (which reads the transcript directly) fills real token
#     columns in a `session-file` snapshot that out-ranks this one at fold
#     time (see lib/costs.sh — spec'd in SPEC-355-COSTS-V2.md so both sides
#     agree). Silently exits 0 when the payload names no session, or when the
#     payload's cwd (or $PWD) is not inside a git working tree — a hook
#     firing outside a repo is not an error.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable transcript (`resolve`), `emit` never exits 2 — a push that cannot be
# attributed is simply dropped (exit 0). Exit 2 is never fatal to the caller:
# the commit lane degrades to the harness (sub-agent) path rather than
# blocking on a broken side channel.
#
# `model` is the latest `model` seen on an assistant entry (latest wins, so a
# mid-session /model switch propagates forward), or `unknown`. Nothing is
# blocked on it any more — it is a label on the row, not a pricing key.
#
# Environment overrides:
#   CLAUDE_TRANSCRIPT_PATH    absolute path to the session JSONL — also the
#                             declared-path source `resolve` prefers when the
#                             caller passed no explicit <declared-path>.
#   CLAUDE_PROJECTS_DIR       override ~/.claude/projects
#

set -u

VERB="${1:-}"

encode_path() {
    # Replace every `/` and `.` with `-`, matching Claude Code's project-dir convention.
    printf '%s' "$1" | sed -E 's#[/.]#-#g'
}

# JSONL usage extraction in POSIX awk (issue #355 — no python on any path).
# Conservative, per-line, key-anchored substring lookups; a malformed line
# simply contributes nothing. Each lookup anchors on the opening quote of its
# key, so `"input_tokens":` cannot match inside `"cache_read_input_tokens":`.
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
{
    if ($0 ~ /"type"[ ]*:[ ]*"assistant"/ || $0 ~ /"role"[ ]*:[ ]*"assistant"/) {
        m = jstr($0, "model")
        if (m != "" && m != "<synthetic>") { model = m }
    }
    if (index($0, "\"usage\"") > 0) {
        v = jnum($0, "input_tokens");                if (v >= 0) { t_in += v }
        v = jnum($0, "cache_creation_input_tokens"); if (v >= 0) { t_cc += v }
        v = jnum($0, "cache_read_input_tokens");     if (v >= 0) { t_cr += v }
        v = jnum($0, "output_tokens");               if (v >= 0) { t_out += v }
    }
    v = jnum($0, "costUSD")
    if (v < 0) { v = jnum($0, "total_cost_usd") }
    if (v >= 0) { cost += v; have_cost = 1 }
}
END {
    if (model == "") { model = "unknown" }
    c = have_cost ? sprintf("%.4f", cost) : "-"
    printf "%d %d %d %d %s %s session-file\n", t_in, t_cc, t_cr, t_out, model, c
}
' "$1"
}

do_resolve() {
    local session="${1:-}" declared="${2:-}"
    [[ -n "$session" ]] || return 2

    local REPO_ROOT CLAUDE_PROJECTS
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}"

    local transcript="$declared"
    [[ -z "$transcript" ]] && transcript="${CLAUDE_TRANSCRIPT_PATH:-}"

    # Deterministic resolution only (issue #325, tightened by issue #355):
    # the session's transcript is `<projects>/<encoded-cwd>/<session-id>.jsonl`.
    # Naming the file directly by the exact session id — never by mtime —
    # removes any chance of grabbing a throwaway or unrelated transcript.
    if [[ -z "$transcript" ]]; then
        local candidate f
        for candidate in "$REPO_ROOT" "$PWD"; do
            f="$CLAUDE_PROJECTS/$(encode_path "$candidate")/${session}.jsonl"
            if [[ -f "$f" ]]; then
                transcript="$f"
                break
            fi
        done
    fi
    # Cross-worktree lookup: the encoded-cwd dir didn't match (e.g. resolving
    # from a different worktree than the one the session ran in) — find the
    # file named for this exact session anywhere under CLAUDE_PROJECTS.
    # Still identity-pinned by exact name — never an mtime guess.
    if [[ -z "$transcript" && -d "$CLAUDE_PROJECTS" ]]; then
        transcript="$(find "$CLAUDE_PROJECTS" -type f -name "${session}.jsonl" 2>/dev/null | head -n1)"
    fi

    [[ -n "$transcript" && -f "$transcript" ]] || return 2
    sum_transcript "$transcript"
}

# Extract a flat top-level-or-nested JSON value from the whole statusline
# payload. `jobj` cuts an object value at its first closing brace — safe here
# because every object this adapter reads (`model`, `cost`, `workspace`) is a
# flat object of scalars, never itself nested.
parse_statusline() {
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
    p = index(line, "\"" key "\":{")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "}")
    if (e == 0) { return rest }
    return substr(rest, 1, e - 1)
}
{ buf = buf $0 "\n" }
END {
    sid = jstr(buf, "session_id")
    transcript = jstr(buf, "transcript_path")
    modelobj = jobj(buf, "model")
    model = jstr(modelobj, "id")
    if (model == "") { model = "unknown" }
    costobj = jobj(buf, "cost")
    cost = jnum(costobj, "total_cost_usd")
    c = (cost >= 0) ? sprintf("%.4f", cost) : "-"
    cwd = jstr(buf, "cwd")
    if (cwd == "") {
        wsobj = jobj(buf, "workspace")
        cwd = jstr(wsobj, "current_dir")
    }
    printf "%s\t%s\t%s\t%s\t%s\n", sid, model, c, cwd, transcript
}
'
}

do_emit() {
    local payload
    payload="$(cat)"
    [[ -n "$payload" ]] || return 0

    local parsed session model cost cwd transcript
    parsed="$(printf '%s\n' "$payload" | parse_statusline)"
    IFS=$'\t' read -r session model cost cwd transcript <<EOF_PARSED
$parsed
EOF_PARSED
    [[ -n "$session" ]] || return 0

    [[ -n "$cwd" ]] || cwd="$PWD"
    local gitd
    gitd="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -n "$gitd" ]] || return 0

    mkdir -p "$gitd/governance/costs" 2>/dev/null || return 0
    local epoch
    epoch="$(date +%s)"
    printf 'v1 %s 0 0 0 0 %s %s harness-feed\n' "$epoch" "$model" "$cost" \
        >> "$gitd/governance/costs/claude-code-${session}"
    {
        printf 'harness=claude-code\n'
        printf 'session=%s\n' "$session"
        printf 'declared=%s\n' "$transcript"
        printf 'epoch=%s\n' "$epoch"
    } > "$gitd/governance/session-identity"
    return 0
}

case "$VERB" in
    resolve)
        do_resolve "${2:-}" "${3:-}"
        exit $?
        ;;
    emit)
        do_emit
        exit $?
        ;;
    "")
        printf 'claude-code adapter: usage: claude-code.sh {resolve <session> [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'claude-code adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

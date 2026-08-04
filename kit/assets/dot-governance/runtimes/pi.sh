#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Pi coding agent runtime adapter — one file per harness, two verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <session-id> [<declared-path>] — OFF the commit path. Prints one
#     line to stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> <source>
#     or exits 2 when the session cannot be resolved (caller records nothing —
#     never a guess). IDENTITY-PINNED ONLY: the only session file this adapter
#     will open is (a) the <declared-path> argument, (b) $PI_SESSION_FILE, or
#     (c) a file under $PI_SESSIONS_DIR (documented default
#     ${PI_HOME:-$HOME/.pi}/sessions) whose NAME matches `*_<session-id>.jsonl`
#     exactly by the session id suffix. No `ls -t`, no newest-file selection.
#
#     Pi's session JSONL carries a per-message `"usage"` object with `input`,
#     `output`, `cacheRead`, `cacheWrite`, and (unlike Codex) a `cost.total` in
#     dollars — Pi DOES report cost, so it rides through verbatim, summed
#     across messages. `cacheWrite` maps to this adapter's `cache_create`
#     column and `cacheRead` to `cache_read`, matching every other adapter's
#     shape. The adapter never prices anything itself (issue #355).
#
#   emit — Pi has no documented command-hook payload to push from, so this is
#     an identity-only best effort from the environment: if PI_SESSION_ID is
#     set and the caller is inside a git working tree ($PWD — there is no
#     payload to read a cwd from), refreshes the commit-path identity file.
#     No session id → silently exits 0.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable session file (`resolve`), `emit` never exits 2. Exit 2 is never fatal to
# the caller: the commit lane degrades to the harness (sub-agent) path rather
# than blocking on a broken side channel.
#
# Environment overrides:
#   PI_SESSION_FILE    absolute path to the session JSONL — also the
#                       declared-path source `resolve` prefers when the caller
#                       passed no explicit <declared-path>.
#   PI_HOME             override ~/.pi
#   PI_SESSIONS_DIR     override $PI_HOME/sessions
#   PI_SESSION_ID       the live session id (for `emit`'s identity refresh).
#

set -u

VERB="${1:-}"

# JSONL extraction in POSIX awk (issue #355 — no python on any path).
# Conservative, per-line, key-anchored substring lookups guarded by an
# `"usage"` marker on the line, matching the style every other adapter uses.
sum_session() {
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
    m = jstr($0, "model")
    if (m != "") { model = m }
    if (index($0, "\"usage\"") > 0) {
        v = jnum($0, "input");      if (v >= 0) { t_in += v }
        v = jnum($0, "output");     if (v >= 0) { t_out += v }
        v = jnum($0, "cacheRead");  if (v >= 0) { t_cr += v }
        v = jnum($0, "cacheWrite"); if (v >= 0) { t_cc += v }
        v = jnum($0, "total");      if (v >= 0) { cost += v; have_cost = 1 }
    }
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

    local PI_SESSIONS
    PI_SESSIONS="${PI_SESSIONS_DIR:-${PI_HOME:-${HOME}/.pi}/sessions}"

    local file="$declared"
    [[ -z "$file" ]] && file="${PI_SESSION_FILE:-}"
    if [[ -z "$file" && -d "$PI_SESSIONS" ]]; then
        file="$(find "$PI_SESSIONS" -type f -name "*_${session}.jsonl" 2>/dev/null | LC_ALL=C sort | head -n1)"
    fi

    [[ -n "$file" && -f "$file" ]] || return 2
    sum_session "$file"
}

do_emit() {
    [[ -n "${PI_SESSION_ID:-}" ]] || return 0
    local gitd
    gitd="$(git -C "$PWD" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -n "$gitd" ]] || return 0
    # Drain stdin if anything was piped, so a hook caller never SIGPIPEs.
    cat >/dev/null 2>&1 || true
    mkdir -p "$gitd/governance" 2>/dev/null || return 0
    {
        printf 'harness=pi\n'
        printf 'session=%s\n' "$PI_SESSION_ID"
        printf 'declared=%s\n' "${PI_SESSION_FILE:-}"
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
        do_emit
        exit $?
        ;;
    "")
        printf 'pi adapter: usage: pi.sh {resolve <session> [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'pi adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

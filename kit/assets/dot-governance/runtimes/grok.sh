#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Grok runtime adapter — one file per harness, two verbs
# (issue #355 v2: identity at commit, measurement at rest).
#
# Verb interface (argv[1]; a bare invocation prints usage and exits 2):
#
#   resolve <session-id> [<declared-path>] — OFF the commit path. Prints one
#     line to stdout:
#         <input> <cache_create> <cache_read> <output> <model> <cost_usd|-> <source>
#     or exits 2 when the session cannot be resolved (caller records nothing —
#     never a guess). IDENTITY-PINNED ONLY: the only directory this adapter
#     will look in is (a) the <declared-path> argument (a session directory or
#     a file inside one), or (b) $GROK_HOME/sessions/<session-id> (default
#     $HOME/.grok/sessions/<session-id>) — the exact session id as a directory
#     name, never a glob. No `ls -t`, no newest-file/newest-dir selection.
#
#     Inside that directory this adapter reads the documented `signals.json`
#     (preferred) or `summary.json` sidecar the session directory carries, and
#     conservatively key-anchors `input_tokens` / `output_tokens` /
#     `cache_read_tokens` / `cache_write_tokens` / `total_cost_usd` out of it.
#     `input_tokens`/`output_tokens` are required — either missing is treated
#     as "cannot resolve" (exit 2) rather than guessed as zero. `cost_usd` is
#     `-` unless the file carries the documented `total_cost_usd`. The adapter
#     never prices anything itself (issue #355).
#
#   emit — Grok exports nothing into the environment, so the ONLY way this
#     adapter learns a session id is a wired SessionStart-style hook handing
#     it a JSON envelope with a `sessionId` field (and, ideally, `cwd`) on
#     stdin. On a successful parse it both refreshes the commit-path identity
#     file AND appends an identity-only snapshot (all-zero counters, source
#     `harness-feed`) to the sidecar — the zero row exists purely so a
#     same-session `resolve` has an anchor to out-rank at fold time; it is
#     never read as a real number. Silently exits 0 when the payload names no
#     session, or when the payload's cwd (or $PWD) is not inside a git
#     working tree.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable/incomplete signals file (`resolve`). `emit` never exits 2. Exit
# 2 is never fatal to the caller: an unattributable session is a row the ledger
# simply does not carry.
#
# Environment overrides:
#   GROK_HOME           override $HOME/.grok
#

set -u

VERB="${1:-}"

# Key-anchored counter extraction in POSIX awk (issue #355 — no python on any
# path). `input_tokens`/`output_tokens` are required; the caller (do_resolve)
# treats their absence as "cannot resolve".
read_signals() {
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
    ti = jnum(buf, "input_tokens")
    to = jnum(buf, "output_tokens")
    if (ti < 0 || to < 0) { exit 2 }
    cr = jnum(buf, "cache_read_tokens");  if (cr < 0) { cr = 0 }
    cc = jnum(buf, "cache_write_tokens"); if (cc < 0) { cc = 0 }
    cost = jnum(buf, "total_cost_usd")
    c = (cost >= 0) ? sprintf("%.4f", cost) : "-"
    model = jstr(buf, "model"); if (model == "") { model = "unknown" }
    printf "%d %d %d %d %s %s session-file\n", ti, cc, cr, to, model, c
}
'
}

do_resolve() {
    local session="${1:-}" declared="${2:-}"
    [[ -n "$session" ]] || return 2

    local GROK_SESSIONS="${GROK_HOME:-${HOME}/.grok}/sessions"
    local dir="$declared"
    if [[ -n "$dir" && ! -d "$dir" ]]; then
        # A file was declared (e.g. signals.json directly) — its parent is
        # the session directory.
        dir="$(dirname "$dir")"
    fi
    [[ -z "$dir" ]] && dir="$GROK_SESSIONS/$session"
    [[ -d "$dir" ]] || return 2

    local f
    for f in "$dir/signals.json" "$dir/summary.json"; do
        [[ -f "$f" ]] || continue
        read_signals < "$f" && return 0
    done
    return 2
}

# Extract identity fields from a Grok hook envelope.
parse_envelope() {
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
    parsed="$(printf '%s\n' "$payload" | parse_envelope)"
    IFS=$'\t' read -r session cwd <<EOF_PARSED
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
    printf 'v1 %s 0 0 0 0 unknown - harness-feed\n' "$epoch" \
        >> "$gitd/governance/costs/grok-${session}"
    {
        printf 'harness=grok\n'
        printf 'session=%s\n' "$session"
        printf 'declared=\n'
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
        printf 'grok adapter: usage: grok.sh {resolve <session> [<declared>]|emit}\n' >&2
        exit 2
        ;;
    *)
        printf 'grok adapter: unknown verb %s (supported: resolve, emit)\n' "$VERB" >&2
        exit 2
        ;;
esac

#!/usr/bin/env bash
# Frozen endpoints + per-session checkpoints for agent-token-accounting
# (issues #305, #229) — flat `key=value` files, read and written in bash
# (issue #355 took python off the commit path).
#
# Both live in the git dir, so they survive branch switches inside a worktree
# and never reach a commit:
#
#   .git/governance-token-endpoints/<staged-tree>.endpoint
#       session= input= cache_create= cache_read= output= receipt= cost_key=
#       Written by hooks/pre-commit.sh after it appends the row and stages the
#       receipt; read by check.sh at commit-msg time. Keyed by the staged tree
#       so a later transcript movement belongs to a later row instead of
#       invalidating this commit.
#
#   .git/governance-token-checkpoints/<session>
#       input= cache_create= cache_read= output=
#       The session's last-written cumulative coordinate, which the writer
#       subtracts to derive this commit's delta — never the receipts, so a
#       delta cannot depend on which sibling receipts are visible in this
#       branch's tree.
#
# The pre-#355 JSON files (`<tree>.json`, `governance-token-checkpoints.json`)
# are ignored: both are local, disposable caches, and a stale one only costs a
# single zero-delta row.
#
# Sourced by check.sh / hooks/pre-commit.sh after sibling `receipt.sh` and
# `costs.sh`.

# _endpoint_get <file> <key>  → the value, or empty.
_endpoint_get() {
    [ -f "$1" ] || return 0
    ENDPOINT_KEY="$2" awk '
BEGIN { k = ENVIRON["ENDPOINT_KEY"] }
index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
' "$1"
}

# _endpoint_session_file <session>  → a filesystem-safe checkpoint name.
_endpoint_session_file() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# endpoint_write <file> <session> <cum-in> <cum-cc> <cum-cr> <cum-out> \
#                <receipt-relpath> <cost-key>
endpoint_write() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    {
        printf 'session=%s\n' "$2"
        printf 'input=%s\n' "$3"
        printf 'cache_create=%s\n' "$4"
        printf 'cache_read=%s\n' "$5"
        printf 'output=%s\n' "$6"
        printf 'receipt=%s\n' "$7"
        printf 'cost_key=%s\n' "$8"
    } > "$file"
}

# endpoint_verify <file> <repo-root>
#   Print one violation per line when the staged receipt row named by the
#   frozen endpoint does not carry the coordinate the writer sampled. Exit
#   non-zero when any fired.
endpoint_verify() {
    local file="$1" root="$2"
    local session receipt cost_key e_in e_cc e_cr e_out
    local receipt_path hits got_session got

    session="$(_endpoint_get "$file" session)"
    e_in="$(_endpoint_get "$file" input)"
    e_cc="$(_endpoint_get "$file" cache_create)"
    e_cr="$(_endpoint_get "$file" cache_read)"
    e_out="$(_endpoint_get "$file" output)"
    receipt="$(_endpoint_get "$file" receipt)"
    cost_key="$(_endpoint_get "$file" cost_key)"

    if [ -z "$session" ] || [ -z "$receipt" ] || [ -z "$cost_key" ] \
        || [ -z "$e_in" ] || [ -z "$e_cc" ] || [ -z "$e_cr" ] || [ -z "$e_out" ]; then
        printf 'pending commit — the frozen token endpoint %s is missing fields; re-stage through the pre-commit hook (a plain `git commit`)\n' "$file"
        return 1
    fi

    receipt_path="$root/$receipt"
    if [ ! -f "$receipt_path" ]; then
        printf "pending commit — frozen token endpoint names missing receipt '%s'\n" "$receipt"
        return 1
    fi

    hits="$(costs_find_cum "$receipt_path" "$cost_key" | wc -l | tr -d ' ')"
    if [ "$hits" != "1" ]; then
        printf "pending commit — frozen token endpoint cost-key '%s' appears %s times in %s; expected exactly one row\n" \
            "$cost_key" "$hits" "$receipt"
        return 1
    fi

    got="$(costs_find_cum "$receipt_path" "$cost_key")"
    local g_in g_cc g_cr g_out
    read -r got_session g_in g_cc g_cr g_out <<<"$got"
    if [ "$got_session" != "$session" ] || [ "$g_in" != "$e_in" ] \
        || [ "$g_cc" != "$e_cc" ] || [ "$g_cr" != "$e_cr" ] || [ "$g_out" != "$e_out" ]; then
        printf "pending commit — frozen token endpoint for cost-key '%s' records session '%s…' at (input=%s cache_create=%s cache_read=%s output=%s), but the staged receipt row has session '%s…' at (input=%s cache_create=%s cache_read=%s output=%s)\n" \
            "$cost_key" "${session:0:16}" "$e_in" "$e_cc" "$e_cr" "$e_out" \
            "${got_session:0:16}" "$g_in" "$g_cc" "$g_cr" "$g_out"
        return 1
    fi
    return 0
}

# checkpoint_get <dir> <session>  → "<in> <cc> <cr> <out>" (zeros when absent).
checkpoint_get() {
    local file="$1/$(_endpoint_session_file "$2")"
    local ci ccc ccr co
    ci="$(_endpoint_get "$file" input)"
    ccc="$(_endpoint_get "$file" cache_create)"
    ccr="$(_endpoint_get "$file" cache_read)"
    co="$(_endpoint_get "$file" output)"
    case "$ci$ccc$ccr$co" in
        *[!0-9]*|'') printf '0 0 0 0\n'; return 0 ;;
    esac
    printf '%s %s %s %s\n' "${ci:-0}" "${ccc:-0}" "${ccr:-0}" "${co:-0}"
}

# checkpoint_set <dir> <session> <in> <cc> <cr> <out>
checkpoint_set() {
    local dir="$1" file
    file="$dir/$(_endpoint_session_file "$2")"
    mkdir -p "$dir"
    {
        printf 'input=%s\n' "$3"
        printf 'cache_create=%s\n' "$4"
        printf 'cache_read=%s\n' "$5"
        printf 'output=%s\n' "$6"
    } > "$file"
}

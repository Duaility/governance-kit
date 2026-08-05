#!/usr/bin/env bash
# The resolve sweep — measurement at rest (issue #355).
#
# Everything that reads a harness surface happens HERE, off the commit path,
# driven by post-commit and pre-push. Both are best-effort by construction: a
# failed read means "try again later", never "commit blocked" and never a
# guessed number. That is the whole reason the sweep exists as its own lane —
# the pre-commit hook is synchronous, blocking and unretryable, so measuring
# there buys nothing and costs the commit.
#
# The adapter contract (kit-level registry, `.governance/runtimes/<name>.sh`):
#
#   bash <adapter> resolve <session-id> [<declared-path>]
#       → one line on stdout: `<input> <cc> <cr> <output> <model> <cost|-> <source>`
#       → exit 2 (or any non-zero) when it cannot resolve; the caller then
#         records NOTHING. A row that stays `-`/`unresolved` is the honest
#         answer for a harness with no readable per-session surface.
#
#   An adapter may open ONLY: an explicitly passed declared path, a file whose
#   name contains the exact session id under the harness's documented state
#   dir, or a harness-declared local server. Never "the newest file".
#
# Sourced by hooks/post-commit.sh and hooks/pre-push.sh AFTER sibling
# `runtime.sh` (sidecar paths, adapter registry) and `costs.sh` (snapshot
# schema). Bash 3.2 + POSIX awk.

# _resolve_valid <in> <cc> <cr> <out> <model> <cost> <source>
#   Reject anything that is not the documented shape, so a broken adapter can
#   never write a shaped-but-false snapshot.
_resolve_valid() {
    local v
    for v in "$1" "$2" "$3" "$4"; do
        case "$v" in
            -) ;;
            ''|*[!0-9]*) return 1 ;;
        esac
    done
    [ -n "$5" ] || return 1
    case "$6" in
        -|[0-9]*) ;;
        *) return 1 ;;
    esac
    case "$6" in
        *[!0-9.-]*) return 1 ;;
    esac
    case " harness-feed session-file server manual " in
        *" $7 "*) ;;
        *) return 1 ;;
    esac
    return 0
}

# _resolve_harness_for <sidecar-basename>
#   Map `<harness>-<session>` back to its harness by longest match against the
#   registered adapter names (harness names contain hyphens, so a plain split
#   would be ambiguous). Prints `<harness>\t<session>`, or nothing.
_resolve_harness_for() {
    local base="$1" name best="" rest=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$base" in
            "$name"-*)
                if [ ${#name} -gt ${#best} ]; then
                    best="$name"
                    rest="${base#"$name"-}"
                fi
                ;;
        esac
    done < <(adapter_names)
    [ -n "$best" ] || return 1
    printf '%s\t%s\n' "$best" "$rest"
}

# resolve_candidates  → `<harness>\t<session>\t<declared>` for every session
#   this worktree knows about, most authoritative first:
#     1. the session the ENVIRONMENT is announcing right now — the sweep runs
#        inside that session (post-commit / pre-push), so this is the one
#        candidate that needs no file to exist at all. Without it a harness
#        whose emitter is not wired would never resolve, because nothing would
#        ever create the first sidecar.
#     2. the identity file, whatever its age — a stale identity still names a
#        real session worth measuring; the trust window governs ATTRIBUTION at
#        commit time, not whether an old session may still be read.
#     3. every existing sidecar, mapped back to its harness by the registry.
#   Deduplicated in that order, so the richest declared path wins.
resolve_candidates() {
    local seen=$'\n' h s d dir f base pair
    if detect_runtime_identity; then
        seen="$seen$RUNTIME/$SESSION_ID"$'\n'
        printf '%s\t%s\t%s\n' "$RUNTIME" "$SESSION_ID" "$DECLARED"
    fi
    h="$(identity_get harness)"
    s="$(identity_get session)"
    d="$(identity_get declared)"
    if [ -n "$h" ]; then
        [ -n "$s" ] || s="-"
        case "$seen" in
            *$'\n'"$h/$s"$'\n'*) ;;
            *)
                seen="$seen$h/$s"$'\n'
                printf '%s\t%s\t%s\n' "$h" "$s" "$d"
                ;;
        esac
    fi
    dir="$(sidecar_dir)" || return 0
    [ -d "$dir" ] || return 0
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        pair="$(_resolve_harness_for "$base")" || continue
        h="${pair%%$'\t'*}"
        s="${pair#*$'\t'}"
        case "$seen" in
            *$'\n'"$h/$s"$'\n'*) continue ;;
        esac
        seen="$seen$h/$s"$'\n'
        printf '%s\t%s\t\n' "$h" "$s"
    done
}

# resolve_session <harness> <session> [<declared>]
#   Ask one adapter to measure one session and append the snapshot it reports.
#   Returns 0 only when a snapshot was appended.
resolve_session() {
    local harness="$1" session="$2" declared="${3:-}"
    local adapter out file
    local inp cc cr out_t model cost src

    [ -n "$harness" ] || return 1
    adapter="$(adapter_for "$harness")" || return 1
    out="$(bash "$adapter" resolve "$session" "$declared" 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    read -r inp cc cr out_t model cost src <<EOF
$out
EOF
    _resolve_valid "$inp" "$cc" "$cr" "$out_t" "$model" "$cost" "$src" || return 1
    file="$(sidecar_file "$harness" "$session")" || return 1
    costs_snapshot_append "$file" "$inp" "$cc" "$cr" "$out_t" "$model" "$cost" "$src"
}

# resolve_sweep
#   Resolve every candidate session. Never fails: a harness with no adapter, no
#   readable surface, or a broken adapter simply contributes nothing. Sets
#   RESOLVE_ATTEMPTED / RESOLVE_UPDATED for callers that want to say something.
resolve_sweep() {
    RESOLVE_ATTEMPTED=0
    RESOLVE_UPDATED=0
    local h s d
    while IFS=$'\t' read -r h s d; do
        [ -n "$h" ] || continue
        RESOLVE_ATTEMPTED=$(( RESOLVE_ATTEMPTED + 1 ))
        if resolve_session "$h" "$s" "$d"; then
            RESOLVE_UPDATED=$(( RESOLVE_UPDATED + 1 ))
        fi
    done <<EOF
$(resolve_candidates)
EOF
    return 0
}

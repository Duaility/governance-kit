#!/usr/bin/env bash
# Agent steering accounting — pre-commit hook.
#
# Walks the active agent runtime's session JSONL, extracts steering events
# (interrupts, classifier-confirmed corrections), and appends one row per
# *new* event to STEERING.md. `git add`s the ledger so the rows land in
# this commit's tree, then writes a handoff env file for prepare-commit-msg
# to stamp matching summary + Steer-Key trailers from.
#
# Always-on contract: when a runtime + transcript are detected, the handoff
# is written even on commits with zero new events. prepare-commit-msg then
# stamps `Steer-Count: 0` / `Steer-Types: none` / `Steer-Tiers: none` so an
# agent-authored commit is never silent — a `git log`-skimmable assertion
# that the directive ran and saw nothing. Commits authored outside a
# recognised runtime stay silent (no handoff, no trailers).
#
# Why pre-commit, not prepare-commit-msg: by the time prepare-commit-msg
# runs, git has already snapshotted the tree. `git add` from there lands
# in the next commit's index, not this one. Same shape as
# agent-token-accounting/hooks/pre-commit.sh.
#
# Dedup: the extractor returns *every* event on the session. We skip the
# first N, where N is the count of rows already in STEERING.md for this
# session. Append-only ordering of the ledger plus the JSONL's chronological
# order makes this exact.
#
# Bash 3.2 compatible — no associative arrays, no namerefs. macOS ships
# bash 3.2.x at /bin/bash, and `#!/usr/bin/env bash` resolves to it on a
# default install. Per-type / per-tier counts use newline-separated
# accumulators folded by `sort | uniq -c` at format time.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git commit ...
#   git commit --no-verify

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

# ── Detect runtime ─────────────────────────────────────────────
RUNTIME=""
if [[ "${CLAUDECODE:-}" == "1" ]]; then
    RUNTIME="claude-code"
fi
# Codex / other runtimes: future runtimes/<name>.sh adapters will land here.

# Not in an agent-runtime session — silently no-op. This directive does
# not block human-only commits.
[[ -z "$RUNTIME" ]] && exit 0

ROOT="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "$0")" && pwd)"
RULE_DIR="$(cd "$HERE/.." && pwd)"
LEDGER="$ROOT/STEERING.md"
LIB="$RULE_DIR/lib"
RUNTIMES="$RULE_DIR/runtimes"
HANDOFF="$(git rev-parse --git-path governance-pending-steering.env)"

# ── Resolve the transcript ─────────────────────────────────────
case "$RUNTIME" in
    claude-code)
        if ! out="$("$RUNTIMES/claude-code.sh")"; then
            # No transcript — silent no-op (e.g. session id changed mid-commit).
            exit 0
        fi
        read -r SESSION_ID TRANSCRIPT <<<"$out"
        AGENT_NAME="claude-code"
        ;;
    *)
        exit 0
        ;;
esac

# ── Walk argv to recover the issue anchor ─────────────────────
# Same trick as agent-token-accounting: $PPID is the hook process; git is
# its grandparent (typically), so walk one more level. Optional — empty
# `Issue` cell is allowed in the schema for repos that don't enforce
# anchors.
grandparent_pid() {
    local pid="$PPID"
    if [[ -r "/proc/$pid/status" ]]; then
        awk '/^PPid:/ {print $2}' "/proc/$pid/status"
    else
        ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' '
    fi
}

parent_argv_string() {
    local pid="$1"
    if [[ -r "/proc/$pid/cmdline" ]]; then
        tr '\0' ' ' < "/proc/$pid/cmdline"
    else
        ps -ww -p "$pid" -o args= 2>/dev/null
    fi
}

GIT_PID="$(grandparent_pid)"
ARGV="$(parent_argv_string "${GIT_PID:-$PPID}")"
if [[ "$ARGV" != *git* ]]; then
    ARGV="$(parent_argv_string "$PPID")"
fi

ISSUE="${AGENT_ISSUE:-}"
if [[ -z "$ISSUE" && "$ARGV" =~ \(#([1-9][0-9]*)\) ]]; then
    ISSUE="#${BASH_REMATCH[1]}"
fi

# Capture a short subject for the `commit` cell.
SUBJECT=""
if [[ "$ARGV" =~ [[:space:]](-m|--message)[[:space:]]+(.+) ]]; then
    SUBJECT="${BASH_REMATCH[2]}"
elif [[ "$ARGV" =~ --message=(.+) ]]; then
    SUBJECT="${BASH_REMATCH[1]}"
fi

# ── Run the extractor ─────────────────────────────────────────
# Tier-2 (corrections) is on by default — the directive itself is opt-in
# at install time, so no further env-var gates inside it. The extractor
# shells out to the active runtime's headless CLI (`claude -p` or
# `codex exec`) for semantic classification, falling back to a regex
# pre-filter only when the CLI is unreachable. Verdicts are cached by
# message-pair hash so re-runs are deterministic.
CLASSIFIER_CACHE="$(git rev-parse --git-path agent-steering-classify-cache.json)"

# Extractor emits TSV: timestamp\ttype\ttier\tuser_reason
ALL_EVENTS="$(mktemp)"
trap 'rm -f "$ALL_EVENTS"' EXIT

if ! python3 "$LIB/extract.py" "$TRANSCRIPT" --cache "$CLASSIFIER_CACHE" > "$ALL_EVENTS"; then
    # Extractor failure shouldn't block a commit — log and move on.
    echo "agent-steering-accounting: extractor failed; skipping" >&2
    exit 0
fi

TOTAL_EVENTS="$(wc -l < "$ALL_EVENTS" | tr -d ' ')"

# Count rows already in STEERING.md for this session — the dedup boundary.
EXISTING_ROWS=0
if [[ -f "$LEDGER" ]]; then
    EXISTING_ROWS="$(awk -F'|' -v sid="$SESSION_ID" '
        /^\|/ {
            key = $2
            sess = $3
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            gsub(/^[ \t]+|[ \t]+$/, "", sess)
            if (key == "steer-key" || key == "" || key ~ /^-+$/) next
            if (sess == sid) c++
        }
        END { print c+0 }
    ' "$LEDGER")"
fi

# New events to append: lines after the first $EXISTING_ROWS. May be zero.
NEW_EVENTS_COUNT=$(( TOTAL_EVENTS - EXISTING_ROWS ))
if (( NEW_EVENTS_COUNT < 0 )); then
    # Defensive — extractor returned fewer events than the ledger already
    # has for this session. Treat as a no-op and let check.sh surface it.
    NEW_EVENTS_COUNT=0
fi

# ── Append rows ────────────────────────────────────────────────
EPOCH="$(date +%s)"
SESSION_SHORT="${SESSION_ID:0:12}"
SESSION_SHORT="${SESSION_SHORT//[^A-Za-z0-9]/}"
[[ -z "$SESSION_SHORT" ]] && SESSION_SHORT="anon"

# Track keys + per-type / per-tier values. bash 3.2 has no associative
# arrays, so we collect each event's type / tier into newline-separated
# accumulators and let `sort | uniq -c` fold them at format time.
KEYS_LIST=""
TYPES_RAW=""
TIERS_RAW=""

if (( NEW_EVENTS_COUNT > 0 )); then
    idx=0
    while IFS=$'\t' read -r ts typ tier user_reason; do
        idx=$(( idx + 1 ))
        STEER_KEY="steer-${SESSION_SHORT}-${EPOCH}-${idx}"

        # `-` is the extractor's empty sentinel; map back to "" for the ledger
        # (which has its own sanitizer).
        [[ "$user_reason" == "-" ]] && user_reason=""

        if ! python3 "$LIB/ledger.py" append-row \
            "$LEDGER" \
            "$STEER_KEY" "$SESSION_ID" "$ISSUE" \
            "$typ" "$tier" "$user_reason" \
            "$SUBJECT"; then
            echo "agent-steering-accounting: append-row failed; aborting" >&2
            exit 1
        fi
        KEYS_LIST="${KEYS_LIST}${STEER_KEY}"$'\n'
        TYPES_RAW="${TYPES_RAW}${typ}"$'\n'
        TIERS_RAW="${TIERS_RAW}${tier}"$'\n'
    done < <(tail -n "$NEW_EVENTS_COUNT" "$ALL_EVENTS")

    git add "$LEDGER"
fi

# Format raw newline-separated values into `key=N,key=N` (sorted for
# determinism — squash-merge rebases shouldn't reorder them). Empty input
# maps to "none".
format_counts() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        printf 'none'
        return
    fi
    printf '%s' "$raw" \
        | awk 'NF { print }' \
        | sort \
        | uniq -c \
        | awk 'BEGIN { sep="" } { printf("%s%s=%s", sep, $2, $1); sep="," } END { print "" }'
}

TYPES_SUMMARY="$(format_counts "$TYPES_RAW")"
TIERS_SUMMARY="$(format_counts "$TIERS_RAW")"

# ── Hand off to prepare-commit-msg ────────────────────────────
# Always written when a runtime + transcript are detected, even on
# zero-event commits. prepare-commit-msg uses the count + summary fields
# to stamp the always-on summary trailers and walks KEYS to emit per-event
# Steer-Key trailers (zero lines on a no-event commit).
{
    printf "AGENT_STEERING_COUNT='%s'\n" "$NEW_EVENTS_COUNT"
    printf "AGENT_STEERING_TYPES='%s'\n" "$TYPES_SUMMARY"
    printf "AGENT_STEERING_TIERS='%s'\n" "$TIERS_SUMMARY"
    printf "AGENT_STEERING_KEYS='"
    printf '%s' "$KEYS_LIST"
    printf "'\n"
} > "$HANDOFF"

printf 'agent-steering: runtime=%s session=%s new=%d total=%d\n' \
    "$RUNTIME" "$SESSION_ID" "$NEW_EVENTS_COUNT" "$TOTAL_EVENTS" >&2

exit 0

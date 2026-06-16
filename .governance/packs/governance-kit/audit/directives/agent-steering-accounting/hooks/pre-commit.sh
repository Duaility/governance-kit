#!/usr/bin/env bash
# Agent steering accounting — pre-commit hook.
#
# Walks the active agent runtime's session JSONL, extracts steering events
# (interrupts, classifier-confirmed corrections), and appends one row per
# *new* event to the issue's receipt. `git add`s the ledger so the rows land
# in this commit's tree. This is a side-effect hook only — issue #293 retired
# the summary trailers, so there is no longer a handoff or a prepare-commit-msg
# stamp; check.sh validates the resulting ledger shape.
#
# Why pre-commit, not a later hook: pre-commit runs before git snapshots the
# tree, so the `git add` of the receipt rows lands in the CURRENT commit. From
# a post-snapshot hook it would land in the next commit's index. Same shape as
# agent-token-accounting/hooks/pre-commit.sh.
#
# Dedup (issue #229): the extractor returns *every* event on the session; we
# append only those whose (session, ordinal) identity isn't already recorded.
# Best-effort by design — a transient extractor failure logs and exits 0
# rather than blocking the commit.
#
# Bash 3.2 compatible — no associative arrays, no namerefs. macOS ships
# bash 3.2.x at /bin/bash, and `#!/usr/bin/env bash` resolves to it on a
# default install.
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

# Not in an agent-runtime session — pre-commit is a no-op (no transcript to
# extract events from, no rows to append). A human / manual commit records no
# steering; check.sh still validates whatever rows already exist.
[[ -z "$RUNTIME" ]] && exit 0

ROOT="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "$0")" && pwd)"
RULE_DIR="$(cd "$HERE/.." && pwd)"
# Steering rows live in per-issue receipts (issue #201). The receipt is
# resolved from the issue anchor once events are known to need homing.
RECEIPTS_DIR="$ROOT/receipts"
LIB="$RULE_DIR/lib"
RUNTIMES="$RULE_DIR/runtimes"

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
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS `ps -o args=` cat-v-escapes bytes >= 0x80 under LC_ALL=C
        # (the locale git hooks usually run with), which mangles UTF-8 in
        # the commit subject before it ever reaches the regex. Read raw
        # argv bytes via sysctl(KERN_PROCARGS2) so non-ASCII subjects
        # survive intact. See issue #140.
        python3 "$LIB/argv.py" "$pid" 2>/dev/null | tr '\0' ' '
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

# Extractor emits TSV: ordinal\ttimestamp\ttype\ttier\tuser_reason
ALL_EVENTS="$(mktemp)"
EXISTING_ORD="$(mktemp)"
NEW_EVENTS="$(mktemp)"
trap 'rm -f "$ALL_EVENTS" "$EXISTING_ORD" "$NEW_EVENTS"' EXIT

if ! python3 "$LIB/extract.py" "$TRANSCRIPT" --cache "$CLASSIFIER_CACHE" > "$ALL_EVENTS"; then
    # Extractor failure shouldn't block a commit — log and move on.
    echo "agent-steering-accounting: extractor failed; skipping" >&2
    exit 0
fi

TOTAL_EVENTS="$(wc -l < "$ALL_EVENTS" | tr -d ' ')"

# Identity dedup (issue #229): an event is new iff its (session, ordinal) isn't
# already recorded — not "after the first N rows". The old positional scheme
# re-appended and misattributed events across branches in the same session; the
# ordinal makes dedup an identity test and the duplicate detectable post-merge.
python3 "$LIB/ledger.py" existing-ordinals "$RECEIPTS_DIR" "$SESSION_ID" > "$EXISTING_ORD"
if [[ -s "$EXISTING_ORD" ]]; then
    # Keep events whose ordinal (TSV col 1) is not already recorded.
    awk -F'\t' 'NR==FNR { seen[$1]=1; next } !($1 in seen)' \
        "$EXISTING_ORD" "$ALL_EVENTS" > "$NEW_EVENTS"
else
    cp "$ALL_EVENTS" "$NEW_EVENTS"
fi
NEW_EVENTS_COUNT="$(wc -l < "$NEW_EVENTS" | tr -d ' ')"

# ── Attribution gate (issue #201, decision 6) ─────────────────
# Every accounted event must resolve to an issue — receipts are per-issue, so
# an issue-less event has no home and a catch-all file would reintroduce the
# central ledger this design retires. Refuse to write events we cannot
# attribute; zero-event commits don't need an issue (nothing to home).
if (( NEW_EVENTS_COUNT > 0 )) && [[ -z "$ISSUE" ]]; then
    cat >&2 <<EOF

────────────────────────────────────────
✗ Agent commit blocked by agent-steering-accounting.

Detected $NEW_EVENTS_COUNT new steering event(s) but no issue anchor to
attribute them to. Steering rows live in the issue's receipt; an event with
no issue has nowhere to land.

Pass '(#N)' in the subject:
    git commit -m "fix: thing (#123)"

Or set AGENT_ISSUE explicitly:
    AGENT_ISSUE='#123' git commit
────────────────────────────────────────
EOF
    exit 1
fi

# Resolve the receipt these rows belong in (only meaningful with an issue).
RECEIPT=""
if [[ -n "$ISSUE" ]]; then
    RECEIPT="$(python3 "$LIB/ledger.py" resolve-receipt "$RECEIPTS_DIR" "$ISSUE")"
fi

# ── Append rows ────────────────────────────────────────────────
EPOCH="$(date +%s)"
SESSION_SHORT="${SESSION_ID:0:12}"
SESSION_SHORT="${SESSION_SHORT//[^A-Za-z0-9]/}"
[[ -z "$SESSION_SHORT" ]] && SESSION_SHORT="anon"

if (( NEW_EVENTS_COUNT > 0 )); then
    mkdir -p "$RECEIPTS_DIR"
    idx=0
    while IFS=$'\t' read -r ordinal ts typ tier user_reason; do
        idx=$(( idx + 1 ))
        STEER_KEY="steer-${SESSION_SHORT}-${EPOCH}-${idx}"

        # `-` is the extractor's empty sentinel; map back to "" for the ledger
        # (which has its own sanitizer). `ordinal` is always a positive integer.
        [[ "$user_reason" == "-" ]] && user_reason=""
        [[ "$ts" == "-" ]] && ts=""

        if ! python3 "$LIB/ledger.py" append-row \
            "$RECEIPT" \
            "$STEER_KEY" "$SESSION_ID" "$ISSUE" \
            "$typ" "$tier" "$user_reason" \
            "$SUBJECT" "$ordinal" "$ts"; then
            echo "agent-steering-accounting: append-row failed; aborting" >&2
            exit 1
        fi
    done < "$NEW_EVENTS"

    git add "$RECEIPT"
fi

printf 'agent-steering: runtime=%s session=%s new=%d total=%d\n' \
    "$RUNTIME" "$SESSION_ID" "$NEW_EVENTS_COUNT" "$TOTAL_EVENTS" >&2

exit 0

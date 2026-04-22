#!/usr/bin/env bash
# Claude Code commit wrapper — extracts token metrics from the live session
# transcript, populates the AGENT_* contract, and execs `git commit`.
#
# Why this exists: Claude Code does not currently export a session id or a
# running token tally to the Bash tool's environment. The session transcript
# on disk does carry both, so this wrapper reads it.
#
# Usage (from inside a Claude Code session):
#   scripts/claude-code-commit.sh -m "feat: add foo (#13)"
#
# Environment overrides:
#   CLAUDE_TRANSCRIPT_PATH   absolute path to the session JSONL (skip discovery)
#   CLAUDE_PROJECTS_DIR      override ~/.claude/projects
#   AGENT_NAME               override the default "claude-code"
#   AGENT_ISSUE              override issue inference from the subject
#
# Token math:
#   input  = sum(input_tokens + cache_creation_input_tokens + cache_read_input_tokens)
#   output = sum(output_tokens)
#   summed across all assistant entries in the transcript that match sessionId.
#
# Per-commit delta, not cumulative: we subtract the sum of existing COSTS.md
# rows whose `session` column matches this session id. That way a session that
# produces N commits has N rows whose sum equals the session's total spend.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}"

encode_path() {
    # Replace every `/` and `.` with `-`, matching Claude Code's project-dir convention.
    printf '%s' "$1" | sed -E 's#[/.]#-#g'
}

# ── Locate the transcript ──────────────────────────────────────
TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"
if [[ -z "$TRANSCRIPT" ]]; then
    encoded="$(encode_path "$REPO_ROOT")"
    dir="$CLAUDE_PROJECTS/$encoded"
    if [[ ! -d "$dir" ]]; then
        # Fall back to $PWD encoding in case the session was launched from a subdir.
        encoded="$(encode_path "$PWD")"
        dir="$CLAUDE_PROJECTS/$encoded"
    fi
    if [[ -d "$dir" ]]; then
        # Most recently modified JSONL wins — Claude Code writes transcript
        # events in real time, so the active session is the most recent file.
        TRANSCRIPT="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -n1)"
    fi
fi

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
    cat >&2 <<EOF
✗ Could not locate a Claude Code session transcript.
  Searched under: ${CLAUDE_PROJECTS}/$(encode_path "$REPO_ROOT")/
  Override with:  CLAUDE_TRANSCRIPT_PATH=/abs/path/session.jsonl scripts/claude-code-commit.sh ...
EOF
    exit 1
fi

# ── Sum tokens from the transcript ─────────────────────────────
read -r SESSION_ID CUM_INPUT CUM_OUTPUT < <(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
sid = None
tin = 0
tout = 0
with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        if sid is None and d.get("sessionId"):
            sid = d["sessionId"]
        msg = d.get("message") if isinstance(d.get("message"), dict) else None
        if not msg:
            continue
        usage = msg.get("usage")
        if not isinstance(usage, dict):
            continue
        tin  += int(usage.get("input_tokens", 0) or 0)
        tin  += int(usage.get("cache_creation_input_tokens", 0) or 0)
        tin  += int(usage.get("cache_read_input_tokens", 0) or 0)
        tout += int(usage.get("output_tokens", 0) or 0)
print(f"{sid or 'unknown'} {tin} {tout}")
PY
)

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "unknown" ]]; then
    echo "✗ Could not extract sessionId from transcript: $TRANSCRIPT" >&2
    exit 1
fi

# ── Subtract tokens already accounted for in COSTS.md ──────────
LEDGER="$REPO_ROOT/COSTS.md"
PREV_INPUT=0
PREV_OUTPUT=0
if [[ -f "$LEDGER" ]]; then
    # Match rows whose `session` (column 3) equals this session id.
    # Awk sums columns 5 (input) and 6 (output).
    read -r PREV_INPUT PREV_OUTPUT < <(
        awk -F'|' -v sid="$SESSION_ID" '
            /^[[:space:]]*\|/ {
                n = split($0, c, "|")
                if (n < 9) next
                for (i = 2; i <= 8; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", c[i])
                if (c[2] == "cost-key" || c[2] ~ /^-+$/ || c[2] == "") next
                if (c[3] != sid) next
                tin  += c[5] + 0
                tout += c[6] + 0
            }
            END { print (tin+0) " " (tout+0) }
        ' "$LEDGER"
    )
fi

TOKEN_INPUT=$(( CUM_INPUT - PREV_INPUT ))
TOKEN_OUTPUT=$(( CUM_OUTPUT - PREV_OUTPUT ))

# Clamp to zero — transcripts can be rewritten / session resumed / rows
# manually edited. Negative delta would fail the rule's integer check and
# isn't useful; zero is the honest floor.
(( TOKEN_INPUT  < 0 )) && TOKEN_INPUT=0
(( TOKEN_OUTPUT < 0 )) && TOKEN_OUTPUT=0

export AGENT_NAME="${AGENT_NAME:-claude-code}"
export AGENT_SESSION_ID="$SESSION_ID"
export AGENT_TOKEN_INPUT="$TOKEN_INPUT"
export AGENT_TOKEN_OUTPUT="$TOKEN_OUTPUT"
[[ -n "${AGENT_ISSUE:-}" ]] && export AGENT_ISSUE

printf 'claude-code-commit: session=%s input=+%d output=+%d (cumulative %d/%d)\n' \
    "$SESSION_ID" "$TOKEN_INPUT" "$TOKEN_OUTPUT" "$CUM_INPUT" "$CUM_OUTPUT" >&2

exec git commit "$@"

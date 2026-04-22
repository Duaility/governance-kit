#!/usr/bin/env bash
# Claude Code commit wrapper. Discovers the session transcript, sums token
# usage, exports the cumulative values, and hands off to governance-commit.sh.
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

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
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
# Claude-Code-specific schema: every `assistant` entry has a
# `.message.usage` object. Input tokens count regular + cache-creation +
# cache-read so the number matches billed usage regardless of cache state.
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

# ── Hand off to the shared helper ─────────────────────────────
export AGENT_NAME="${AGENT_NAME:-claude-code}"
export AGENT_SESSION_ID="$SESSION_ID"
export AGENT_CUM_INPUT="$CUM_INPUT"
export AGENT_CUM_OUTPUT="$CUM_OUTPUT"

exec "$HERE/governance-commit.sh" "$@"

#!/usr/bin/env bash
# Claude Code transcript reader.
#
# Output on success (one line to stdout):
#   <session_id> <cum_input> <cum_output>
# Exit non-zero if no transcript can be located.
#
# Environment overrides:
#   CLAUDE_TRANSCRIPT_PATH   absolute path to the session JSONL
#   CLAUDE_PROJECTS_DIR      override ~/.claude/projects

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}"

encode_path() {
    # Replace every `/` and `.` with `-`, matching Claude Code's project-dir convention.
    printf '%s' "$1" | sed -E 's#[/.]#-#g'
}

TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"
if [[ -z "$TRANSCRIPT" ]]; then
    for candidate in "$REPO_ROOT" "$PWD"; do
        dir="$CLAUDE_PROJECTS/$(encode_path "$candidate")"
        if [[ -d "$dir" ]]; then
            TRANSCRIPT="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -n1)"
            [[ -n "$TRANSCRIPT" ]] && break
        fi
    done
fi

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 1

# Input counts regular + cache-creation + cache-read so the number matches
# billed usage regardless of cache state.
python3 - "$TRANSCRIPT" <<'PY'
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
if sid is None:
    sys.exit(2)
print(f"{sid} {tin} {tout}")
PY

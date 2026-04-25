#!/usr/bin/env bash
# Claude Code transcript locator for agent-steering-accounting.
#
# Output on success (one line to stdout, space-separated):
#   <session_id> <transcript_path>
# Exit non-zero if no transcript can be located. The caller (pre-commit
# hook) reads the transcript via lib/extract.py to detect steering events.
#
# JSONL discovery mirrors agent-token-accounting/runtimes/claude-code.sh —
# Claude Code stores per-project session logs under
# ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl.
#
# Environment overrides:
#   CLAUDE_TRANSCRIPT_PATH   absolute path to the session JSONL
#   CLAUDE_PROJECTS_DIR      override ~/.claude/projects

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}"

encode_path() {
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

# Recover the session id from the first JSONL entry that carries one.
SESSION_ID="$(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("sessionId"):
            print(d["sessionId"])
            break
PY
)"

[[ -z "$SESSION_ID" ]] && exit 2

printf '%s %s\n' "$SESSION_ID" "$TRANSCRIPT"

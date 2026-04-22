#!/usr/bin/env bash
# Codex transcript reader.
#
# Output on success (one line to stdout):
#   <session_id> <cum_input> <cum_output>
# Exit non-zero if no transcript can be located.
#
# Environment overrides:
#   CODEX_TRANSCRIPT_PATH   absolute path to the session JSONL
#   CODEX_SESSIONS_DIR      override ~/.codex/sessions
#   CODEX_THREAD_ID         the thread/session id (otherwise derived from filename)

set -u

CODEX_SESSIONS="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"

TRANSCRIPT="${CODEX_TRANSCRIPT_PATH:-}"
if [[ -z "$TRANSCRIPT" ]]; then
    if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
        candidate="$CODEX_SESSIONS/${CODEX_THREAD_ID}.jsonl"
        [[ -f "$candidate" ]] && TRANSCRIPT="$candidate"
    fi
    if [[ -z "$TRANSCRIPT" && -d "$CODEX_SESSIONS" ]]; then
        TRANSCRIPT="$(ls -t "$CODEX_SESSIONS"/*.jsonl 2>/dev/null | head -n1)"
    fi
fi

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 1

SESSION_ID="${CODEX_THREAD_ID:-}"
if [[ -z "$SESSION_ID" ]]; then
    base="$(basename "$TRANSCRIPT")"
    SESSION_ID="${base%.jsonl}"
fi
[[ -z "$SESSION_ID" ]] && exit 2

# Sum tokens across the common Codex transcript shapes — top-level `usage`,
# nested `message.usage`, `response.usage` — and both `input_tokens` /
# `output_tokens` and `prompt_tokens` / `completion_tokens` key pairs.
read -r CUM_INPUT CUM_OUTPUT < <(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
tin = 0
tout = 0

def pull(u):
    if not isinstance(u, dict):
        return 0, 0
    i = u.get("input_tokens")  or u.get("prompt_tokens")     or 0
    o = u.get("output_tokens") or u.get("completion_tokens") or 0
    try:
        return int(i or 0), int(o or 0)
    except (TypeError, ValueError):
        return 0, 0

with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        for container in (d,
                          d.get("message")  if isinstance(d.get("message"),  dict) else None,
                          d.get("response") if isinstance(d.get("response"), dict) else None):
            if container is None:
                continue
            u = container.get("usage") if container is not d else container.get("usage", container)
            i, o = pull(u if isinstance(u, dict) else {})
            if i or o:
                tin  += i
                tout += o
                break
print(f"{tin} {tout}")
PY
)

printf '%s %s %s\n' "$SESSION_ID" "${CUM_INPUT:-0}" "${CUM_OUTPUT:-0}"

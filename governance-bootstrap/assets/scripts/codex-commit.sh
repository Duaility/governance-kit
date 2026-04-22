#!/usr/bin/env bash
# Codex commit wrapper. Discovers the session transcript, sums token usage,
# and hands off to governance-commit.sh.
#
# Codex (the OpenAI CLI) writes session transcripts under ~/.codex/sessions/
# as JSONL, one file per thread. The exact field layout has shifted across
# Codex versions — this reader checks the common shapes: top-level `usage`,
# nested `message.usage`, and `response.usage`. If your Codex version stores
# tokens somewhere else, set CODEX_USAGE_JQ to a jq expression that maps a
# JSONL line to "<input> <output>" and this wrapper will use it instead.
#
# Usage (from inside a Codex session, or with CODEX_THREAD_ID exported):
#   scripts/codex-commit.sh -m "feat: add foo (#13)"
#
# Environment overrides:
#   CODEX_TRANSCRIPT_PATH   absolute path to the session JSONL (skip discovery)
#   CODEX_SESSIONS_DIR      override ~/.codex/sessions
#   CODEX_THREAD_ID         the thread/session id (required unless the
#                            transcript path is set and contains one event
#                            with a session id)
#   AGENT_NAME              override the default "codex"

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CODEX_SESSIONS="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"

# ── Locate the transcript ──────────────────────────────────────
TRANSCRIPT="${CODEX_TRANSCRIPT_PATH:-}"
if [[ -z "$TRANSCRIPT" ]]; then
    if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
        candidate="$CODEX_SESSIONS/${CODEX_THREAD_ID}.jsonl"
        [[ -f "$candidate" ]] && TRANSCRIPT="$candidate"
    fi
    if [[ -z "$TRANSCRIPT" && -d "$CODEX_SESSIONS" ]]; then
        # Fall back to the most recently modified session.
        TRANSCRIPT="$(ls -t "$CODEX_SESSIONS"/*.jsonl 2>/dev/null | head -n1)"
    fi
fi

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
    cat >&2 <<EOF
✗ Could not locate a Codex session transcript.
  Searched under: ${CODEX_SESSIONS}/
  Override with:  CODEX_TRANSCRIPT_PATH=/abs/path/thread.jsonl scripts/codex-commit.sh ...
  Or set CODEX_THREAD_ID to the thread id.
EOF
    exit 1
fi

# ── Resolve session id ─────────────────────────────────────────
SESSION_ID="${CODEX_THREAD_ID:-}"
if [[ -z "$SESSION_ID" ]]; then
    # Derive from filename (foo.jsonl → foo). Codex writes one file per thread.
    base="$(basename "$TRANSCRIPT")"
    SESSION_ID="${base%.jsonl}"
fi
if [[ -z "$SESSION_ID" ]]; then
    echo "✗ codex-commit: could not resolve session id" >&2
    exit 1
fi

# ── Sum tokens from the transcript ─────────────────────────────
read -r CUM_INPUT CUM_OUTPUT < <(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
tin = 0
tout = 0

def pull(d):
    if not isinstance(d, dict):
        return 0, 0
    for key in ("usage", None):
        u = d if key is None else d.get(key)
        if isinstance(u, dict):
            i = u.get("input_tokens") or u.get("prompt_tokens") or 0
            o = u.get("output_tokens") or u.get("completion_tokens") or 0
            try:
                return int(i or 0), int(o or 0)
            except (TypeError, ValueError):
                return 0, 0
    return 0, 0

with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        # Try top-level usage, then nested message.usage / response.usage.
        for container in (d, d.get("message") if isinstance(d.get("message"), dict) else None,
                             d.get("response") if isinstance(d.get("response"), dict) else None):
            if container is None:
                continue
            i, o = pull(container)
            if i or o:
                tin  += i
                tout += o
                break
print(f"{tin} {tout}")
PY
)

# ── Hand off to the shared helper ─────────────────────────────
export AGENT_NAME="${AGENT_NAME:-codex}"
export AGENT_SESSION_ID="$SESSION_ID"
export AGENT_CUM_INPUT="$CUM_INPUT"
export AGENT_CUM_OUTPUT="$CUM_OUTPUT"

exec "$HERE/governance-commit.sh" "$@"

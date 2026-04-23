#!/usr/bin/env bash
# Codex transcript reader.
#
# Output on success (one line to stdout, space-separated):
#   <session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model>
# Exit non-zero if no transcript can be located.
#
# Codex transcripts typically do not report prompt-cache fields (that's an
# Anthropic-API feature), so cache_create / cache_read come out as 0. Keeping
# the shape identical to claude-code.sh lets the caller treat all runtime
# readers uniformly.
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
# Also surface cache_creation / cache_read fields if the transcript happens
# to carry them (some Anthropic-via-Codex configurations do).
read -r CUM_INPUT CUM_CACHE_CREATE CUM_CACHE_READ CUM_OUTPUT MODEL < <(python3 - "$TRANSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
t_input = 0
t_cache_create = 0
t_cache_read = 0
t_output = 0
model = ""

def pull(u):
    """Return (input, cache_create, cache_read, output) from a usage dict."""
    if not isinstance(u, dict):
        return 0, 0, 0, 0
    i  = u.get("input_tokens")  or u.get("prompt_tokens")     or 0
    o  = u.get("output_tokens") or u.get("completion_tokens") or 0
    cc = u.get("cache_creation_input_tokens", 0) or 0
    cr = u.get("cache_read_input_tokens", 0) or 0
    try:
        return int(i or 0), int(cc or 0), int(cr or 0), int(o or 0)
    except (TypeError, ValueError):
        return 0, 0, 0, 0

with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        # Model can live at any of several places depending on transcript version.
        for container in (d, d.get("message"), d.get("response")):
            if isinstance(container, dict):
                m = container.get("model")
                if isinstance(m, str) and m:
                    model = m
                    break
        for container in (
            d,
            d.get("message")  if isinstance(d.get("message"),  dict) else None,
            d.get("response") if isinstance(d.get("response"), dict) else None,
        ):
            if container is None:
                continue
            u = container.get("usage") if container is not d else container.get("usage", container)
            i, cc, cr, o = pull(u if isinstance(u, dict) else {})
            if i or o or cc or cr:
                t_input        += i
                t_cache_create += cc
                t_cache_read   += cr
                t_output       += o
                break
print(f"{t_input} {t_cache_create} {t_cache_read} {t_output} {model or 'unknown'}")
PY
)

printf '%s %s %s %s %s %s\n' \
    "$SESSION_ID" "${CUM_INPUT:-0}" "${CUM_CACHE_CREATE:-0}" "${CUM_CACHE_READ:-0}" "${CUM_OUTPUT:-0}" "${MODEL:-unknown}"

#!/usr/bin/env bash
# Shared governance commit helper. Runtime-agnostic.
#
# A per-runtime wrapper (e.g. claude-code-commit.sh, codex-commit.sh) discovers
# the session id and cumulative token totals, then exec's this script with the
# original `git commit` args. This script does everything else: computes the
# per-commit delta, parses the issue anchor, builds the cost-key, appends the
# ledger row, stages COSTS.md, and finally exec's `git commit`.
#
# Why the wrappers don't do it themselves: the "append + stage BEFORE git
# commit" step is the non-obvious part that took a CI failure to discover, and
# every runtime needs it identically. Keeping it in one place keeps the
# per-runtime wrappers honest — they only implement the runtime-specific
# transcript reader.
#
# Env-var contract (set by the caller):
#   AGENT_NAME        required — "claude-code", "codex", etc.
#   AGENT_SESSION_ID  required — the runtime's session / thread id
#   AGENT_CUM_INPUT   required — session-cumulative input tokens
#   AGENT_CUM_OUTPUT  required — session-cumulative output tokens
#   AGENT_ISSUE       optional — "#123"; parsed from argv -m if unset
#   AGENT_COST_KEY    optional — override the default <agent>-<sess>-<epoch>

set -euo pipefail

require_var() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "✗ governance-commit: \$${name} must be set by the runtime wrapper" >&2
        exit 1
    fi
}
require_var AGENT_NAME
require_var AGENT_SESSION_ID
require_var AGENT_CUM_INPUT
require_var AGENT_CUM_OUTPUT

if ! [[ "$AGENT_CUM_INPUT" =~ ^[0-9]+$ && "$AGENT_CUM_OUTPUT" =~ ^[0-9]+$ ]]; then
    echo "✗ governance-commit: AGENT_CUM_INPUT/OUTPUT must be non-negative integers" >&2
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
LEDGER="$REPO_ROOT/COSTS.md"

# ── Prev-row subtraction for per-commit delta ──────────────────
# Column layout under `awk -F'|'` for a pipe-table row:
#   $1 empty | $2 cost-key | $3 agent | $4 session | $5 issue |
#   $6 input | $7 output   | $8 total | $9 note    | $10 empty
PREV_INPUT=0
PREV_OUTPUT=0
if [[ -f "$LEDGER" ]]; then
    read -r PREV_INPUT PREV_OUTPUT < <(
        awk -F'|' -v sid="$AGENT_SESSION_ID" '
            /^[[:space:]]*\|/ {
                n = split($0, c, "|")
                if (n < 9) next
                for (i = 2; i <= 8; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", c[i])
                if (c[2] == "cost-key" || c[2] ~ /^-+$/ || c[2] == "") next
                if (c[4] != sid) next
                tin  += c[6] + 0
                tout += c[7] + 0
            }
            END { print (tin+0) " " (tout+0) }
        ' "$LEDGER"
    )
fi

TOKEN_INPUT=$(( AGENT_CUM_INPUT  - PREV_INPUT  ))
TOKEN_OUTPUT=$(( AGENT_CUM_OUTPUT - PREV_OUTPUT ))
# Clamp to zero — transcripts can be rewritten / session resumed / rows edited.
(( TOKEN_INPUT  < 0 )) && TOKEN_INPUT=0
(( TOKEN_OUTPUT < 0 )) && TOKEN_OUTPUT=0
TOKEN_TOTAL=$(( TOKEN_INPUT + TOKEN_OUTPUT ))

# ── Parse issue from -m / --message / -F ──────────────────────
# The row goes into the current commit's tree, so we need the issue anchor
# before `git commit` runs. Editor-mode commits (no -m) require AGENT_ISSUE
# to be set explicitly.
ISSUE="${AGENT_ISSUE:-}"
SUBJECT=""
prev=""
for arg in "$@"; do
    case "$prev" in
        -m|--message) SUBJECT="$arg"; break ;;
        -F|--file)
            [[ -f "$arg" ]] && SUBJECT="$(grep -vE '^[[:space:]]*($|#)' "$arg" | head -n1)"
            break ;;
    esac
    case "$arg" in
        -m*)         [[ "$arg" != "-m" ]] && SUBJECT="${arg#-m}" ;;
        --message=*) SUBJECT="${arg#--message=}"; break ;;
    esac
    prev="$arg"
done
if [[ -z "$ISSUE" && "$SUBJECT" =~ \(#([1-9][0-9]*)\) ]]; then
    ISSUE="#${BASH_REMATCH[1]}"
fi
if [[ -z "$ISSUE" ]]; then
    echo "✗ governance-commit: could not infer issue — pass -m 'subject (#N)' or set AGENT_ISSUE='#N'" >&2
    exit 1
fi

# ── Compute cost-key ──────────────────────────────────────────
# Strip trailing dash/dot/underscore from the truncated session id so the
# key doesn't grow a double-dash on ids like "abc12345-6789-...".
SESSION_SHORT="${AGENT_SESSION_ID:0:12}"
SESSION_SHORT="${SESSION_SHORT%%[-._]}"
COST_KEY="${AGENT_COST_KEY:-${AGENT_NAME}-${SESSION_SHORT}-$(date +%s)}"

# ── Append the ledger row, create COSTS.md if missing ─────────
if [[ ! -f "$LEDGER" ]]; then
    cat > "$LEDGER" <<'LEDGER_EOF'
<!-- COSTS.md — append-only agent token-accounting ledger -->
<!-- governance: allow-plan-captured -->

# COSTS.md

Append-only ledger of token consumption for agent-authored commits. Rows are
keyed by `Cost-Key`, which survives squash merges. Do not rewrite or reorder
rows; this file is auditable history.

## Ledger

| cost-key | agent | session | issue | input | output | total | note |
| --- | --- | --- | --- | --- | --- | --- | --- |
LEDGER_EOF
fi

NOTE=$(printf '%s' "$SUBJECT" | tr -d '|' | cut -c 1-80)
printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$COST_KEY" "$AGENT_NAME" "$AGENT_SESSION_ID" "$ISSUE" \
    "$TOKEN_INPUT" "$TOKEN_OUTPUT" "$TOKEN_TOTAL" "$NOTE" \
    >> "$LEDGER"
git add "$LEDGER"

# ── Export the AGENT_* contract for prepare-commit-msg ────────
export AGENT_NAME
export AGENT_SESSION_ID
export AGENT_TOKEN_INPUT="$TOKEN_INPUT"
export AGENT_TOKEN_OUTPUT="$TOKEN_OUTPUT"
export AGENT_COST_KEY="$COST_KEY"
export AGENT_ISSUE="$ISSUE"

printf 'governance-commit: agent=%s session=%s input=+%d output=+%d (cumulative %d/%d) cost-key=%s\n' \
    "$AGENT_NAME" "$AGENT_SESSION_ID" "$TOKEN_INPUT" "$TOKEN_OUTPUT" \
    "$AGENT_CUM_INPUT" "$AGENT_CUM_OUTPUT" "$COST_KEY" >&2

exec git commit "$@"

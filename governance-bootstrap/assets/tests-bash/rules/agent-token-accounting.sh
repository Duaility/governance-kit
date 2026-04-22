#!/usr/bin/env bash
# Rule: Agent-authored commits carry full token-accounting trailers and a
# matching append-only row in COSTS.md.
#
# Required trailers on any commit whose message contains `Agent: <name>`:
#   Agent:         free-form runtime identifier (codex, claude-code, cursor, ...)
#   Issue:         #123 — the GitHub issue anchor
#   Session:       the runtime's session / thread id
#   Token-Input:   non-negative integer
#   Token-Output:  non-negative integer
#   Token-Total:   non-negative integer, == Token-Input + Token-Output
#   Cost-Key:      <agent>-<session-short>-<epoch>, unique within COSTS.md
#
# COSTS.md ledger format (one row per agent-authored commit, append-only):
#   | cost-key | agent | session | issue | input | output | total | note |
#
# Modes:
#   Mode A — commit-msg hook:  bash agent-token-accounting.sh <path-to-msg-file>
#   Mode B — CI / run.sh:      bash agent-token-accounting.sh
#       Walks default-branch merge-base → HEAD and validates every commit
#       that declares an Agent: trailer. Also validates COSTS.md shape
#       independently, so post-squash repos still get ledger integrity.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "agent-token-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
LEDGER="$ROOT/COSTS.md"
REQUIRED_TRAILERS=(Agent Issue Session Token-Input Token-Output Token-Total Cost-Key)

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

# Extract a trailer value from a commit message blob on stdin.
# Usage: echo "$msg" | trailer_value "Token-Input"
trailer_value() {
    local key="$1"
    awk -v k="^${key}:[[:space:]]*" 'tolower($0) ~ tolower(k) { sub(k, "", $0); print; exit }'
}

# Parse all ledger rows into "cost_key|agent|session|issue|input|output|total"
# Skips header, separator, and non-table lines.
ledger_rows() {
    [[ -f "$LEDGER" ]] || return 0
    awk -F'|' '
        /^[[:space:]]*\|/ {
            # Strip leading/trailing pipes, trim each cell.
            n = split($0, cells, "|")
            # cells[1] is empty (leading |), cells[n] is empty (trailing |).
            if (n < 9) next
            for (i = 2; i <= 8; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[i])
            }
            # Skip header row (literal "cost-key") and separator row (dashes only).
            if (cells[2] == "cost-key") next
            if (cells[2] ~ /^-+$/) next
            if (cells[2] == "") next
            print cells[2]"|"cells[3]"|"cells[4]"|"cells[5]"|"cells[6]"|"cells[7]"|"cells[8]
        }
    ' "$LEDGER"
}

validate_commit_message() {
    local msg="$1" label="$2"
    # If there is no Agent: trailer, this commit is not agent-authored — nothing to do.
    local agent
    agent=$(printf '%s\n' "$msg" | trailer_value "Agent")
    [[ -z "$agent" ]] && return 0

    local missing=()
    local values=()
    local k
    for k in "${REQUIRED_TRAILERS[@]}"; do
        local v
        v=$(printf '%s\n' "$msg" | trailer_value "$k")
        if [[ -z "$v" ]]; then
            missing+=("$k")
        fi
        values+=("$k=$v")
    done
    if (( ${#missing[@]} > 0 )); then
        violation "$label — declares Agent: '$agent' but is missing trailers: ${missing[*]}"
        return 1
    fi

    local input output total cost_key
    input=$(printf '%s\n' "$msg" | trailer_value "Token-Input")
    output=$(printf '%s\n' "$msg" | trailer_value "Token-Output")
    total=$(printf '%s\n' "$msg" | trailer_value "Token-Total")
    cost_key=$(printf '%s\n' "$msg" | trailer_value "Cost-Key")

    if ! [[ "$input" =~ ^[0-9]+$ && "$output" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ ]]; then
        violation "$label — Token-Input/Output/Total must be non-negative integers (got '$input', '$output', '$total')"
        return 1
    fi

    if (( input + output != total )); then
        violation "$label — Token-Total ($total) != Token-Input ($input) + Token-Output ($output)"
        return 1
    fi

    # Validate Cost-Key shape: <agent>-<session-short>-<epoch>
    if [[ ! "$cost_key" =~ ^[A-Za-z0-9._-]+$ ]]; then
        violation "$label — Cost-Key '$cost_key' contains invalid characters (allowed: A-Z a-z 0-9 . _ -)"
        return 1
    fi

    # Require a matching row in the ledger.
    if [[ ! -f "$LEDGER" ]]; then
        violation "$label — agent-authored commit but COSTS.md does not exist at repo root"
        return 1
    fi
    local matches
    matches=$(ledger_rows | awk -F'|' -v k="$cost_key" '$1 == k' | wc -l | tr -d ' ')
    if [[ "$matches" != "1" ]]; then
        violation "$label — Cost-Key '$cost_key' should have exactly 1 row in COSTS.md, found $matches"
        return 1
    fi

    # Cross-check: ledger row's totals must agree with trailers.
    local row
    row=$(ledger_rows | awk -F'|' -v k="$cost_key" '$1 == k')
    local row_input row_output row_total
    row_input=$(printf '%s' "$row" | awk -F'|' '{print $5}')
    row_output=$(printf '%s' "$row" | awk -F'|' '{print $6}')
    row_total=$(printf '%s' "$row" | awk -F'|' '{print $7}')
    if [[ "$row_input" != "$input" || "$row_output" != "$output" || "$row_total" != "$total" ]]; then
        violation "$label — COSTS.md row for '$cost_key' disagrees with commit trailers (row: $row_input/$row_output/$row_total, trailers: $input/$output/$total)"
        return 1
    fi

    return 0
}

# ──────────────────────────────────────────────────────────────
# Ledger-integrity check — runs unconditionally. This is the
# post-squash safety net: even when branch commits disappear,
# COSTS.md stays in history.
# ──────────────────────────────────────────────────────────────
if [[ -f "$LEDGER" ]]; then
    # Duplicate Cost-Key detection — uses a sorted|uniq pipe so we stay
    # compatible with Bash 3.2 (macOS default), which lacks associative arrays.
    while IFS= read -r dup_key; do
        [[ -z "$dup_key" ]] && continue
        violation "COSTS.md — Cost-Key '$dup_key' appears more than once (must be unique, append-only)"
    done < <(ledger_rows | awk -F'|' '{print $1}' | sort | uniq -d)

    while IFS='|' read -r k agent session issue input output total; do
        [[ -z "$k" ]] && continue

        if ! [[ "$input" =~ ^[0-9]+$ && "$output" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ ]]; then
            violation "COSTS.md — row '$k' has non-integer token counts ($input/$output/$total)"
            continue
        fi
        if (( input + output != total )); then
            violation "COSTS.md — row '$k' has Total=$total but Input+Output=$((input + output))"
        fi

        if [[ -z "$agent" || -z "$session" || -z "$issue" ]]; then
            violation "COSTS.md — row '$k' has empty agent/session/issue field"
        fi
        if [[ ! "$issue" =~ ^\#[1-9][0-9]*$ ]]; then
            violation "COSTS.md — row '$k' issue '$issue' must look like '#123'"
        fi
    done < <(ledger_rows)
fi

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        rule_end
    fi
    msg=$(cat "$msg_file")
    validate_commit_message "$msg" "pending commit"
    rule_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh — walk base..HEAD
# ──────────────────────────────────────────────────────────────
base=""
for candidate in origin/main origin/master main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
        mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
        if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD)" ]]; then
            base="$mb"
            break
        fi
    fi
done

if [[ -z "$base" ]]; then
    # Fall back to validating HEAD alone so the rule still exercises.
    msg=$(git log -1 --format=%B HEAD 2>/dev/null || echo "")
    [[ -n "$msg" ]] && validate_commit_message "$msg" "HEAD"
    rule_end
fi

while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    msg=$(git log -1 --format=%B "$sha")
    validate_commit_message "$msg" "$sha"
done < <(git log "$base..HEAD" --format='%H')

rule_end

#!/usr/bin/env bash
# Rule: AGENTS.md exists at the repo root and functions as an index (not a manual).
# Rationale: The harness-engineering pattern — a brief, link-heavy entry point for
# agents that points at deeper docs. Enforcing size keeps it from drifting into a
# god-file that nobody reads.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "agents-md-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
FILE="$ROOT/AGENTS.md"

if [[ ! -f "$FILE" ]]; then
    violation "AGENTS.md not found at repo root"
    rule_end
fi

lines=$(wc -l < "$FILE" | tr -d ' ')
MIN_LINES="${GOVERNANCE_AGENTS_MD_MIN:-30}"
MAX_LINES="${GOVERNANCE_AGENTS_MD_MAX:-250}"

if [[ $lines -lt $MIN_LINES ]]; then
    violation "AGENTS.md has $lines lines — looks like a stub (min: $MIN_LINES)"
fi

if [[ $lines -gt $MAX_LINES ]]; then
    violation "AGENTS.md has $lines lines — drifting toward a manual (max: $MAX_LINES). Move detail into linked docs."
fi

# It's an *index*, so it must actually link to other repo files.
# Count markdown links to local paths (not http/https/mailto).
link_count=$(grep -oE '\]\([^)]+\)' "$FILE" 2>/dev/null \
    | grep -cvE '\((https?://|mailto:|tel:|#)' 2>/dev/null || true)
link_count="${link_count:-0}"
MIN_LINKS="${GOVERNANCE_AGENTS_MD_MIN_LINKS:-3}"
if [[ $link_count -lt $MIN_LINKS ]]; then
    violation "AGENTS.md has $link_count internal links — an index should link out (min: $MIN_LINKS)"
fi

rule_end

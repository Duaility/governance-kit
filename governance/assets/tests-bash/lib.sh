#!/usr/bin/env bash
# Shared helpers for governance rule tests.
# Source this from every rule file: `source "$(dirname "$0")/../lib.sh"`

set -u

# Color output only when stdout is a terminal.
if [[ -t 1 ]]; then
    readonly C_RED=$'\033[31m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RESET=$'\033[0m'
else
    readonly C_RED=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_BOLD=""
    readonly C_RESET=""
fi

# Track violations for the current rule. Each rule should call `rule_start`
# at the top, then `violation` for each problem found, then `rule_end` at the
# bottom. `rule_end` exits 0 if no violations, 1 otherwise.
_RULE_NAME=""
_VIOLATION_COUNT=0
_VIOLATIONS=()

rule_start() {
    _RULE_NAME="$1"
    _VIOLATION_COUNT=0
    _VIOLATIONS=()
}

violation() {
    _VIOLATION_COUNT=$((_VIOLATION_COUNT + 1))
    _VIOLATIONS+=("$1")
}

rule_end() {
    if [[ $_VIOLATION_COUNT -eq 0 ]]; then
        printf "%s✓%s %s\n" "$C_GREEN" "$C_RESET" "$_RULE_NAME"
        exit 0
    fi
    printf "%s✗ %s%s (%d violation%s)\n" "$C_RED" "$_RULE_NAME" "$C_RESET" \
        "$_VIOLATION_COUNT" "$([[ $_VIOLATION_COUNT -eq 1 ]] || echo s)"
    for v in "${_VIOLATIONS[@]}"; do
        printf "    %s\n" "$v"
    done
    exit 1
}

# Emit tracked files (respects .gitignore), optionally filtered by a pathspec.
# Usage: tracked_files                → all tracked files
#        tracked_files '*.py'         → all tracked .py files
#        tracked_files ':!vendor/**'  → all tracked files excluding vendor/
tracked_files() {
    if [[ $# -eq 0 ]]; then
        git ls-files
    else
        git ls-files "$@"
    fi
}

# Exit with skip status if we're not inside a git working tree.
require_git() {
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        printf "%s⊘%s %s (not a git repo — skipped)\n" \
            "$C_YELLOW" "$C_RESET" "$_RULE_NAME"
        exit 0
    fi
}

# Allow in-source waivers. Rules that support exceptions should grep for
# `governance: allow-<rule-name>` on the violating line and skip it.
# Example: `foo = "AKIA..."  # governance: allow-secrets-hygiene TICKET-123`
has_waiver() {
    local file="$1" line_no="$2" rule="$3"
    sed -n "${line_no}p" "$file" | grep -q "governance: allow-${rule}"
}

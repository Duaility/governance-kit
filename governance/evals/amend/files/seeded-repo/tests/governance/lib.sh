#!/usr/bin/env bash
set -u
_RULE_NAME=""; _VIOLATION_COUNT=0; _VIOLATIONS=()

rule_start() { _RULE_NAME="$1"; _VIOLATION_COUNT=0; _VIOLATIONS=(); }
violation()  { _VIOLATION_COUNT=$((_VIOLATION_COUNT + 1)); _VIOLATIONS+=("$1"); }
rule_end() {
    if [[ $_VIOLATION_COUNT -eq 0 ]]; then
        echo "✓ $_RULE_NAME"; exit 0
    fi
    echo "✗ $_RULE_NAME ($_VIOLATION_COUNT violation(s))"
    for v in "${_VIOLATIONS[@]}"; do echo "    $v"; done
    exit 1
}
require_git() { git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "⊘ not a git repo"; exit 0; }; }
has_waiver() { sed -n "${2}p" "$1" | grep -q "governance: allow-${3}"; }
tracked_files() { if [[ $# -eq 0 ]]; then git ls-files; else git ls-files "$@"; fi; }

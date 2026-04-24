#!/usr/bin/env bash
# CUSTOMIZED — do not overwrite. Includes an extra helper used by this repo's rules.
set -u

_RULE_NAME=""
_VIOLATION_COUNT=0
_VIOLATIONS=()

rule_start() { _RULE_NAME="$1"; _VIOLATION_COUNT=0; _VIOLATIONS=(); }
violation()   { _VIOLATION_COUNT=$((_VIOLATION_COUNT + 1)); _VIOLATIONS+=("$1"); }
rule_end() {
    if [[ $_VIOLATION_COUNT -eq 0 ]]; then
        echo "OK $_RULE_NAME"; exit 0
    fi
    echo "FAIL $_RULE_NAME ($_VIOLATION_COUNT)"
    for v in "${_VIOLATIONS[@]}"; do echo "  $v"; done
    exit 1
}
has_waiver() { sed -n "${2}p" "$1" | grep -q "governance: allow-${3}"; }

# Local helper added by the fixture owner.
fixture_custom_helper() { echo "custom"; }

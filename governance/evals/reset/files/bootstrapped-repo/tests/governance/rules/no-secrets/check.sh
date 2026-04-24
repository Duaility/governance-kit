#!/usr/bin/env bash
source "$(dirname "$0")/../../lib.sh"
rule_start "no-secrets"
if git grep -nE 'AKIA[0-9A-Z]{16}' -- ':!tests/governance/' 2>/dev/null; then
    violation "AWS key-like pattern found"
fi
rule_end

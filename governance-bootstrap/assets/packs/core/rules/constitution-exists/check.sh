#!/usr/bin/env bash
# Rule: CONSTITUTION.md exists at the repo root and is non-empty.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "constitution-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
FILE="$ROOT/CONSTITUTION.md"

if [[ ! -f "$FILE" ]]; then
    violation "CONSTITUTION.md not found at repo root"
elif [[ ! -s "$FILE" ]]; then
    violation "CONSTITUTION.md exists but is empty"
elif [[ $(wc -l < "$FILE") -lt 10 ]]; then
    violation "CONSTITUTION.md has fewer than 10 lines — looks like a stub"
fi

rule_end

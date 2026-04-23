#!/usr/bin/env bash
source "$(dirname "$0")/../../lib.sh"
rule_start "constitution-exists"
[[ -s CONSTITUTION.md ]] || violation "CONSTITUTION.md missing or empty"
rule_end

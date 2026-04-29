#!/usr/bin/env bash
source "$(dirname "$0")/../../../lib.sh"
directive_start "constitution-exists"
[[ -s CONSTITUTION.md ]] || violation "CONSTITUTION.md missing or empty"
directive_end

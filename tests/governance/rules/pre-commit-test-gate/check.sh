#!/usr/bin/env bash
# Rule: The governance-kit source repo's local pre-commit hook runs the
# pack-author test suite, including packverb contract coverage.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "pre-commit-test-gate"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

hook=".githooks/pre-commit"
pack_tests="scripts/test-packs.sh"
packverb_tests="scripts/test-packverb.py"

if [[ ! -f "$pack_tests" ]]; then
    rule_end
fi

if [[ ! -x "$pack_tests" ]]; then
    violation "$pack_tests exists but is not executable"
fi

if [[ ! -f "$hook" ]]; then
    violation "$hook is missing; pack tests cannot be enforced before commit"
elif [[ ! -x "$hook" ]]; then
    violation "$hook exists but is not executable"
elif ! grep -Fq "$pack_tests" "$hook"; then
    violation "$hook must invoke $pack_tests so pack tests run before commit"
fi

if [[ -f "$packverb_tests" ]] && ! grep -Fq "$packverb_tests" "$pack_tests"; then
    violation "$pack_tests must invoke $packverb_tests so packverb contracts are part of the pack test gate"
fi

rule_end

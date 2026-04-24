#!/usr/bin/env bash
# Governance test runner — discovers and runs every directive's check.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for directive in "$HERE"/directives/*/check.sh; do
    bash "$directive" || fail=1
done
exit "$fail"

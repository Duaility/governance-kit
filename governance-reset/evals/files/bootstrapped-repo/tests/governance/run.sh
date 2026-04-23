#!/usr/bin/env bash
# Governance test runner — discovers and runs every rule's check.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for rule in "$HERE"/rules/*/check.sh; do
    bash "$rule" || fail=1
done
exit "$fail"

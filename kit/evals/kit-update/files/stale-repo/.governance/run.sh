#!/usr/bin/env bash
# governance-kit:managed
# Old v0.1 runner stub — current kit ships a richer version
# (single-directive filter, exit-code summary, etc.).
set -eu
fail=0
for check in $(find .governance/packs -type f -path '*/directives/*/check.sh'); do
    bash "$check" || fail=$((fail + 1))
done
exit $fail

#!/usr/bin/env bash
# governance-kit:managed kit-version=0.1 generated=2026-04-01
# Old v0.1 runner stub — current kit ships a richer version. This
# fixture's `install.yaml` was hand-deleted; the marker above is the
# only surviving evidence of the original install version.
set -eu
fail=0
for check in $(find .governance/packs -type f -path '*/directives/*/check.sh'); do
    bash "$check" || fail=$((fail + 1))
done
exit $fail

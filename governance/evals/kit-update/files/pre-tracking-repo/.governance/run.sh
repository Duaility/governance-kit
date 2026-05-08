#!/usr/bin/env bash
# Old runtime stub from before the marker convention. The eval grades
# the agent's handling of the pre-tracking install case (kit_version
# absent in install.yaml), where the runtime files lack the marker too.
set -eu
fail=0
for check in $(find .governance/packs -type f -path '*/directives/*/check.sh'); do
    bash "$check" || fail=$((fail + 1))
done
exit $fail

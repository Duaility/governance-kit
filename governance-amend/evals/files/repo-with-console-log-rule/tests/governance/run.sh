#!/usr/bin/env bash
set -u
if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then echo "⊘ skipped"; exit 0; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
failed=0
for rule in "$HERE"/rules/*.sh; do
    [[ -f "$rule" ]] || continue
    bash "$rule" || failed=1
done
[[ $failed -eq 0 ]] || exit 1
echo "governance: all rules passed"

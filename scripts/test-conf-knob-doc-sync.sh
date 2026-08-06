#!/usr/bin/env bash
# Every config helper call names an entry declared in the sibling directive.yaml.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

note() { printf '  ✗ conf-registry-sync: %s\n' "$1"; fail=$((fail + 1)); }

while IFS= read -r check; do
    manifest="$(dirname "$check")/directive.yaml"
    [[ -f "$manifest" ]] || continue
    while IFS=: read -r line_no key; do
        [[ -n "$key" ]] || continue
        grep -qE "^[[:space:]]+- name:[[:space:]]+${key}[[:space:]]*$" "$manifest" \
            || note "$check:$line_no — reads undeclared config key $key"
    done < <(
        sed -nE 's/^([0-9]+):.*conf_get[[:space:]]+[^[:space:]]+[[:space:]]+([A-Z][A-Z0-9_]*).*/\1:\2/p' \
            < <(nl -ba "$check" | sed 's/^[[:space:]]*//')
        sed -nE 's/^([0-9]+):.*conf_list[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+([A-Z][A-Z0-9_]*).*/\1:\2/p' \
            < <(nl -ba "$check" | sed 's/^[[:space:]]*//')
    )
done < <(find "$ROOT/packs" "$ROOT/.governance/packs/duaility/governance-kit" -type f -name check.sh 2>/dev/null | sort)

if [[ "$fail" -eq 0 ]]; then
    printf '  ✓ conf-registry-sync: every config helper key is declared in directive.yaml\n'
    exit 0
fi
printf '  ✗ conf-registry-sync: %s problem(s)\n' "$fail"
exit 1

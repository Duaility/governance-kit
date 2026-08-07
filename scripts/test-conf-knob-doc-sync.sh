#!/usr/bin/env bash
# Every config helper call names an entry declared in the sibling directive.yaml.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

note() { printf '  ✗ conf-registry-sync: %s\n' "$1"; fail=$((fail + 1)); }

while IFS= read -r check; do
    manifest="$(dirname "$check")/directive.yaml"
    [[ -f "$manifest" ]] || continue
    while IFS=: read -r line_no source_line; do
        [[ -n "$source_line" ]] || continue
        key="$(printf '%s\n' "$source_line" \
            | sed -nE 's/.*conf_get[[:space:]]+[^[:space:]]+[[:space:]]+([A-Z][A-Z0-9_]*).*/\1/p')"
        if [[ -z "$key" ]]; then
            key="$(printf '%s\n' "$source_line" \
                | sed -nE 's/.*conf_list[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+([A-Z][A-Z0-9_]*).*/\1/p')"
        fi
        [[ -n "$key" ]] || continue
        grep -qE "^[[:space:]]+- name:[[:space:]]+${key}([[:space:]]|$)" "$manifest" \
            || note "$check:$line_no — reads undeclared config key $key"
    done < <(rg -n 'conf_(get|list)[[:space:]]' "$check" 2>/dev/null || true)
# `.governance/` is a released consumer snapshot and may intentionally lag the
# source registry during a kit update; source-pack checks are the authoritative
# contract for this sync test.
done < <(find "$ROOT/packs" -type f -name check.sh 2>/dev/null | sort)

if [[ "$fail" -eq 0 ]]; then
    printf '  ✓ conf-registry-sync: every config helper key is declared in directive.yaml\n'
    exit 0
fi
printf '  ✗ conf-registry-sync: %s problem(s)\n' "$fail"
exit 1

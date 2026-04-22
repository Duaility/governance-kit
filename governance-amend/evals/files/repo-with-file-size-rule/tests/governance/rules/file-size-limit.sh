#!/usr/bin/env bash
# Rule: no single tracked source file may exceed the limit.
# Limit is controlled by GOVERNANCE_FILE_SIZE_LIMIT (default 500).
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "file-size-limit"
require_git

LIMIT="${GOVERNANCE_FILE_SIZE_LIMIT:-500}"

while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
        *.md|*.lock|*.svg|*.json) continue ;;
    esac
    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [[ -z "$lines" ]] && continue
    if (( lines > LIMIT )); then
        first="$(sed -n '1p' "$f")"
        if [[ "$first" == *"governance: allow-file-size-limit"* ]]; then
            continue
        fi
        violation "$f has $lines lines (> $LIMIT)"
    fi
done < <(git ls-files 2>/dev/null)

rule_end

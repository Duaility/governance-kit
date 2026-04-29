#!/usr/bin/env bash
# Rule: no console.log / console.debug in tracked JS/TS.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "no-console-log"
require_git

while IFS=: read -r file line _; do
    [[ -z "$file" ]] && continue
    if ! has_waiver "$file" "$line" "no-console-log"; then
        violation "$file:$line"
    fi
done < <(git ls-files -z '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null \
         | xargs -0 grep -nE 'console\.(log|debug)' 2>/dev/null || true)

directive_end

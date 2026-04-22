#!/usr/bin/env bash
# Orphan: this script exists on disk but is NOT named in any CONSTITUTION Invariants
# entry. The gardener should flag it under Consistency C2 (test without rule).
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-console-log"
require_git
while IFS=: read -r file line _; do
    [[ -z "$file" ]] && continue
    violation "$file:$line"
done < <(git ls-files -z '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null \
         | xargs -0 grep -nE 'console\.(log|debug)' 2>/dev/null || true)
rule_end

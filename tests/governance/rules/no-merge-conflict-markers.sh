#!/usr/bin/env bash
# Rule: No tracked file contains a merge conflict marker.
# Installed ALWAYS (not an opt-in menu item) — this rule has zero false positives
# and prevents an entire category of broken builds.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-merge-conflict-markers"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Use git grep with -I to skip binary files. Match each marker at line-start.
while IFS=: read -r file line_no _; do
    [[ -z "$file" ]] && continue
    # Skip this rule file — it contains the patterns as strings.
    [[ "$file" == tests/governance/rules/no-merge-conflict-markers.sh ]] && continue
    violation "$file:$line_no — merge conflict marker"
done < <(git grep -InE '^(<<<<<<< |=======$|>>>>>>> )' -- \
    ':!governance-bootstrap/assets/packs/*/evals/**' 2>/dev/null || true)

rule_end

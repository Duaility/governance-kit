#!/usr/bin/env bash
# Rule: Every TODO/FIXME must reference a tracker (#123 or ABC-123).
# Orphan TODOs rot — a TODO without a ticket is a future bug with no owner.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-orphan-todos"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Pattern: TODO or FIXME, then anything up to 80 chars on the same line.
# Accepted references on the same line: #123, ABC-123 (uppercase project key + number).
while IFS=: read -r file line_no match; do
    [[ -z "$file" ]] && continue
    # Skip matches in this rule file itself (it mentions TODO).
    [[ "$file" == tests/governance/rules/no-orphan-todos.sh ]] && continue
    # Skip matches inside the constitution, which documents the rule.
    [[ "$file" == CONSTITUTION.md ]] && continue
    # Accept waiver: `# governance: allow-no-orphan-todos <reason>`
    has_waiver "$file" "$line_no" "no-orphan-todos" && continue
    # Accept a tracker reference on the same line.
    if echo "$match" | grep -qE '(#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+)'; then
        continue
    fi
    violation "$file:$line_no — $(echo "$match" | sed 's/^[[:space:]]*//' | cut -c1-80)"
done < <(git grep -nE '\b(TODO|FIXME)\b' -- \
    ':!tests/governance/rules/no-orphan-todos.sh' \
    ':!CONSTITUTION.md' 2>/dev/null || true)

rule_end

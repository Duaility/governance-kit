#!/usr/bin/env bash
# Rule: GitHub issue templates must encode the agent brainstorming handoff.
# Rationale: Agent-created issues are the durable record of a brainstorming
# session. If the issue form does not ask for the settled decision, scope,
# acceptance criteria, validation, and open questions, the next agent has to
# recover intent from chat history instead of the system of record.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "issue-templates"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

require_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        violation "$file not found"
        return 1
    fi
    return 0
}

require_pattern() {
    local file="$1" pattern="$2" message="$3"
    grep -qE "$pattern" "$file" || violation "$file - $message"
}

require_count_at_least() {
    local file="$1" pattern="$2" min="$3" message="$4"
    local count
    count="$(grep -cE "$pattern" "$file" || true)"
    if (( count < min )); then
        violation "$file - $message"
    fi
}

config=".github/ISSUE_TEMPLATE/config.yml"
proposal=".github/ISSUE_TEMPLATE/proposal.yml"
bug=".github/ISSUE_TEMPLATE/bug.yml"

if require_file "$config"; then
    require_pattern "$config" '^blank_issues_enabled:[[:space:]]*false$' "blank issues must be disabled so issues use a tracked template"
fi

if require_file "$proposal"; then
    require_pattern "$proposal" '^name:[[:space:]]*Proposal$' "proposal form must be named Proposal"
    require_pattern "$proposal" '^title:[[:space:]]*"proposal: <short summary>"$' "proposal title must use the proposal: prefix"
    require_pattern "$proposal" '^labels:[[:space:]]*\["proposal"\]$' "proposal form must apply the proposal label"
    for id in context decision scope acceptance validation open-questions; do
        require_pattern "$proposal" "^[[:space:]]+id:[[:space:]]*$id$" "proposal form missing '$id' field"
    done
    for label in Context Decision Scope 'Acceptance criteria' Validation 'Open questions'; do
        require_pattern "$proposal" "^[[:space:]]+label:[[:space:]]*$label$" "proposal form missing '$label' label"
    done
    require_count_at_least "$proposal" '^[[:space:]]+required:[[:space:]]*true$' 6 "all six proposal handoff fields must be required"
fi

if require_file "$bug"; then
    require_pattern "$bug" '^name:[[:space:]]*Bug$' "bug form must be named Bug"
    require_pattern "$bug" '^title:[[:space:]]*"bug: <short summary>"$' "bug title must use the bug: prefix"
    require_pattern "$bug" '^labels:[[:space:]]*\["bug"\]$' "bug form must apply the bug label"
    for id in what-happened expected repro environment notes; do
        require_pattern "$bug" "^[[:space:]]+id:[[:space:]]*$id$" "bug form missing '$id' field"
    done
    require_count_at_least "$bug" '^[[:space:]]+required:[[:space:]]*true$' 4 "core bug-report fields must be required"
fi

rule_end

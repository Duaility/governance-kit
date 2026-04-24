#!/usr/bin/env bash
# Rule: Each tracked plans/*.md file carries an `issue-<N>` token in its
# filename, no two plan files share the same issue number, and every plan
# includes at least one validation-intent section heading
# (`## Validation`, `## Verification`, or `## Acceptance`).
# Rationale: Plans are the durable record of intent behind a change set. A
# one-to-one binding between plan and issue keeps the system of record
# unambiguous — reviewers jump from an issue to its single plan, and agents
# can detect whether an issue already has a plan before drafting a duplicate.
# A validation-intent section tells a reviewer (human or agent) how the plan
# will be judged complete before any code is written.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "plan-per-issue"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

if [[ ! -d "$ROOT/plans" ]]; then
    rule_end
fi

plan_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    plan_files+=("$f")
done < <(git ls-files -- 'plans/*.md' 2>/dev/null || true)

if [[ ${#plan_files[@]} -eq 0 ]]; then
    rule_end
fi

seen_nums=()
seen_files=()
for f in "${plan_files[@]}"; do
    # Two independent per-file waivers — each covers only its own block so a
    # plan that opts out of the filename check is still held to the
    # validation-section check (and vice versa).
    waive_filename=0
    waive_validation=0
    if grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-plan-per-issue' "$f"; then
        waive_filename=1
    fi
    if grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-plan-validation' "$f"; then
        waive_validation=1
    fi

    # Filename-token + duplicate-issue check.
    if [[ $waive_filename -eq 0 ]]; then
        base="${f##*/}"
        if [[ "$base" =~ issue-([0-9]+) ]]; then
            num="${BASH_REMATCH[1]}"
            dup_of=""
            for i in "${!seen_nums[@]}"; do
                if [[ "${seen_nums[$i]}" == "$num" ]]; then
                    dup_of="${seen_files[$i]}"
                    break
                fi
            done
            if [[ -n "$dup_of" ]]; then
                violation "$f — issue #$num already has a plan at $dup_of"
            else
                seen_nums+=("$num")
                seen_files+=("$f")
            fi
        else
            violation "$f — plan filename must include an 'issue-<N>' token (e.g. 2026-04-23-issue-15-summary.md)"
        fi
    fi

    # Validation-intent section check.
    if [[ $waive_validation -eq 0 ]]; then
        if ! grep -qE '^##[[:space:]]+(Validation|Verification|Acceptance)\b' "$f"; then
            violation "$f — plan is missing a '## Validation', '## Verification', or '## Acceptance' section describing how completion will be judged"
        fi
    fi
done

rule_end

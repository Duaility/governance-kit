#!/usr/bin/env bash
# Rule: The repo maintains plans/ — each plan doc captures the plan an agent
# (or human) executed, with a title, Goal, and Steps section. Substantive
# tracked changes must add or modify at least one plans/*.md file in the same
# change set.
# Rationale: The diff shows what changed; the plan shows why the change took
# this shape. Without it, reviewers and future agents reconstruct intent from
# code, and get it wrong.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "plan-captured"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

if [[ ! -d "$ROOT/plans" ]]; then
    violation "plans/ directory not found at repo root"
    rule_end
    exit 0
fi

plan_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    plan_files+=("$f")
done < <(git ls-files -- 'plans/*.md' 2>/dev/null || true)

if [[ ${#plan_files[@]} -eq 0 ]]; then
    violation "plans/ contains no tracked .md files"
    rule_end
    exit 0
fi

for f in "${plan_files[@]}"; do
    # Per-file waiver: `governance: allow-plan-captured` anywhere in the file.
    if grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-plan-captured' "$f"; then
        continue
    fi

    grep -qE '^# '        "$f" || violation "$f — missing top-level '# ' heading"
    grep -qE '^## Goal'   "$f" || violation "$f — missing '## Goal' section"
    grep -qE '^## Steps'  "$f" || violation "$f — missing '## Steps' section"
done

# Require a plan touch for substantive tracked changes in the same change set.
# Resolution order:
#   1. Pre-commit / local staging context: use the staged diff.
#   2. CI / committed branch context: diff merge-base..HEAD against the default branch.
# Changes limited to plans/ and governance-health/ are exempt from the same-change check.
changed_files=()
if ! git diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        changed_files+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACMRD -- 2>/dev/null || true)
else
    base=""
    for candidate in origin/main origin/master main master; do
        if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
            mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
            if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD)" ]]; then
                base="$mb"
                break
            fi
        fi
    done

    if [[ -n "$base" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            changed_files+=("$f")
        done < <(git diff --name-only --diff-filter=ACMRD "$base..HEAD" -- 2>/dev/null || true)
    fi
fi

if [[ ${#changed_files[@]} -gt 0 ]]; then
    substantive_files=()
    plan_touched=0

    for f in "${changed_files[@]}"; do
        case "$f" in
            plans/*.md)
                plan_touched=1
                ;;
            governance-health/*)
                ;;
            *)
                substantive_files+=("$f")
                ;;
        esac
    done

    if [[ ${#substantive_files[@]} -gt 0 && $plan_touched -eq 0 ]]; then
        violation "substantive change set touches tracked files outside plans/ but no plans/*.md file was added or modified"
        for f in "${substantive_files[@]:0:5}"; do
            violation "missing plan touch for change: $f"
        done
        if [[ ${#substantive_files[@]} -gt 5 ]]; then
            violation "...and $((${#substantive_files[@]} - 5)) more file(s)"
        fi
    fi
fi

rule_end

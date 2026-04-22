#!/usr/bin/env bash
# Rule: The repo maintains plans/ — each plan doc captures the plan an agent
# (or human) executed, with a title, Goal, and Steps section.
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

rule_end

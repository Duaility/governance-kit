#!/usr/bin/env bash
# Rule: At least one non-governance GitHub Actions workflow exists.
# Rationale: CI is the backstop for the pre-commit hook (which is skippable).
# If the only workflow is governance.yml itself, there's nothing verifying the
# rest of the project. Governance without CI for the code it protects is honor-system.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "ci-workflow-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
WF_DIR="$ROOT/.github/workflows"

if [[ ! -d "$WF_DIR" ]]; then
    violation "no .github/workflows/ directory"
    rule_end
fi

shopt -s nullglob
count=0
for f in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
    # Don't count governance.yml itself — this rule wants CI for the actual project.
    [[ "$(basename "$f")" == "governance.yml" || "$(basename "$f")" == "governance.yaml" ]] && continue
    count=$((count + 1))
done
shopt -u nullglob

if [[ $count -eq 0 ]]; then
    violation ".github/workflows/ has no non-governance workflow (CI is the backstop for skipped hooks)"
fi

rule_end

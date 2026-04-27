#!/usr/bin/env bash
# Directive: When HEAD carries a tracked receipts/*.md whose `## Checklist`
# section has at least one `- [x]` and zero `- [ ]` items, and the current
# branch is not main/master, an open pull request must exist for the current
# branch on the GitHub remote.
#
# This is a gate, not an actor. The directive verifies a PR exists; opening
# the PR is left to the agent or developer (`gh pr create --fill`).
#
# Reading HEAD (not the working tree) is deliberate: the commit that ticks
# the final box must land cleanly so it can be referenced by the PR. The
# gate fires on the *next* commit (because HEAD now contains the completed
# receipt) and in CI (which checks HEAD on every push).
#
# Skip-with-warning when `gh` is missing or unauthenticated — local devs
# without gh are not blocked, but CI (where gh is expected) enforces. When
# gh is present but the API call fails, fail loudly: silent bypass on
# network errors would defeat the gate.
#
# Test seam: setting GOVERNANCE_TEST_PR_EXISTS=1 (or =0) bypasses the gh
# call entirely. Used by the eval harness to test both branches without
# hitting GitHub.
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "pr-required-when-checklist-complete"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Skip when HEAD doesn't exist (no commits yet).
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    directive_end
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
case "$branch" in
    main|master|HEAD|"")
        directive_end
        ;;
esac

# Walk every tracked receipt at HEAD; collect the ones whose Checklist is
# fully ticked.
completed=()
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    content=$(git show "HEAD:$path" 2>/dev/null) || continue

    checklist=$(printf '%s\n' "$content" | awk '
        BEGIN { in_section = 0 }
        /^##[[:space:]]+/ {
            if (in_section) exit
            line = $0
            sub(/^##[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (tolower(line) == "checklist") { in_section = 1; next }
        }
        { if (in_section) print }
    ')

    [[ -z "$checklist" ]] && continue

    unchecked=$(printf '%s\n' "$checklist" \
        | grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\][[:space:]]+' \
        || true)
    checked=$(printf '%s\n' "$checklist" \
        | grep -cE '^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]+' \
        || true)

    if [[ "$unchecked" -eq 0 && "$checked" -ge 1 ]]; then
        completed+=("$path")
    fi
done < <(git ls-tree -r HEAD --name-only -- receipts/ 2>/dev/null | grep -E '\.md$' || true)

if [[ ${#completed[@]} -eq 0 ]]; then
    directive_end
fi

# Determine whether a PR exists for the current branch.
pr_exists=""
if [[ -n "${GOVERNANCE_TEST_PR_EXISTS:-}" ]]; then
    pr_exists="$GOVERNANCE_TEST_PR_EXISTS"
elif ! command -v gh >/dev/null 2>&1; then
    printf '%s⊘%s pr-required-when-checklist-complete (gh CLI not installed — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
elif ! gh auth status >/dev/null 2>&1; then
    printf '%s⊘%s pr-required-when-checklist-complete (gh not authenticated — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
else
    count=$(gh pr list --head "$branch" --state open --json number --jq 'length' 2>/dev/null || echo "")
    if [[ -z "$count" ]]; then
        violation "gh pr list failed for branch '$branch' — cannot verify PR existence (network or API issue)"
        directive_end
    fi
    if [[ "$count" -gt 0 ]]; then
        pr_exists="1"
    else
        pr_exists="0"
    fi
fi

if [[ "$pr_exists" == "0" ]]; then
    list="${completed[*]}"
    violation "branch '$branch' has completed-checklist receipts but no open PR — open one with: gh pr create --fill --base main --head '$branch' (receipts: $list)"
fi

directive_end

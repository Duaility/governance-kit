#!/usr/bin/env bash
# Directive: When the current branch is not main/master AND has an open PR
# on the GitHub remote that is **not in draft state** (i.e., marked ready
# for review), that PR must carry a codex-authored review — a Pull Request
# Review whose body contains the marker `<!-- codex-review -->`.
#
# Trigger axis is the GitHub draft → ready transition (`gh pr ready`),
# the platform's first-class "ready for review" signal. Decoupled from
# receipt checklist state: the agent may finish the checklist, push, and
# keep iterating in draft. Review is mandated only when the agent (or a
# human) explicitly marks the PR ready, making readiness an intentional
# gesture rather than a side-effect of the commit cadence.
#
# Composition with `pr-required-when-checklist-complete`:
#   - The create-gate fires on receipt-checklist completion and demands a PR
#     (draft is fine — its check is just `PR exists`).
#   - This review-gate fires on draft→ready and demands a codex review.
#
# Local-only: skipped under CI. Codex is part of the local agent loop, not
# a merge-gate. The hard merge-gate in CI is pr-required-when-checklist-
# complete (PR must exist); review quality on the PR is verified by humans.
#
# Skip-with-warning when `gh` is missing or unauthenticated. When `gh` is
# present but the API call fails, fail loudly: silent bypass on network
# errors would defeat the gate.
#
# Tested by mocking `gh` via a PATH shim — see evals/test.sh. The check
# itself has no test backdoor; production code always calls the real gh.
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "pr-review-required-when-pr-ready"
require_git

# Local-only — skip in CI environments.
if [[ -n "${CI:-}" ]]; then
    printf '%s⊘%s pr-review-required-when-pr-ready (CI environment — directive is local-only)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

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

# Skip-with-warning when gh is unavailable — local devs without gh aren't blocked.
if ! command -v gh >/dev/null 2>&1; then
    printf '%s⊘%s pr-review-required-when-pr-ready (gh CLI not installed — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
    printf '%s⊘%s pr-review-required-when-pr-ready (gh not authenticated — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

# Fetch number + isDraft for the open PR on this branch in one call.
# Output format: "<number>\t<isDraft>" or empty string if no PR.
pr_data=$(gh pr list --head "$branch" --state open --json number,isDraft --jq '.[0] // empty | "\(.number)\t\(.isDraft)"' 2>/dev/null || echo "__ERR__")
if [[ "$pr_data" == "__ERR__" ]]; then
    violation "gh pr list failed for branch '$branch' — cannot verify PR state (network or API issue)"
    directive_end
fi

# No open PR → directive does not apply (readiness has no signal to read).
if [[ -z "$pr_data" ]]; then
    printf '%s⊘%s pr-review-required-when-pr-ready (no open PR for branch — directive does not apply)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

IFS=$'\t' read -r pr_number is_draft <<<"$pr_data"

# Draft PR → not ready for review yet.
if [[ "$is_draft" == "true" ]]; then
    printf '%s⊘%s pr-review-required-when-pr-ready (PR #%s is in draft — mark ready with `gh pr ready %s` to request review)\n' \
        "$C_YELLOW" "$C_RESET" "$pr_number" "$pr_number"
    exit 0
fi

# Invariant: ready-for-review PR carries a codex-marked review.
review_count=$(gh pr view "$pr_number" --json reviews --jq '[.reviews[] | select((.body // "") | contains("<!-- codex-review -->"))] | length' 2>/dev/null || echo "")
if [[ -z "$review_count" ]]; then
    violation "gh pr view failed for PR #$pr_number — cannot verify review existence (network or API issue)"
    directive_end
fi

if [[ "$review_count" -eq 0 ]]; then
    violation "PR #$pr_number on branch '$branch' is marked ready for review but carries no codex review — this directive mandates posting one now. Execute: codex exec 'review PR #$pr_number and start the review body with <!-- codex-review --> so the governance gate can detect it'. The directive's firing is the durable authorization; agents must run the command, not re-pose it as a 'want me to ask codex to review?' offer."
fi

directive_end

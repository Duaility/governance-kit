#!/usr/bin/env bash
# Directive: When HEAD carries a tracked receipts/*.md whose `## Checklist`
# section has at least one `- [x]` and zero `- [ ]` items, the current branch
# is not main/master, AND an open PR exists for the branch on the GitHub
# remote, that PR must carry a codex-authored review — a Pull Request Review
# whose body contains the marker `<!-- codex-review -->`.
#
# Composes with `pr-required-when-checklist-complete` via precondition-skip:
# when no PR exists for the branch yet, this directive skips-with-info and
# defers messaging to the create-gate. The cascade falls out of
# re-evaluation — agent runs `gh pr create`, re-runs governance, this gate
# now fires and instructs `codex exec 'review PR #N ...'`. There is no
# declared dependency between the two directives; each reads its own
# preconditions on every firing (level-triggered reconciliation).
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
directive_start "pr-review-required-when-checklist-complete"
require_git

# Local-only — skip in CI environments.
if [[ -n "${CI:-}" ]]; then
    printf '%s⊘%s pr-review-required-when-checklist-complete (CI environment — directive is local-only)\n' \
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

# Same trigger condition as pr-required-when-checklist-complete: walk every
# tracked receipt at HEAD; collect the ones whose Checklist is fully ticked.
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

# Skip-with-warning when gh is unavailable — local devs without gh aren't blocked.
if ! command -v gh >/dev/null 2>&1; then
    printf '%s⊘%s pr-review-required-when-checklist-complete (gh CLI not installed — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
    printf '%s⊘%s pr-review-required-when-checklist-complete (gh not authenticated — skipped)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

# Precondition: PR must exist. If not, defer to pr-required-when-checklist-complete.
pr_number=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // ""' 2>/dev/null || echo "__ERR__")
if [[ "$pr_number" == "__ERR__" ]]; then
    violation "gh pr list failed for branch '$branch' — cannot verify PR existence (network or API issue)"
    directive_end
fi
if [[ -z "$pr_number" ]]; then
    printf '%s⊘%s pr-review-required-when-checklist-complete (no PR for branch yet — deferring to pr-required-when-checklist-complete)\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

# Invariant: PR carries a codex-marked review.
review_count=$(gh pr view "$pr_number" --json reviews --jq '[.reviews[] | select((.body // "") | contains("<!-- codex-review -->"))] | length' 2>/dev/null || echo "")
if [[ -z "$review_count" ]]; then
    violation "gh pr view failed for PR #$pr_number — cannot verify review existence (network or API issue)"
    directive_end
fi

if [[ "$review_count" -eq 0 ]]; then
    list="${completed[*]}"
    violation "PR #$pr_number on branch '$branch' has a complete-checklist receipt but no codex review — this directive mandates posting one now. Execute: codex exec 'review PR #$pr_number and start the review body with <!-- codex-review --> so the governance gate can detect it' (receipts: $list). The directive's firing is the durable authorization; agents must run the command, not re-pose it as a 'want me to ask codex to review?' offer."
fi

directive_end

#!/usr/bin/env bash
# Rule: For every non-merge, non-revert commit in scope, the issue number in
# the commit subject's trailing `(#N)` must match at least one `issue-<N>`
# token on a `plans/*.md` file that the commit added or modified. A commit
# that touches no `plans/*.md` also fails.
#
# Rationale: `conventional-commits` pins each commit to an issue, and
# `plan-per-issue` pins each plan file to an issue, but nothing cross-checks
# the two — a commit claiming `(#15)` while touching only issue #42's plan
# passes both rules. This rule closes that hole and, in doing so, subsumes
# the former `plan-captured` "substantive change must touch a plan"
# obligation under a stricter check (the plan must also be the *right* one).
#
# Modes:
#   Mode A — commit-msg hook:  bash commit-issue-plan-match.sh <path-to-msg-file>
#       Reads the pending subject + body from the msg file and uses the
#       staged diff for the plan-touch check.
#   Mode B — CI / run.sh:      bash commit-issue-plan-match.sh
#       Walks default-branch merge-base → HEAD and validates each commit
#       against its own message + tree-diff.
#
# Exceptions:
#   - Merge commits (parent count > 1 in Mode B; commit-msg never sees them).
#   - Revert commits (subject starts with `Revert "`).
#   - Per-commit waiver: a line `governance: allow-commit-issue-plan-match
#     <reason>` anywhere in the commit body, for unusual cross-issue
#     refactors. The reason is required — a bare token does not waive.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "commit-issue-plan-match"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Echoes the trailing issue number (1+ digits) from a subject line, or empty.
# Anchors to end-of-line so trailing `(#N)` wins over mid-sentence `(#M)`.
extract_issue_num() {
    local subject="$1"
    if [[ "$subject" =~ \(#([1-9][0-9]*)\)[[:space:]]*$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# Echoes space-separated `issue-<N>` numbers harvested from the basenames
# of the plan files passed as args. A single plan file with multiple
# `issue-<N>` tokens contributes all of them.
collect_plan_issues() {
    local f base rest nums=""
    for f in "$@"; do
        [[ -z "$f" ]] && continue
        base="${f##*/}"
        rest="$base"
        while [[ "$rest" =~ issue-([0-9]+) ]]; do
            nums+="${BASH_REMATCH[1]} "
            rest="${rest#*issue-${BASH_REMATCH[1]}}"
        done
    done
    printf '%s' "$nums"
}

# Returns 0 if the commit body carries a valid waiver line.
msg_has_waiver() {
    local msg="$1"
    printf '%s\n' "$msg" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-commit-issue-plan-match[[:space:]]+.+'
}

# validate <label> <subject> <body> [changed-file ...]
validate() {
    local label="$1" subject="$2" body="$3"
    shift 3

    # Skip merge commits.
    [[ "$subject" == Merge\ * ]] && return 0
    # Skip revert commits (git auto-subject).
    [[ "$subject" == Revert\ \"* ]] && return 0

    if msg_has_waiver "$body"; then
        return 0
    fi

    local issue_num
    issue_num="$(extract_issue_num "$subject")"
    if [[ -z "$issue_num" ]]; then
        # `conventional-commits` will flag the shape separately; we still
        # emit a targeted violation so the root cause is clear to readers.
        violation "$label — subject has no trailing '(#N)' issue suffix: '$subject'"
        return 0
    fi

    local plan_files=() f
    for f in "$@"; do
        case "$f" in
            plans/*.md) plan_files+=("$f") ;;
        esac
    done

    if [[ ${#plan_files[@]} -eq 0 ]]; then
        violation "$label — commit claims (#$issue_num) but touches no plans/*.md (add the plan for this issue, or use 'governance: allow-commit-issue-plan-match <reason>' in the body)"
        return 0
    fi

    local plan_issues n match=0
    plan_issues="$(collect_plan_issues "${plan_files[@]}")"
    for n in $plan_issues; do
        if [[ "$n" == "$issue_num" ]]; then
            match=1
            break
        fi
    done

    if [[ "$match" == "0" ]]; then
        local touched="${plan_files[*]}"
        violation "$label — subject issue #$issue_num not found among plan issue numbers [${plan_issues% }] (plans touched: ${touched})"
    fi
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        rule_end
    fi
    subject=$(grep -vE '^[[:space:]]*($|#)' "$msg_file" | head -n1)
    body=$(cat "$msg_file")

    changed=()
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        changed+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACMR -- 2>/dev/null || true)

    if [[ ${#changed[@]} -eq 0 ]]; then
        validate "pending commit" "$subject" "$body"
    else
        validate "pending commit" "$subject" "$body" "${changed[@]}"
    fi
    rule_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh — walk base..HEAD
# ──────────────────────────────────────────────────────────────
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

if [[ -z "$base" ]]; then
    # No new work on this branch relative to the default — Mode A handles
    # any pending commit. Re-flagging history already on main is out of
    # scope.
    rule_end
fi

while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    parents=$(git log -1 --format=%P "$sha" 2>/dev/null || echo "")
    # Multi-parent → merge commit; skip.
    [[ "$parents" == *' '* ]] && continue
    subject=$(git log -1 --format=%s "$sha" 2>/dev/null || echo "")
    [[ "$subject" == Revert\ \"* ]] && continue
    body=$(git log -1 --format=%B "$sha" 2>/dev/null || echo "")

    changed=()
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        changed+=("$f")
    done < <(git diff-tree --no-commit-id --name-only --diff-filter=ACMR -r "$sha" 2>/dev/null || true)

    if [[ ${#changed[@]} -eq 0 ]]; then
        validate "$sha" "$subject" "$body"
    else
        validate "$sha" "$subject" "$body" "${changed[@]}"
    fi
done < <(git log "$base..HEAD" --format='%H')

rule_end

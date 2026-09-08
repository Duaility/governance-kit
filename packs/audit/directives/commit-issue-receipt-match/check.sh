#!/usr/bin/env bash
# Directive: a completed change set adds or modifies at least one
# receipts/issue-<N>.md. Intermediate feature-branch commits are not gated
# (issue #370). File-first issue #293: the receipt path is the issue anchor.
#
# Mode A — commit-msg hook: bash check.sh <msg-file>
#   Default-branch pending commit must stage a receipt (direct-to-default
#   completion). Feature-branch pending commits skip (intermediate).
# Mode B — CI / run.sh: bash check.sh
#   Aggregate merge-base..HEAD must include a receipt add/modify. Per-commit
#   receipt-touch is not required. No new work vs default → no-op.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "commit-issue-receipt-match"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1
MANIFEST="$(dirname "$0")/directive.yaml"
RECEIPTS_DIR="$(conf_get commit-issue-receipt-match RECEIPTS_DIR "$MANIFEST")"
ISSUE_RECEIPT_GLOB="$(conf_get commit-issue-receipt-match ISSUE_RECEIPT_GLOB "$MANIFEST")"

msg_has_waiver() {
    local msg="$1"
    printf '%s\n' "$msg" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-commit-issue-receipt-match[[:space:]]+.+'
}

touches_receipt() {
    local f
    for f in "$@"; do
        case "$f" in
            "$RECEIPTS_DIR"/$ISSUE_RECEIPT_GLOB) return 0 ;;
        esac
    done
    return 1
}

resolve_cs_base() {
    cs_base=""
    for candidate in origin/main origin/master main master; do
        if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
            mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
            if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD)" ]]; then
                cs_base="$mb"
                return 0
            fi
        fi
    done
    return 1
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        directive_end
    fi
    subject=$(grep -vE '^[[:space:]]*($|#)' "$msg_file" | head -n1)
    body=$(cat "$msg_file")

    [[ "$subject" == Merge\ * ]] && directive_end
    [[ "$subject" == Revert\ \"* ]] && directive_end
    if msg_has_waiver "$body"; then
        directive_end
    fi

    # Feature / detached HEAD: this commit is intermediate. CI Mode B checks
    # the completed change set. Direct-to-default (HEAD is main/master) has no
    # PR boundary, so the pending commit itself is the completed change.
    head_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$head_branch" != "main" && "$head_branch" != "master" ]]; then
        directive_end
    fi

    changed=()
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        changed+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACMR -- 2>/dev/null || true)

    if [[ ${#changed[@]} -eq 0 ]] || ! touches_receipt "${changed[@]}"; then
        violation "pending commit — completed change on the default branch touches no $RECEIPTS_DIR/$ISSUE_RECEIPT_GLOB (use 'governance: allow-commit-issue-receipt-match <reason>' for a deliberate exception such as a release commit)"
    fi
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh — aggregate base..HEAD
# ──────────────────────────────────────────────────────────────
if ! resolve_cs_base; then
    directive_end
fi

# Waiver on any commit in the change set covers the aggregate (release
# series, bot stacks). Merge/revert-only ranges still need a receipt if a
# non-merge non-revert commit landed without one and without a waiver.
range_waived=0
while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    parents=$(git log -1 --format=%P "$sha" 2>/dev/null || echo "")
    [[ "$parents" == *' '* ]] && continue
    subject=$(git log -1 --format=%s "$sha" 2>/dev/null || echo "")
    [[ "$subject" == Revert\ \"* ]] && continue
    body=$(git log -1 --format=%B "$sha" 2>/dev/null || echo "")
    if msg_has_waiver "$body"; then
        range_waived=1
        break
    fi
done < <(git log "$cs_base..HEAD" --format='%H')

if [[ "$range_waived" -eq 1 ]]; then
    directive_end
fi

changed=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    changed+=("$f")
done < <(git diff --name-only --diff-filter=ACMR "$cs_base"..HEAD -- 2>/dev/null || true)

if [[ ${#changed[@]} -eq 0 ]] || ! touches_receipt "${changed[@]}"; then
    violation "change set $cs_base..HEAD — completed change touches no $RECEIPTS_DIR/$ISSUE_RECEIPT_GLOB (intermediate commits need not each edit a receipt; the aggregate must. Waiver: 'governance: allow-commit-issue-receipt-match <reason>')"
fi

directive_end

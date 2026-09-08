#!/usr/bin/env bash
# Directive: unique issue receipts; completed changes carry outcome + verification
# evidence. A recorded fence or verdict is not proof of execution (issue #370).
#
# Always: filename issue-<N>[ -slug].md; unique issue numbers.
# Completed-change only (PR CI / direct-to-default pending commit):
#   non-stub receipts added in the change set need ## What changed, ## Verification
#   with recorded evidence, and ## Audit. Session stubs fail this boundary.
# Intermediate feature-branch commits: uniqueness/filename only.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "receipt-per-issue"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1
MANIFEST="$(dirname "$0")/directive.yaml"
RECEIPTS_DIR="$(conf_get receipt-per-issue RECEIPTS_DIR "$MANIFEST")"
RECEIPT_FILENAME_REGEX="$(conf_get receipt-per-issue RECEIPT_FILENAME_REGEX "$MANIFEST")"

if [[ ! -d "$ROOT/$RECEIPTS_DIR" ]]; then
    directive_end
fi

receipt_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    receipt_files+=("$f")
done < <(git ls-files -- "$RECEIPTS_DIR/*.md" 2>/dev/null || true)

if [[ ${#receipt_files[@]} -eq 0 ]]; then
    directive_end
fi

completed_sections=()
while IFS= read -r section; do [[ -n "$section" ]] && completed_sections+=("$section"); done \
    < <(conf_list receipt-per-issue "$MANIFEST" COMPLETED_SECTIONS)

has_receipt_waiver() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    head -n 10 "$file" 2>/dev/null \
        | sed -E 's/<!--//g; s/-->//g' \
        | grep -qE 'governance:[[:space:]]*allow-receipt-per-issue[[:space:]]+[^[:space:]]'
}

is_receipt_stub() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    local h2
    h2="$(grep -E '^##[[:space:]]+' "$file" 2>/dev/null \
        | sed -E 's/^##[[:space:]]+//; s/[[:space:]]+$//')"
    [[ "$h2" == "Session" || "$h2" == "Accounting" ]]
}

# Completed-change boundary (issue #370):
#   * default branch + staged files → direct-to-default completed commit
#   * not on default (feature/detached) + clean index + merge-base → PR/CI
#   * feature branch + staged files → intermediate (pre-commit on WIP)
#   * default branch + clean index → already on trunk; grandfather
on_default_branch() {
    local head
    head=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [[ "$head" == "main" || "$head" == "master" ]]
}
cs_base=""
for candidate in origin/main origin/master main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
        mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
        if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD 2>/dev/null)" ]]; then
            cs_base="$mb"
            break
        fi
    fi
done
staged_names="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"
completed_change=0
if on_default_branch && [[ -n "$staged_names" ]]; then
    completed_change=1
elif ! on_default_branch && [[ -z "$staged_names" && -n "$cs_base" ]]; then
    completed_change=1
fi

ADDED_RECEIPTS=$'\n'
add_to_scope() {
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$ADDED_RECEIPTS" in
            *$'\n'"$f"$'\n'*) ;;
            *) ADDED_RECEIPTS+="$f"$'\n' ;;
        esac
    done
}
add_to_scope < <(git diff --cached --no-renames --diff-filter=A --name-only -- "$RECEIPTS_DIR/*.md" 2>/dev/null || true)
if [[ -n "$cs_base" ]]; then
    add_to_scope < <(git diff --no-renames --diff-filter=A --name-only "$cs_base"..HEAD -- "$RECEIPTS_DIR/*.md" 2>/dev/null || true)
fi

receipt_in_scope() {
    case "$ADDED_RECEIPTS" in
        *$'\n'"$1"$'\n'*) return 0 ;;
        *) return 1 ;;
    esac
}

# Evidence: a fenced command plus an outcome token, or a durable pointer
# (http(s) URL). Presence is not proof of execution.
has_verification_evidence() {
    local body="$1"
    local has_fence=0 has_outcome=0 has_url=0
    printf '%s\n' "$body" | grep -qE '^[[:space:]]*```' && has_fence=1
    printf '%s\n' "$body" | grep -qiE '(^|[[:space:]])(pass(ed)?|fail(ed)?|ok|error|exit[[:space:]]*[0-9]+|green)([[:space:]]|$|[.:,])' && has_outcome=1
    printf '%s\n' "$body" | grep -qE 'https?://' && has_url=1
    if [[ "$has_url" -eq 1 ]]; then
        return 0
    fi
    [[ "$has_fence" -eq 1 && "$has_outcome" -eq 1 ]]
}

seen_nums=()
seen_files=()
for f in ${receipt_files[@]+"${receipt_files[@]}"}; do
    if has_receipt_waiver "$f"; then
        continue
    fi
    base="${f##*/}"
    issue_ref="${base#issue-}"; issue_ref="${issue_ref%%[-.]*}"
    [[ "$issue_ref" =~ ^[0-9]+$ ]] || issue_ref="<N>"

    if [[ "$base" =~ $RECEIPT_FILENAME_REGEX ]]; then
        num="${BASH_REMATCH[1]}"
        dup_of=""
        for i in ${seen_nums[@]+"${!seen_nums[@]}"}; do
            if [[ "${seen_nums[$i]}" == "$num" ]]; then
                dup_of="${seen_files[$i]}"
                break
            fi
        done
        if [[ -n "$dup_of" ]]; then
            violation "$f — issue #$num already has a receipt at $dup_of"
        else
            seen_nums+=("$num")
            seen_files+=("$f")
        fi
    else
        violation "$f — receipt filename must match 'issue-<N>.md' or optional 'issue-<N>-<slug>.md' (kebab-case slug)"
    fi

    if [[ "$completed_change" -ne 1 ]] || ! receipt_in_scope "$f"; then
        continue
    fi

    if is_receipt_stub "$f"; then
        violation "$f — session-only receipt stub cannot satisfy a completed change; add ## What changed and ## Verification evidence (a stub is valid on intermediate commits only)"
        continue
    fi

    for section in ${completed_sections[@]+"${completed_sections[@]}"}; do
        grep -qE "^##[[:space:]]+${section}\b" "$f" \
            || violation "$f — completed-change receipt is missing a '## ${section}' section"
    done

    if grep -qE "^##[[:space:]]+Verification\b" "$f"; then
        verif_body="$(extract_md_section "$f" "Verification")"
        if ! has_verification_evidence "$verif_body"; then
            violation "$f — ## Verification must record a command and its outcome (fence + pass/fail/exit) or a durable evidence URL; a fence alone is not evidence. This check does not prove the command ran."
        fi
    fi

    if declare -F judge_attest >/dev/null 2>&1; then
        judge_attest "$f"
    else
        require_attestation "$f" "Audit" \
            "Mechanical checks record that outcome and verification text exist; they do not prove the receipt matches the diff or that a command ran." \
            "the diff (\`git diff\`), this receipt, and the linked issue (\`gh issue view $issue_ref\`)" \
            "'## What changed' faithfully describes the outcome and significant behavior of the diff" \
            "verification evidence, if taken as true, would support the claimed outcome (a recorded fence or verdict is not proof of execution)" \
            "applicable acceptance criteria from the work item are met by the diff, or remaining gaps are named under Decisions/limitations"
    fi
done

directive_end

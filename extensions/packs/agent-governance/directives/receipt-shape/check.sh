#!/usr/bin/env bash
# Directive: Each tracked receipts/*.md file carries an `issue-<N>` token in
# its filename, no two receipts share the same issue number, and every
# receipt includes a `## Verification` section.
# Rationale: Receipts are the durable post-implementation audit trace for
# work an agent did against a GitHub issue — they record what was changed
# and how a reviewer can verify it. A one-to-one binding between receipt
# and issue keeps the system of record unambiguous; the Verification
# section forces the agent to name the criteria a reviewer uses to judge
# the work complete.
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "receipt-shape"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

if [[ ! -d "$ROOT/receipts" ]]; then
    directive_end
fi

receipt_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    receipt_files+=("$f")
done < <(git ls-files -- 'receipts/*.md' 2>/dev/null || true)

if [[ ${#receipt_files[@]} -eq 0 ]]; then
    directive_end
fi

seen_nums=()
seen_files=()
for f in "${receipt_files[@]}"; do
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
            violation "$f — issue #$num already has a receipt at $dup_of"
        else
            seen_nums+=("$num")
            seen_files+=("$f")
        fi
    else
        violation "$f — receipt filename must include an 'issue-<N>' token (e.g. receipts/issue-63-replace-plans.md)"
    fi

    if ! grep -qE '^##[[:space:]]+Verification\b' "$f"; then
        violation "$f — receipt is missing a '## Verification' section describing how completion will be judged"
    fi
done

directive_end

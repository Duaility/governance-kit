#!/usr/bin/env bash
# Governance test runner. Discovers every rule under ./rules/ and runs it.
# Exits 0 if all rules pass, 1 if any rule fails.
#
# Usage:
#   bash tests/governance/run.sh              # run all rules
#   bash tests/governance/run.sh no-secrets   # run a single rule by name
#
# Environment:
#   SKIP_GOVERNANCE=1   skip all rules (for emergency commits)

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    echo "⊘ governance skipped (SKIP_GOVERNANCE=1)"
    exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
RULES_DIR="$HERE/rules"

if [[ ! -d "$RULES_DIR" ]]; then
    echo "✗ no rules directory at $RULES_DIR"
    echo "  Is this repo bootstrapped? Run the governance-bootstrap skill."
    exit 1
fi

rule_files=()
while IFS= read -r f; do
    [[ -n "$f" ]] && rule_files+=("$f")
done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

if [[ ${#rule_files[@]} -eq 0 ]]; then
    echo "⊘ no governance rules defined in $RULES_DIR"
    exit 0
fi

# Single-rule filter: `run.sh no-secrets` only runs no-secrets.sh.
if [[ $# -gt 0 ]]; then
    filter="$1"
    filtered=()
    for f in "${rule_files[@]}"; do
        [[ "$(basename "$f" .sh)" == "$filter" ]] && filtered+=("$f")
    done
    if [[ ${#filtered[@]} -eq 0 ]]; then
        echo "✗ no rule named '$filter' under $RULES_DIR"
        exit 1
    fi
    rule_files=("${filtered[@]}")
fi

fail_count=0
pass_count=0
for rule in "${rule_files[@]}"; do
    if bash "$rule"; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
done

echo
echo "────────────────────────────────────────"
if [[ $fail_count -eq 0 ]]; then
    echo "✓ governance: all $pass_count rule(s) passed"
    exit 0
fi
echo "✗ governance: $fail_count rule(s) failed, $pass_count passed"
echo
echo "To bypass temporarily (CI will still enforce):"
echo "    SKIP_GOVERNANCE=1 git commit ..."
echo "    git commit --no-verify"
exit 1

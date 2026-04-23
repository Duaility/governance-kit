#!/usr/bin/env bash
# Rule: No leftover debug statements in tracked source files.
# Covers the common traps: console.log, debugger, print(, pdb, dbg!, fmt.Println.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "no-debug-statements"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Format: "<label>|<pattern>|<pathspec>"
# pathspec restricts where the pattern applies (so we don't flag print() in Python docs).
checks=(
    "console.log|console\.log\s*\(|*.js *.jsx *.ts *.tsx *.mjs *.cjs"
    "debugger statement|^[[:space:]]*debugger[[:space:]]*;?|*.js *.jsx *.ts *.tsx *.mjs *.cjs"
    "Python breakpoint|^[[:space:]]*breakpoint\s*\(|*.py"
    "pdb.set_trace|import pdb|*.py"
    "Rust dbg! macro|\bdbg!\s*\(|*.rs"
    "fmt.Println debug|^[[:space:]]*fmt\.Println\s*\(|*.go"
)

for entry in "${checks[@]}"; do
    IFS='|' read -r label pattern pathspec <<<"$entry"
    # shellcheck disable=SC2206
    pathspec_args=($pathspec)
    while IFS=: read -r file line_no _; do
        [[ -z "$file" ]] && continue
        # Skip this rule file (contains the patterns).
        [[ "$file" == tests/governance/rules/no-debug-statements/* ]] && continue
        # Skip test files — debug output in tests is sometimes legitimate.
        [[ "$file" == *_test.* ]] && continue
        [[ "$file" == *.test.* ]] && continue
        [[ "$file" == *test_*.py ]] && continue
        [[ "$file" == tests/* ]] && continue
        has_waiver "$file" "$line_no" "no-debug-statements" && continue
        violation "$file:$line_no — $label"
    done < <(git grep -InE "$pattern" -- "${pathspec_args[@]}" 2>/dev/null || true)
done

rule_end

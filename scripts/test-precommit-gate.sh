#!/usr/bin/env bash
# scripts/test-precommit-gate.sh — the governance-kit source repo's local
# pre-commit hook runs the kit-internal test umbrella (scripts/test.sh), which
# fans out to every product-code test layer. Ported from the former dogfood
# directive `pre-commit-test-gate` (issue #251): it guards THIS repo's own hook
# wiring, not a consumer's repo state, so it lives in the umbrella it guards.
#
# Self-referential by design: this layer is run *by* scripts/test.sh and asserts
# that test.sh both exists in the hook and wires every required layer (including
# the three checks moved out of the dogfood directive set in #251).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

hook=".githooks/pre-commit"
umbrella="scripts/test.sh"
required_layers=(
    "scripts/test-packctl.py"
    "scripts/test-packctl-validate.py"
    "scripts/test-packverb.py"
    "scripts/test-install-sh.sh"
    "scripts/test-hooks-sh.sh"
    "scripts/test-runtime.sh"
    "scripts/test-packs.sh"
    "scripts/test-digestlib.py"
    "scripts/test-kit-version-consistency.sh"
    "scripts/test-precommit-gate.sh"
    "scripts/test-conf-knob-doc-sync.sh"
)

fail=0
note() { printf '  ✗ %s\n' "$1" >&2; fail=1; }

if [[ ! -f "$umbrella" ]]; then
    note "$umbrella is missing; kit tests cannot be enforced before commit"
    exit $fail
fi
[[ -x "$umbrella" ]] || note "$umbrella exists but is not executable"

if [[ ! -f "$hook" ]]; then
    note "$hook is missing; kit tests cannot be enforced before commit"
elif [[ ! -x "$hook" ]]; then
    note "$hook exists but is not executable"
elif ! grep -Fq "$umbrella" "$hook"; then
    note "$hook must invoke $umbrella so kit tests run before commit"
fi

for layer in "${required_layers[@]}"; do
    if [[ ! -f "$layer" ]]; then
        note "$layer is missing; expected as a layer of $umbrella"
        continue
    fi
    grep -Fq "$layer" "$umbrella" || note "$umbrella must invoke $layer"
done

if [[ $fail -eq 0 ]]; then
    printf '  ✓ pre-commit-test-gate: hook runs %s and every required layer is wired\n' "$umbrella"
fi
exit $fail

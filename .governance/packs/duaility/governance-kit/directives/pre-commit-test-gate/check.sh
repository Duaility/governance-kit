#!/usr/bin/env bash
# Directive: The governance-kit source repo's local pre-commit hook runs the
# kit-internal test umbrella (scripts/test.sh), which fans out to every
# product-code test layer — packctl/packverb unit tests, install.sh / hooks.sh
# helper tests, the shipped-runtime tests, and the pack smoke + evals.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "pre-commit-test-gate"
require_git

ROOT="$(git rev-parse --show-toplevel)"
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
)

if [[ ! -f "$umbrella" ]]; then
    directive_end
fi

if [[ ! -x "$umbrella" ]]; then
    violation "$umbrella exists but is not executable"
fi

if [[ ! -f "$hook" ]]; then
    violation "$hook is missing; kit tests cannot be enforced before commit"
elif [[ ! -x "$hook" ]]; then
    violation "$hook exists but is not executable"
elif ! grep -Fq "$umbrella" "$hook"; then
    violation "$hook must invoke $umbrella so kit tests run before commit"
fi

for layer in "${required_layers[@]}"; do
    if [[ ! -f "$layer" ]]; then
        violation "$layer is missing; expected as a layer of $umbrella"
        continue
    fi
    if ! grep -Fq "$layer" "$umbrella"; then
        violation "$umbrella must invoke $layer"
    fi
done

directive_end

#!/usr/bin/env bash
# Rule: Local git hooks live in `.githooks/` (tracked) and `core.hooksPath`
# is set to `.githooks` so they actually fire. The `commit-msg` hook is only
# required if `conventional-commits` is installed.
# Rationale: Hooks in `.git/hooks/` are per-clone and untracked. Without this
# rule, a fresh clone has zero local enforcement until someone re-runs
# bootstrap, and CI is the only thing catching violations. This rule turns
# that silent failure into a noisy one on the very next commit.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "hooks-configured"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# 1. .githooks/pre-commit must be tracked and executable.
if ! git ls-files --error-unmatch .githooks/pre-commit >/dev/null 2>&1; then
    violation ".githooks/pre-commit is not tracked — bootstrap should ship it"
elif [[ ! -x .githooks/pre-commit ]]; then
    violation ".githooks/pre-commit exists but is not executable (chmod +x .githooks/pre-commit)"
fi

# 2. .githooks/commit-msg required only if conventional-commits is installed.
if [[ -f tests/governance/rules/conventional-commits.sh ]]; then
    if ! git ls-files --error-unmatch .githooks/commit-msg >/dev/null 2>&1; then
        violation ".githooks/commit-msg is not tracked — required because conventional-commits is installed"
    elif [[ ! -x .githooks/commit-msg ]]; then
        violation ".githooks/commit-msg exists but is not executable (chmod +x .githooks/commit-msg)"
    fi
fi

# 3. core.hooksPath must point at .githooks. This is per-clone config; the
# rule's whole job is to nag until it's set.
# Skip in CI: runners clone fresh and invoke the suite directly (not via the
# hook), so checking their core.hooksPath is meaningless. The tracked +
# executable checks above still run there.
if [[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]; then
    configured="$(git config --get core.hooksPath 2>/dev/null || true)"
    if [[ "$configured" != ".githooks" ]]; then
        if [[ -z "$configured" ]]; then
            violation "core.hooksPath is not set — run: git config core.hooksPath .githooks"
        else
            violation "core.hooksPath is '$configured' — expected '.githooks' (run: git config core.hooksPath .githooks)"
        fi
    fi
fi

rule_end

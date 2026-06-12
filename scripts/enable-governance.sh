#!/usr/bin/env bash
# governance-kit:managed kit-version=0.7.2
# Enable governance-kit for this clone.
#
# Points git at the tracked .githooks/ directory. Safe to re-run — git
# overwrites the existing value. Worktrees inherit .git/config from their
# parent checkout, so this only needs to run once per clone, not per worktree.

set -eu

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ ! -d .githooks ]]; then
    echo "enable-governance: no .githooks/ directory — is governance-kit bootstrapped in this repo?" >&2
    exit 1
fi

git config core.hooksPath .githooks

current="$(git config --get core.hooksPath)"
echo "enable-governance: core.hooksPath=$current"

# No reconcile step: directive trees are committed (vendored) under
# .governance/packs/, so a fresh clone already has them. That tree is Lane 1 of
# the dogfood (issue #200) — an honest customer pinned at released tags — and is
# re-materialized only by `governance pack update` in a post-release PR, never
# hand-edited. Editing a directive touches packs/ only; Lane 2 (dogfood-smoke.yml)
# smoke-tests the change against this repo on every PR.

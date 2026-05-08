#!/usr/bin/env bash
# governance-kit:managed kit-version=0.2 generated=2026-05-08
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

# Materialize directive folders for every `source: gh` entry in packs.lock.
# Those trees are gitignored (reconstructable artifacts), so without this
# step `.governance/run.sh` would only see committed `source: local` packs.
# Re-run after pulling lockfile changes.
if [[ -f .governance/packs.lock ]]; then
    bash governance/assets/packs/lib/reconcile.sh "$ROOT"
fi

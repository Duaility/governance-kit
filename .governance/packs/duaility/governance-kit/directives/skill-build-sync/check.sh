#!/usr/bin/env bash
# Directive: skill-build-sync (dogfood) — the committed published-skill tree
# (skill/) is byte-identical to what scripts/build-skill.sh derives from
# governance/. skill/SKILL.md is source and exempt; skill/assets/** is derived.
# Without this check the vendored engine lib / version anchor could silently
# drift from the kit sources and `npx skills` would ship stale code.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "skill-build-sync"
require_git
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

if [[ ! -f scripts/build-skill.sh ]]; then
    violation "scripts/build-skill.sh is missing — the published skill tree cannot be reproduced"
elif [[ ! -f skill/SKILL.md ]]; then
    violation "skill/SKILL.md is missing — nothing for npx skills to install"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    if ! bash scripts/build-skill.sh "$tmp/skill" >/dev/null 2>&1; then
        violation "scripts/build-skill.sh failed to assemble the skill tree"
    else
        # Compare the derived subtree only (SKILL.md is source, not derived).
        if ! diff -r "$tmp/skill/assets" "skill/assets" >/dev/null 2>&1; then
            drift="$(diff -rq "$tmp/skill/assets" "skill/assets" 2>&1 | head -5)"
            violation "skill/assets drifted from governance/ sources — run: bash scripts/build-skill.sh
${drift}"
        fi
    fi
fi

directive_end

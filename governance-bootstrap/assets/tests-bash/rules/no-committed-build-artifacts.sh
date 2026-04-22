#!/usr/bin/env bash
# Rule: No common build artifacts are tracked in the repo.
# Only flags unambiguous artifacts — things that are almost never intentionally
# checked in. Deliberately excludes .so / .jar / .dll because some projects
# legitimately ship those.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-committed-build-artifacts"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# (pattern, label) pairs.
checks=(
    '*.pyc|Python bytecode'
    '*.pyo|Python optimized bytecode'
    '__pycache__/**|Python cache dir'
    '*.class|Java class file'
    '*.o|compiled object file'
    'node_modules/**|node_modules committed'
    'dist/**|dist/ build output'
    'build/**|build/ output'
    'target/**|target/ (JVM / Rust) build output'
    'out/**|out/ build output'
    '.DS_Store|macOS metadata'
    'Thumbs.db|Windows metadata'
    '*.swp|editor swap file'
    '*.swo|editor swap file'
)

for entry in "${checks[@]}"; do
    IFS='|' read -r pattern label <<<"$entry"
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        violation "$f — $label"
    done < <(git ls-files -- "$pattern" 2>/dev/null || true)
done

rule_end

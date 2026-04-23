#!/usr/bin/env bash
# Rule: No tracked source file exceeds the line-count limit.
# Default 500 lines. Override with GOVERNANCE_FILE_SIZE_LIMIT in the environment.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "file-size-limit"
require_git

LIMIT="${GOVERNANCE_FILE_SIZE_LIMIT:-500}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Source extensions we care about. Tweak this list as the project's stack dictates.
extensions=(
    "*.py" "*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs"
    "*.go" "*.rs" "*.rb" "*.java" "*.kt" "*.scala"
    "*.c" "*.cc" "*.cpp" "*.h" "*.hpp"
    "*.swift" "*.php" "*.cs"
)

# Excludes: vendor, generated, migrations, lock files.
excludes=(
    ":!vendor/**"
    ":!**/node_modules/**"
    ":!**/generated/**"
    ":!**/*_pb2.py"
    ":!**/*.pb.go"
    ":!**/migrations/**"
)

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ ! -f "$file" ]] && continue
    lines=$(wc -l < "$file" | tr -d ' ')
    if [[ "$lines" -gt "$LIMIT" ]]; then
        violation "$file — $lines lines (limit: $LIMIT)"
    fi
done < <(git ls-files -- "${extensions[@]}" "${excludes[@]}" 2>/dev/null || true)

rule_end

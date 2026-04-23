#!/usr/bin/env bash
# Rule: README.md exists at repo root with at least a top-level heading and one paragraph.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "readme-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
FILE=""
for candidate in "$ROOT/README.md" "$ROOT/README" "$ROOT/README.rst"; do
    [[ -f "$candidate" ]] && { FILE="$candidate"; break; }
done

if [[ -z "$FILE" ]]; then
    violation "no README.md / README / README.rst at repo root"
    rule_end
fi

if ! grep -qE '^#[^#]' "$FILE" 2>/dev/null && ! grep -qE '^=+$' "$FILE" 2>/dev/null; then
    violation "$FILE has no top-level heading"
fi

if [[ $(wc -w < "$FILE") -lt 30 ]]; then
    violation "$FILE has fewer than 30 words — looks like a stub"
fi

rule_end

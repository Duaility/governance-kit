#!/usr/bin/env bash
# Rule: A LICENSE file exists at the repo root.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "license-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
found=""
for candidate in LICENSE LICENSE.md LICENSE.txt COPYING COPYING.md; do
    [[ -f "$ROOT/$candidate" ]] && { found="$candidate"; break; }
done

if [[ -z "$found" ]]; then
    violation "no LICENSE file at repo root (looked for LICENSE, LICENSE.md, LICENSE.txt, COPYING, COPYING.md)"
elif [[ ! -s "$ROOT/$found" ]]; then
    violation "$found exists but is empty"
fi

rule_end

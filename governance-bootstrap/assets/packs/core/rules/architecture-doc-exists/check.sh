#!/usr/bin/env bash
# Rule: ARCHITECTURE.md exists and is substantive.
# Rationale: The harness-engineering "top-level map of domains and package
# layering". Without it, agents lack a mental model of the repo.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "architecture-doc-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
FILE=""
for candidate in ARCHITECTURE.md docs/ARCHITECTURE.md ARCHITECTURE.rst docs/architecture.md; do
    [[ -f "$ROOT/$candidate" ]] && { FILE="$ROOT/$candidate"; break; }
done

if [[ -z "$FILE" ]]; then
    violation "no ARCHITECTURE.md (looked at: ARCHITECTURE.md, docs/ARCHITECTURE.md, ARCHITECTURE.rst, docs/architecture.md)"
    rule_end
fi

if [[ ! -s "$FILE" ]]; then
    violation "$FILE exists but is empty"
    rule_end
fi

lines=$(wc -l < "$FILE" | tr -d ' ')
MIN_LINES="${GOVERNANCE_ARCHITECTURE_MIN:-20}"
if [[ $lines -lt $MIN_LINES ]]; then
    violation "$FILE has $lines lines — looks like a stub (min: $MIN_LINES)"
fi

rule_end

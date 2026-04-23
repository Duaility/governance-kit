#!/usr/bin/env bash
# Rule: <one-sentence statement of the rule>
# Rationale: <why this matters — link incident / policy / constraint if possible>
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "<rule-name>"    # MUST match the filename without .sh
require_git                  # remove if the rule does not touch git

# ──────────────────────────────────────────────────────────────
# The check goes here. Patterns:
#
# (a) File-level existence/content:
#   [[ -f "$ROOT/FILE" ]] || violation "FILE missing"
#
# (b) Per-line grep over tracked files:
#   while IFS=: read -r file line_no match; do
#       [[ -z "$file" ]] && continue
#       has_waiver "$file" "$line_no" "<rule-name>" && continue
#       violation "$file:$line_no — <what went wrong>"
#   done < <(git grep -nE '<pattern>' -- '<pathspec>' 2>/dev/null || true)
#
# (c) Per-file metric:
#   while IFS= read -r f; do
#       [[ -z "$f" ]] && continue
#       # compute metric and call violation if bad
#   done < <(git ls-files -- '<pathspec>' 2>/dev/null || true)
# ──────────────────────────────────────────────────────────────

rule_end

#!/usr/bin/env bash
# Directive: <one-sentence statement of the directive>
# Rationale: <why this matters — link incident / policy / constraint if possible>
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "<directive-name>"    # MUST match the folder name
require_git                            # remove if the directive does not touch git

# ──────────────────────────────────────────────────────────────
# The check goes here. Patterns:
#
# (a) File-level existence/content:
#   [[ -f "$ROOT/FILE" ]] || violation "FILE missing"
#
# (b) Per-line grep over tracked files:
#   while IFS=: read -r file line_no match; do
#       [[ -z "$file" ]] && continue
#       has_waiver "$file" "$line_no" "<directive-name>" && continue
#       violation "$file:$line_no — <what went wrong>"
#   done < <(git grep -nE '<pattern>' -- '<pathspec>' 2>/dev/null || true)
#
# (c) Per-file metric:
#   while IFS= read -r f; do
#       [[ -z "$f" ]] && continue
#       # compute metric and call violation if bad
#   done < <(git ls-files -- '<pathspec>' 2>/dev/null || true)
# ──────────────────────────────────────────────────────────────

directive_end

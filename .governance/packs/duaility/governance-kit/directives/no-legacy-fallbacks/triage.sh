#!/usr/bin/env bash
# triage.sh — candidate-hunk emitter for the no-legacy-fallbacks sweep directive.
#
# Contract (issue #142): the sweep engine sets SWEEP_RANGE (a git `A..B` range)
# and GOVERNANCE_ROOT (the repo root), runs this script at the repo root, and
# reads `path:line` candidate locations from stdout — one per line. Empty output
# means "nothing to adjudicate" and costs the engine zero inference requests.
#
# Triage is a CHEAP grep pre-filter, never the verdict. It narrows the model's
# attention to changed files carrying a possible legacy-fallback smell; the
# engine then adjudicates each candidate hunk against constitution.md. Over-
# inclusion here is fine (the judge rejects false smoke); under-inclusion is the
# real risk, so the pattern is deliberately broad.
set -u

RANGE="${SWEEP_RANGE:-}"
[[ -z "$RANGE" ]] && exit 0

# Smell terms for retained old code paths. Intentionally broad; the judge, not
# this grep, decides whether a match is an actual violation.
PATTERN='backward[ -]?compat|back[ -]?compat|legacy|fall[ -]?back|deprecat|for compatibility|compat shim|ImportError|old (path|behaviou?r)|removed after'

# Restrict to files the range actually touched, then grep their current content
# (the checkout is at B), emitting file:line. Skip the governance tree and this
# pack's own fixtures so the directive never flags itself.
git diff --name-only "$RANGE" 2>/dev/null \
  | while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] || continue
        case "$f" in
            .governance/*|*/evals/*|packs/architecture/*) continue ;;
        esac
        grep -nIE "$PATTERN" -- "$f" 2>/dev/null | awk -F: -v f="$f" '{print f ":" $1}'
    done

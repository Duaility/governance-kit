#!/usr/bin/env bash
# triage.sh — candidate-hunk emitter for the no-path-bifurcation sweep directive.
#
# Contract (issue #142): the sweep engine sets SWEEP_RANGE (a git `A..B` range)
# and GOVERNANCE_ROOT (the repo root), runs this at the repo root, and reads
# `path:line` candidate locations from stdout — one per line. Empty output means
# "nothing to adjudicate".
#
# Triage is a CHEAP grep pre-filter, never the verdict. It surfaces changed files
# that show a possible fork/dual-path smell; the engine then adjudicates each
# candidate hunk against constitution.md. Over-inclusion is fine; the judge
# rejects false smoke.
set -u

RANGE="${SWEEP_RANGE:-}"
[[ -z "$RANGE" ]] && exit 0

# Smell terms for parallel/forked code paths. Broad by design.
PATTERN='bifurcat|dual[ -]?dispatch|dual[ -]?path|local[ -_]?only|special[ -_]?case|fast path|if .*\blocal\b|elif .*(transport|backend|mode|protocol)|two code paths|parallel path'

git diff --name-only "$RANGE" 2>/dev/null \
  | while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] || continue
        case "$f" in
            .governance/*|*/evals/*|packs/architecture/*) continue ;;
        esac
        grep -nIE "$PATTERN" -- "$f" 2>/dev/null | awk -F: -v f="$f" '{print f ":" $1}'
    done

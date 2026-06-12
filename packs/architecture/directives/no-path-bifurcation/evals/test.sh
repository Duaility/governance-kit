#!/usr/bin/env bash
# Calibration eval for a sweep directive — the "no eval, no ship" gate (#142).
# Runs the real judge against labelled fixtures (evals/violating/* +
# evals/clean/*) and fails below a precision/recall floor. CI uses the
# deterministic echo stub; set GOVERNANCE_SWEEP_JUDGE=github-models + a token to
# measure the real model on demand.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(dirname "$HERE")"                       # the directive folder
ROOT="$(cd "$HERE/../../../../.." && pwd)"     # repo root
ENGINE="$ROOT/kit/assets/dot-governance/sweep.py"
[[ -f "$ENGINE" ]] || { echo "eval: sweep engine missing at $ENGINE" >&2; exit 1; }

JUDGE="${GOVERNANCE_SWEEP_JUDGE:-echo}"
python3 "$ENGINE" eval --directive-dir "$DIR" --judge "$JUDGE" \
    --min-precision 0.8 --min-recall 0.8

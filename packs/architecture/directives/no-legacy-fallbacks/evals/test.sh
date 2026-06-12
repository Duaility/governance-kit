#!/usr/bin/env bash
# Calibration eval for a sweep directive — the "no eval, no ship" gate (#142).
#
# Unlike a check.sh directive's eval (pass/fail fixtures through a git fixture
# repo), a sweep directive's eval runs the REAL judge against labelled
# calibration fixtures (evals/violating/* + evals/clean/*) and fails below a
# precision/recall floor. In CI we use the deterministic echo stub (no inference
# spend, no secret); run with GOVERNANCE_SWEEP_JUDGE=github-models + a token to
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

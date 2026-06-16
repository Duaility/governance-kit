#!/usr/bin/env bash
# Directive: detected human-steering events (interrupts, classifier-confirmed
# corrections) are recorded as rows under `## Accounting` → `### Steering` in
# the issue's receipt (`receipts/issue-<N>.md`), and that ledger is well-formed.
#
# Issue #293 retired the per-commit summary trailers (Steer-Count / Steer-Types
# / Steer-Tiers). They were a `git log`-skimmable copy of facts already in the
# receipt rows; their only enforced contract was "the stamped count equals the
# rows this commit staged" — a self-referential check that becomes vacuous once
# the stamp is gone. Steering completeness was always best-effort regardless:
# the pre-commit extractor is non-blocking (a transient classifier failure
# never blocks a commit), so the directive never guaranteed "every transcript
# event is recorded", only that whatever rows exist are valid. That invariant
# is exactly what `validate-dir` enforces — and it now stands on its own.
#
# Steering rows are well-formed — v2 is 9 columns
# (`steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp`).
# `validate-dir` checks per-row shape, type/tier in the allowed sets, the
# receipt-homed issue, append-only epoch order, per-session `ordinal`
# strict-increase, global steer-key uniqueness, and cross-receipt
# `(session, ordinal)` identity (a duplicate is a cross-branch re-append).
# Legacy v1 rows (7 columns, no ordinal/timestamp) parse and validate to the v1
# rules and are excluded from the ordinal checks.
#
# Modes:
#   Mode A — commit-msg hook:  bash check.sh <path-to-msg-file>
#   Mode B — CI / run.sh:      bash check.sh
#   Both run the same repo-wide ledger-shape check. There is no per-commit
#   contract left to enforce on the message itself; the pre-commit hook
#   (hooks/pre-commit.sh) does the row extraction + append as a side effect.
#
# Ledger row I/O lives in sibling lib/ledger.py; two-tier event detection in
# lib/extract.py; per-repo knobs in lib/conf.py.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "agent-steering-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
RECEIPTS_DIR="$ROOT/receipts"
LIB="$HERE/lib"

if [[ ! -f "$LIB/ledger.py" ]]; then
    violation "directive folder is missing lib/ledger.py — cannot validate"
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Receipt steering-ledger shape check (independent of any commit). Runs in both
# modes — the only contract the directive enforces now that the per-commit
# summary trailers are retired (issue #293).
# ──────────────────────────────────────────────────────────────
if [[ -d "$RECEIPTS_DIR" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(python3 "$LIB/ledger.py" validate-dir "$RECEIPTS_DIR" || true)
fi

directive_end

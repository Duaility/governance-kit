# Plan — issue-35: Harden agent-token-accounting + UX improvements

Closes [#35](https://github.com/Duaility/governance-kit/issues/35).

## Goal

Close the "unpriced model" gap that left rows 101–102 of the ledger with
real token usage but no dollar figure, surface per-commit cost in `git log`
without joining against `COSTS.md`, and stop emitting raw ANSI escapes
under `TERM=dumb` / stripped CI.

## Steps

1. **Family-prefix fallbacks in `lib/rates.py`** — add `claude-opus`,
   `claude-sonnet`, `claude-haiku`, and `gpt-5` family rows seeded from
   the current rate card. Rename bare `claude-opus-4` / `claude-sonnet-4`
   to `-4-0` so longest-prefix matching picks the family row (not stale
   4.0 pricing) for future `-4-8` / `-5-0` minors. Add a `rates.py cost`
   CLI so the hook and ledger row are computed from one call.
2. **`Cost-USD` as a required commit trailer** — pre-commit computes once,
   hands off `AGENT_COST_USD`; `prepare-commit-msg` stamps `Cost-USD:`
   unconditionally (no more optional-path); `trailers.py` adds it to
   `REQUIRED_TRAILERS` and cross-checks against the ledger's `cost-usd`
   cell via extended `find-by-cost-key` output. `ledger.py validate`
   requires non-empty `cost_usd` on v3 rows whose `model` is set —
   legacy v1/v2 and pre-mandate v3 rows (empty `model`) stay
   grandfathered. The constitution's trailer list grows to eight, and
   the cost-usd column spec drops its "either empty" clause for
   model-named rows.
3. **Unpriced models block the commit** — when `compute_cost_usd`
   returns `None`, `rates.py cost` exits 3 with a human-readable
   reason; pre-commit prints a red `✗` error and fails. The operator
   either adds a family-prefix row to `lib/rates.py` or uses
   `SKIP_GOVERNANCE=1` for a one-off hot-fix.
4. **`tput` in `tests/governance/lib.sh`** — swap raw `\033[…]` for
   `tput setaf`/`bold`/`sgr0`, gated on `-t 1` + tput probe. Same change
   in `governance/assets/tests-bash/lib.sh` so bootstrap-generated copies
   pick it up. `TERM=dumb` and piped invocations verified clean.
5. **`commit-issue-plan-match`: accept body `Issue:` trailers** — squash
   merges naturally carry a PR-number subject while the folded
   sub-commits preserve their original `Issue: #N` trailers. Treating
   those trailers as legitimate anchors (union'd with the subject
   `(#N)`) prevents false-positives on post-squash history where the
   plan is correctly for the underlying issue. Follow-up surfaced while
   verifying the rest of the work; landed in the same amendment.

## Acceptance

- `gpt-5.5`-class minors land a non-empty `cost-usd` cell by default.
- Every agent commit carries a required `Cost-USD` trailer matching its
  ledger row (trailer missing → rule violation; ledger row empty for a
  v3 model-named row → rule violation).
- Truly-unpriced model → pre-commit fails hard with a red `✗` message.
- Governance suite output renders cleanly under `TERM=dumb` / piped.
- `commit-issue-plan-match` passes on squash-merged history where the
  subject `(#N)` is a PR id and the body carries the real `Issue: #N`.
- Existing v3 rows on `main` with a non-empty `model` but empty
  `cost-usd` are backfilled (rows 101–102, gpt-5.5) using the new
  family-prefix price so the ledger validator stays clean.
- `scripts/test-packs.sh` green (12/12 evals); `tests/governance/run.sh`
  green (12/12 rules).

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
2. **`Cost-USD` commit trailer** — pre-commit computes once, hands off
   `AGENT_COST_USD`; `prepare-commit-msg` stamps `Cost-USD:` only when
   non-empty (no `0.0000` sentinel); `trailers.py` cross-checks against
   the ledger's `cost-usd` cell via extended `find-by-cost-key` output.
3. **Loud-but-non-blocking warning** — when `compute_cost_usd` returns
   `None`, pre-commit prints a `tput`-colored `warning: model 'X' not in
   rate table` line to stderr. Ledger row stays valid; the gap is no
   longer silent.
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
- Every priced commit carries a `Cost-USD` trailer matching its row.
- Unpriced model → visible `warning:` on stderr, commit still succeeds.
- Governance suite output renders cleanly under `TERM=dumb` / piped.
- `commit-issue-plan-match` passes on squash-merged history where the
  subject `(#N)` is a PR id and the body carries the real `Issue: #N`.
- `scripts/test-packs.sh` green (12/12 evals); `tests/governance/run.sh`
  green (12/12 rules).

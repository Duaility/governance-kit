# issue-136 — token-accounting sibling: per-block trailers + Mode B HEAD fallback

Closes the squash-merge sibling concern flagged in
[#136](https://github.com/Duaility/governance-kit/issues/136). #136 itself
shipped via [#137](https://github.com/Duaility/governance-kit/pull/137) for
the steering directive; this receipt covers the analogous fix for
`agent-token-accounting`, which manifests with a different bug shape (silent
skip of cross-checks rather than math disagreement).

## Checklist

- [x] Per-block trailer validation
- [x] Mode B HEAD fallback on main
- [x] Constitution snippet mirrors updated
- [x] Reference doc
- [x] Evolution log entry
- [x] Pack evals extended

## What changed

- **Per-block trailer validation.** `packs/core/directives/agent-token-accounting/lib/trailers.py` is rewritten around `extract_trailer_blocks(msg)` and a new `validate-blocks` CLI. The body is split into trailer-only paragraphs (one per folded sub-commit on a squash) and each `(block, COSTS.md row)` pair anchored by `Cost-Key` is cross-checked. The pre-fix `awk '/^Cost-Key:/ {val=$2} END {print val}'` extraction in `check.sh` was last-wins across the whole body, so on a squash only the trailing sub-commit's row got cross-checked and every earlier sub-commit's row landed in `COSTS.md` silently unverified.
- **Mode B HEAD fallback on main.** `packs/core/directives/agent-token-accounting/check.sh` previously returned early when `base..HEAD` was empty, deliberately avoiding "re-flag historical commits". The consequence was that squash-merge commits on `main` (which the local commit-msg hook never sees — squash happens on GitHub's server) had their per-Cost-Key trailers entirely unchecked. Mirror the steering directive's #132 pattern: when no base ref resolves, fall through to validating HEAD's trailer blocks on their own.
- **Bash-side simplification.** The pre-fix `check.sh` pre-extracted the Cost-Key and pre-fetched the matching ledger row by calling `lib/ledger.py find-by-cost-key`, then passed the row columns as positional args to `lib/trailers.py validate`. With per-block validation that loop would N times round-trip through bash, so the ledger lookup moved into Python. `lib/ledger.py find-by-cost-key` is kept for potential debug use.
- **Constitution snippet mirrors updated.** Both `packs/core/directives/agent-token-accounting/constitution.md` (the pack source) and the matching subsection in root `CONSTITUTION.md` gain a "Per-block validation" sentence in `Enforced by` and a "Mode B on main actively validates HEAD's trailer blocks" sentence in `Exceptions`.
- **Reference doc.** `governance/references/AGENT_TOKEN_ACCOUNTING.md` updates the `lib/trailers.py` and `check.sh` rows to describe the new per-block flow and the Mode B HEAD-fallback.
- **Evolution log entry** added to `CONSTITUTION.md`.
- **Pack evals extended.** `packs/core/directives/agent-token-accounting/evals/test.sh` grows from 3 → 11 cases: matched-row pass, missing-row fail, trailer-vs-row math mismatch, squash-pair pass, squash-with-earlier-row-missing fail, prose-mixed-with-trailers fail, and the Mode-B-on-main pass + fail pair.

## Out of scope

- The steering directive's parser fix (shipped separately in #137).
- Cosmetic drift between root `CONSTITUTION.md` and the directive folder's `constitution.md` for the token directive (the root mirror was missing the unsupported-runtime waiver clause + install-commit caveat). Out of scope for this fix.
- Bumping the core pack version. Pre-1.0 internal CLI rename (`validate` → `validate-blocks`) has no external consumers — the only caller was `check.sh`, updated in the same commit. V0 stance applies.

## Verification

- `bash packs/core/directives/agent-token-accounting/evals/test.sh` → all 11 cases pass (3 pre-existing + 8 new). Notable: `squash-merge-both-blocks-verified` (per-block validation pass), `squash-merge-earlier-row-missing` (the case that previously slipped past last-wins), `mode-b-on-main-valid` / `mode-b-on-main-missing-agent` (HEAD-fallback enforcement).
- `bash scripts/test-packs.sh` → 14 directives green, all evals pass.
- `bash .governance/run.sh` → dogfood suite green (`pre-commit-test-gate` passes; the kit's own core directives flag the development commit itself per the kit-author waiver convention — see commit body for `governance: allow-...` tokens).

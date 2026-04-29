<!-- governance: allow-plan-validation legacy -->
# Make `agent-token-accounting` mandatory on every non-merge commit

Tracks [#17](https://github.com/Duaility/governance-kit/issues/17).

## Goal

Flip `agent-token-accounting` from opt-in (only commits that already declare an `Agent:` trailer are checked) to **mandatory** (every non-merge, non-revert commit on a branch must carry the full trailer set and a matching `COSTS.md` row). This repo is agent-driven only; an untrailered commit is a bug, not an allowed mode. Without this change the ledger is best-effort and a human-authored or trailer-less agent commit lands with zero token provenance and the rule is silent.

## Steps

1. **Test:** in `.governance/rules/agent-token-accounting.sh`, replace the early-exit (`grep -qE '^Agent:' || return 0`) with a `violation` that fires whenever an in-scope commit lacks an `Agent:` trailer.
2. **Test:** add an `is_exempt_commit` helper that returns true for merge commits (`git log --format=%P` shows >1 parent) and revert commits (subject starts with `Revert "`). Mode B's per-sha walk and the `merge-base == HEAD` fallback skip exempt commits; Mode A's commit-msg path skips revert subjects (merges don't reach commit-msg).
3. **Test (latent bug):** switch the per-commit invocation from `printf '%s' "$msg" | validate_commit_message "$label"` to `validate_commit_message "$label" <<<"$msg"`. The pipe runs the function in a subshell, so its `violation` calls were lost — that's why the rule appeared green even on commits that should fail. The here-string keeps everything in the current shell.
4. **Test (scope correction):** when `merge-base..HEAD` is empty, exit clean instead of falling back to validating HEAD alone. The fallback was a smoke-test convenience under opt-in semantics; under mandatory semantics it would re-flag historical commits already on `main`, which are explicitly out of scope. Mode A still validates the pending commit on every commit-msg invocation.
5. **Constitution:** in `CONSTITUTION.md`, rewrite the **Rule** to say "every non-merge, non-revert commit carries the full trailer set" (drop the "every commit carrying an `Agent:` trailer" framing), update **Exceptions** to "Merge commits and revert commits are exempt", and tighten the rationale — the rule is no longer a "no-op on human commits"; the agent-driven-only invariant is now mechanically enforced.
6. **Constitution:** append an Evolution Log entry dated 2026-04-23 capturing the flip, the merge/revert exemption, the latent subshell-bug fix, and the empty-range scope correction.
7. **Plan:** this file (per the `plan-per-issue` rule).
8. **Verify:** run `bash .governance/run.sh` locally — should pass clean on this branch (no commits ahead of `origin/main`, so Mode B is a no-op). On feature branches with new commits, Mode B walks them and the runtime-aware pre-commit hook stamps trailers; bypass with `SKIP_GOVERNANCE=1` only for the migration window described below.

## Migration notes

- **In-flight branches without trailers will fail CI after this lands.** Contributors need to re-commit through the runtime-aware pre-commit hook (which already auto-generates trailers + ledger rows).
- **Historical commits are fine** — Mode B walks `merge-base..HEAD`, so anything merged before this rule landed is out of scope.
- **Counter-case from the issue:** PR #16's commit `abc6b58` carries no `Agent:` trailer and would fail CI once this rule is mandatory. Either merge #16 first or re-author its commit through the hook.

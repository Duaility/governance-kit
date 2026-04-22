# Fix `hooks-configured` on worktrees

## Goal

Stop `hooks-configured` from reporting a false positive when `core.hooksPath` is stored as an absolute path — the common case in git worktrees, where config is shared with the main checkout.

## Context

Before: the rule compared `git config core.hooksPath` against the literal string `.githooks`. In worktrees the config resolves to something like `/abs/path/to/main-checkout/.githooks`, which is functionally correct but fails the literal string check. The rule has been failing locally on every run of the suite since the worktree was created, even though hooks actually fire.

## Steps

1. In both the live rule (`tests/governance/rules/hooks-configured.sh`) and the bootstrap asset (`governance-bootstrap/assets/tests-bash/rules/hooks-configured.sh`), replace the literal `.githooks` comparison with a tolerant check:
   - Empty → still a violation (set it).
   - Absolute or relative path → resolve, then require that the basename is `.githooks`, the path points at a directory, and that directory contains an executable `pre-commit`.
2. The separate tracked-and-executable checks for `.githooks/pre-commit` and `.githooks/commit-msg` are unchanged — they already cover the worktree's own hook scripts.
3. Run the suite and confirm all rules pass.

## Why this is a one-liner-ish fix, not a rewrite

The rule's intent was always "hooks are configured and fire." The literal-string comparison was a proxy that was right in the 99% case but spuriously fails in worktrees. The fix swaps the proxy for a check that actually expresses the intent: a real `.githooks` directory with an executable `pre-commit` at the resolved path.

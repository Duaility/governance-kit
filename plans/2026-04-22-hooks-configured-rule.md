<!-- governance: allow-plan-per-issue predates-rule -->

# 2026-04-22 — Add `hooks-configured` rule and move hooks to `.githooks/`

## Goal

Close the gap between what the constitution claims about local enforcement and what a fresh clone actually has. Today the pre-commit and commit-msg scripts live in `.git/hooks/` — untracked, so a `git clone` lands with **zero** local enforcement until someone re-runs `governance-bootstrap`. CI catches violations on PR, but the fast-feedback loop the constitution promises silently disappears.

The fix is to ship hook scripts as tracked files under `.githooks/` and require `git config core.hooksPath .githooks`. A new `hooks-configured` governance rule fails loudly until that config is set, so the very first `git status` after clone tells you what to do.

## Steps

1. Create `.githooks/pre-commit` and `.githooks/commit-msg` in this repo, copied from the current `.git/hooks/` versions (they already honor `SKIP_GOVERNANCE=1` and `--no-verify`). Mark both executable.
2. Run `git config core.hooksPath .githooks` locally and verify both hooks still fire (commit-msg test + pre-commit test, same negative tests as before).
3. Author `tests/governance/rules/hooks-configured.sh`. The rule asserts:
   - `.githooks/pre-commit` is tracked and executable.
   - `.githooks/commit-msg` is tracked and executable **only if** `tests/governance/rules/conventional-commits.sh` is installed (the commit-msg hook is conditional on that rule).
   - `git config --get core.hooksPath` returns `.githooks`. If it doesn't, emit a violation with the exact one-line fix command — this is the rule that turns a silent misconfiguration into a noisy one.
4. Delete `.git/hooks/pre-commit` and `.git/hooks/commit-msg` from local working state so we are actually relying on `.githooks/` from now on (not a belt-and-braces situation that hides bugs).
5. Update `governance-bootstrap`:
   - Add `governance-bootstrap/assets/githooks/pre-commit` and `.../commit-msg` (move from `assets/pre-commit` / `assets/commit-msg`).
   - Add `governance-bootstrap/assets/tests-bash/rules/hooks-configured.sh` (the shippable copy of the rule).
   - Rewrite **Step 6** of `governance-bootstrap/SKILL.md` to: copy hook scripts to `.githooks/` in the target repo (tracked, not `.git/hooks/`), then run `git config core.hooksPath .githooks`, then tell the user this config is per-clone and every contributor must run it (the `hooks-configured` rule will nag them if they forget).
   - Surface the new rule in the **always-installed** list (alongside `no-merge-conflict-markers`) — it's the meta-rule that makes every other local check actually run, so it should not be opt-in.
   - Update `governance-bootstrap/references/RULES_CATALOG.md`: add `hooks-configured` under "Always installed (not in the menu)" with the description.
6. Add `hooks-configured` invariant to `CONSTITUTION.md` and append an Evolution Log entry. Update the **Escape hatches** section's pre-commit reference to point at `.githooks/` instead of `.git/hooks/`. Also update the `conventional-commits` invariant's *Enforced by* line.
7. Mark the `hooks-not-enforced-by-rule` entry in `QUALITY.md` as resolved, linking this PR.
8. Run governance suite. Expect 13/13.
9. Stage rule + hooks + skill changes + constitution + QUALITY + plan, commit, push, open PR.

## Notes

- **Why `.githooks/` and not `.git/hooks/`.** `.git/` is per-clone and untracked by design. There is no Git mechanism to ship hooks via clone other than (a) a separate tracked dir + `core.hooksPath`, (b) a framework like husky / pre-commit.com, or (c) a wrapper script. Option (a) is zero-dep and works for every stack — same reasoning as bash-first elsewhere in this repo.
- **Why a per-clone `git config` step is acceptable.** It's one command, documented in the bootstrap output and re-surfaced by the rule on every commit until set. The alternative (auto-running it from a script every time you `cd` in) is more magic for less benefit.
- **Why `hooks-configured` is always-installed, not opt-in.** Every other local rule depends on the hook actually running. Making this rule opt-in would let users disable the meta-check that catches the silent failure mode — same reasoning as `no-merge-conflict-markers`.
- **Why deleting `.git/hooks/*` matters.** If both `.git/hooks/pre-commit` and `.githooks/pre-commit` exist, `core.hooksPath` wins — but if `core.hooksPath` is unset on someone's clone, `.git/hooks/` quietly takes over and the new rule never fires. Removing the old files locally proves the new path works end-to-end on at least one machine.
- **Out of scope.** The husky / pre-commit.com framework integration path stays as documented in `references/NATIVE_TESTS.md` — projects on those frameworks already have a tracked hook-config mechanism and don't need `.githooks/`. The skill's Step 6 already branches on that detection.

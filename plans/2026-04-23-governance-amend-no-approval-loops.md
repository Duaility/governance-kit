# governance-amend — no inline approval loops

## Goal

Pivot the `governance-amend` skill away from staging-and-waiting-for-approval
toward drafting, smoke-testing, and **committing** the amendment in one pass.
Our workflow gates on PR review, not on inline skill-transcript sign-off; every
extra question the skill asks is friction that duplicates what the PR does
better.

The skill's boundary is one atomic commit: three artifacts land together
(rule script + `CONSTITUTION.md` Invariants subsection + Evolution Log
entry), subject is a conventional-commit, and push stays with the user.

## Steps

1. **Rewrite the behavior contract in `SKILL.md`:**
   - Opening paragraphs now say the skill commits; review happens on the PR.
   - Interaction-policy table rewritten: "Request has enough info → draft,
     smoke-test, commit. No approval loop." Added a row for smoke-test-Exit-1.
   - Dropped the Fast path / Interactive path dual mode — fast path is the
     only mode. Ask a *blocking* clarifying question only when rationale or
     check shape is genuinely missing.
   - Collision handling (existing rule of the same name): proceed with the
     update and note it in the summary, rather than confirm-before-overwrite.

2. **Step 3 (draft the test script):** remove the "show the draft and ask
   whether it's the check they want. Iterate. When the user signs off, write
   it to disk." paragraph. Write once syntax-check passes; don't pause for
   draft approval.

3. **Step 4 (smoke test):** Exit-1 is the one exception to the no-question
   rule. Committing a red-CI amendment and punting the three-way resolution
   (fix / loosen / waive) to the PR reviewer would make the reviewer debug
   the rule's collateral damage instead of reviewing the rule itself. So
   the skill asks exactly one three-choice blocking question on Exit-1:
   - **Loosen** — adjust threshold / pattern / scope before committing.
   - **Grandfather** — add waiver comments to the specific violators so CI
     stays green; the grandfathering is a reviewable diff.
   - **Block** — commit as-is, CI goes red, user fixes tree in a follow-up
     (valid when the user means it, but a choice, not a fallback).

4. **Step 6 (stage + commit):** renamed from "Stage the three artifacts" to
   "Stage and commit the three artifacts". Skill runs `git commit` with a
   conventional-commit subject matching the action (add / update / remove),
   appends the repo's required `(#N)` issue anchor, includes the violator
   list in the commit body when Step 4 was Exit-1+grandfather/block, and
   stops there. Pushing is explicit user action.

5. **Step 7 (report):** summary now shows `Committed: <sha> <subject>` and
   `Next: git push` instead of `Staged:` and `Suggested commit:`. Required
   final-output list updated to match.

6. **Key design rules:** replaced "Don't commit. The skill ends at git add"
   with "Commit, don't push." Added "PR review is the review layer, not the
   skill." Added "Block only on genuinely missing inputs" to make the rubric
   for what counts as blocking explicit: can the bash be deterministic
   without the answer?

7. **Evals alignment:** updated `evals/evals.json` assertions for evals #1,
   #2, #3 to verify "created exactly one new commit with a conventional-commit
   subject" and "did not pause to ask for approval of the draft." Eval #4
   (health-check redirect) and #5 (change-set obligation) unchanged — they
   don't depend on the approval-loop behavior.

## Why this shape

The user's workflow runs PR review on every change. Inline approval during
a skill run duplicates that review imperfectly (no diff view, no context,
no way to leave comments for later) and adds latency without adding
confidence. Staging state is a footgun: worktree destruction, colliding
with other work, easy to forget. A real commit is safe, atomic, and
amendable — `git commit --amend` or a follow-up commit handle anything
the PR surfaces.

The one honest exception is smoke-test Exit-1. That's not draft-approval
theater; it's a genuine branching decision (three operationally distinct
resolutions) that the skill cannot pick mechanically without guessing user
intent. One targeted question there prevents the much worse outcome of a
red-CI PR where the reviewer has to reverse-engineer why the amendment
fired on pre-existing code.

## Non-goals

- **Not automating `git push`.** Pushing is a user decision (wrong branch,
  force-push risk, workflow variations). The skill commits; the user pushes.
- **Not changing the skill's scope.** Still: one amendment, three artifacts,
  one commit. Didn't expand to PR creation, CI setup, or cross-repo
  propagation.
- **Not touching `governance-bootstrap` or `governance-gardener`.** This
  pivot is specific to the amend skill — bootstrap already behaves this
  way, gardener is read-only.

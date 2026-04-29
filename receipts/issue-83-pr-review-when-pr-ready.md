# Receipt: replace pr-review-required-when-checklist-complete with pr-review-required-when-pr-ready

Issue: [#83](https://github.com/Duaility/governance-kit/issues/83)

## Checklist

- [x] Directive folder renamed at both layers
- [x] check.sh trigger axis changed from receipt checklist to PR isDraft
- [x] constitution.md and directive.yaml describe new semantic
- [x] Eval coverage exercises draft / ready / no-PR cases
- [x] pack.yaml standard preset updated
- [x] Reference docs updated
- [x] Evolution-log entry appended
- [x] Smoke test passes

## What changed

The `pr-review-required-when-checklist-complete` directive is replaced with `pr-review-required-when-pr-ready`. The retired directive conflated two different signals: receipt-checklist completion (the work the receipt describes is done) and PR-ready-for-review (the author has signaled "look at this now").

These signals diverge for legitimate reasons. Author wants to push speculative commits to see CI before requesting review. Author ticks boxes red→green during the work and the checklist may complete several commits before the PR is actually ready. Reviewer feedback comes in and the author pushes fixes while the checklist stays green — re-firing a review-mandate on every rework commit would be noisy. Tying the review-mandate to checklist completion fired `codex exec` the moment the last `[ ]` was ticked, even when the author intended more work.

The new directive's trigger axis is GitHub's first-class draft → ready transition (`gh pr ready`):

- **No PR for the branch** → no-op (readiness has no signal to read).
- **PR is draft** → no-op (author hasn't requested review yet).
- **PR is non-draft AND no `<!-- codex-review -->` review** → fire, mandating `codex exec`.

The `<!-- codex-review -->` marker, the local-only stance (skipped under `CI`), the `gh`-missing/auth skip-with-warning, and the fail-loud-on-API-error behavior are preserved verbatim from the retired directive. Composition with `pr-required-when-checklist-complete` is now by separation of axes (the create-gate fires on checklist completion and demands a PR exists; this gate fires on draft → ready and demands a codex review) rather than precondition-skip.

Edits land in lockstep at every layer that names the directive id:

- **Pack source** (`extensions/packs/agent-governance/directives/`): `pr-review-required-when-checklist-complete/` renamed to `pr-review-required-when-pr-ready/` via `git mv`. `check.sh` rewritten — drops the receipt-walking block (~40 lines of awk/grep) and replaces it with `gh pr list --json number,isDraft` + a draft-skip branch. The jq filter is `.[0] // empty | "\(.number)\t\(.isDraft)"` (the `// empty` matters — `.[0]` on an empty array is `null` and naive interpolation emits the literal string `"null\tnull"` which broke the first dogfood run; verified the regression and the fix in the same suite). `directive.yaml` summary rewritten to name the new trigger.
- **Dogfood install** (`.governance/local/directives/`): same folder rename via `git mv` and content synced from the pack source.
- **Eval** (`evals/test.sh`): drops receipt-fixture setup and the now-irrelevant `unchecked-remaining` and `no-receipts` cases. `no-pr-defer` is renamed to `no-pr-noop` to reflect the new semantic (the directive does not apply rather than deferring to another). New cases: `draft-pr-noop` (PR exists but `isDraft=true`), `ready-pr-with-review` (PR is ready and has a codex-marked review), `ready-pr-no-review` (PR is ready and the codex review is missing — the only fail case from the trigger axis itself). Retained: `gh-view-error`, `gh-list-error`, `gh-not-authed`, `ci-env-skip`, `main-branch-noop`, `no-head`. The `gh` shim's pattern updates from `--json number` to `--json number,isDraft` and the payload becomes a tab-separated `<number>\t<isDraft>` that the new check parses with `IFS=$'\t' read`.
- **`agent-governance` pack manifest** (`extensions/packs/agent-governance/pack.yaml`): `standard` preset directive list updated.
- **CONSTITUTION.md**: Evolution Log entry appended (2026-04-28, closes #83). The dogfood install of the retired directive does not have a `### pr-review-required-when-checklist-complete` subsection in CONSTITUTION.md (an oversight from PR #79/#80 — the directive was added to `.governance/local/directives/` and the pack source but never to the dogfood constitution); since there's no subsection to rename, the rename is captured by the evolution-log entry alone.
- **Reference docs**: `README.md` (the agent-governance pack table row), `extensions/packs/agent-governance/README.md` (auxiliary directive description + `standard` preset row), and `governance/references/DIRECTIVES_CATALOG.md` (catalog row + `standard` preset row) all updated to name the new id and describe the new trigger.

Pre-1.0 breaking change with no alias period — V0 stance applies.

## Out of scope

- **Touching `pr-required-when-checklist-complete`** — its semantics (checklist complete → demand a PR exists, draft is fine) remain correct. The user explicitly scoped this work to the review-gate.
- **Backfilling a `### pr-review-required-when-checklist-complete` subsection in CONSTITUTION.md so the rename has a heading-level edit to mirror** — the subsection was never added in the first place; introducing it here just to retire it would be busywork. The Evolution Log captures the rename.
- **Migrating the existing `.governance/installed-packs.yaml` manifest** — the manifest does not list this directive (same oversight as above). No manifest entry to update.
- **An alias period** that accepted both old and new ids during a deprecation window — explicitly skipped per the project's V0 stance.
- **Demonstrating the new draft → ready flow on this very PR** — opening this PR as draft and then marking it ready is a reasonable smoke test, but it's a workflow choice not a directive-scope obligation. Captured under Verification.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Directive folder renamed at both layers.** `extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready/` and `.governance/local/directives/pr-review-required-when-pr-ready/` exist; the old `pr-review-required-when-checklist-complete/` paths do not. `git log --diff-filter=R` shows the rename pair.
2. **Pack source and dogfood twin agree.** `diff -r extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready .governance/local/directives/pr-review-required-when-pr-ready` reports `Only in extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready: evals` (eval fixtures live only in the pack source — same divergence as every other directive).
3. **check.sh trigger axis changed from receipt checklist to PR isDraft.** Read `extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready/check.sh`: there is no `receipts/*.md` walking block; the trigger is `gh pr list --head <branch> --state open --json number,isDraft` followed by an `is_draft == "true"` skip branch. The jq filter is `.[0] // empty | "\(.number)\t\(.isDraft)"` (the `// empty` is load-bearing — without it, `.[0]` on an empty array interpolates to the literal string `"null\tnull"` and the check then calls `gh pr view null` which fails with a confusing error; this was caught and fixed in the dogfood pass).
4. **constitution.md and directive.yaml describe new semantic.** The pack source `constitution.md` opens with the new directive id and the rule paragraph names the GitHub draft → ready transition as the trigger. The `directive.yaml` `summary` mentions `not in draft state` and `decoupled from receipt checklist state`.
5. **Eval coverage exercises draft / ready / no-PR cases.** `bash extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready/evals/test.sh` shows ten checks — `no-head`, `ci-env-skip`, `no-pr-noop`, `draft-pr-noop`, `ready-pr-with-review`, `ready-pr-no-review`, `gh-view-error`, `gh-list-error`, `gh-not-authed`, `main-branch-noop` — and exits 0. The `gh` shim's pr-list pattern is `--json number,isDraft` and emits a tab-separated payload.
6. **pack.yaml standard preset updated.** `extensions/packs/agent-governance/pack.yaml` `standard` preset names `pr-review-required-when-pr-ready`.
7. **Reference docs updated.** `README.md`, `extensions/packs/agent-governance/README.md`, and `governance/references/DIRECTIVES_CATALOG.md` all name the new id; no live references to `pr-review-required-when-checklist-complete` remain outside the historical evolution-log lines and ledger files (`COSTS.md`, `STEERING.md`, `receipts/issue-79-codex-pr-review-directive.md`).
8. **Evolution-log entry appended.** `CONSTITUTION.md` carries a 2026-04-28 entry describing the rename + semantic change and naming closes [#83].
9. **Smoke test passes.** `bash scripts/test-packs.sh` exits 0 across both packs (16 directives, 16 evals). `bash .governance/run.sh` shows the renamed directive under its new id with `⊘ pr-review-required-when-pr-ready (no open PR for branch — directive does not apply)` (correct skip behavior on this branch before the PR is opened); after the PR is opened as a draft, the directive remains a skip; once the PR is marked ready (`gh pr ready`), the directive fires and demands a codex review (verified by inspection of the check.sh control flow against the eval cases).
10. **This commit itself satisfies `commit-issue-receipt-match`.** The commit's `(#83)` anchor matches the `issue-83` token on this very file.

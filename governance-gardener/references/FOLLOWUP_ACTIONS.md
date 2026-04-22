# Follow-up actions

After the health report is written, the user can opt into two side-effecting actions. Both touch git; both end in a PR; neither auto-merges.

Invoke the gardener with an action flag to run just that action against the **most recent** report under `governance-health/`:

- `governance-gardener --bump-stamps` — batched, low risk.
- `governance-gardener --draft-doc-updates` — one draft PR per drifted doc.

Both actions refuse to run if:
- The working tree is dirty.
- No report exists under `governance-health/`.
- The most recent report is older than 7 days (stale — re-run the gardener first).

---

## `--bump-stamps`

Opens **one** PR that advances `<!-- last-verified: ... -->` on all A4 (bump-eligible) docs from the report.

### Flow

1. Confirm clean tree and recent report (above).
2. Re-verify A4 eligibility at the moment of action — watched-path log must still be empty since the stamp. A doc that drifted between the report and now drops out.
3. `git checkout -b gardener/stamp-bumps-<YYYY-MM-DD>`.
4. For each remaining A4 doc: replace `<!-- last-verified: OLD -->` with today's date using `Edit` (not `Write`).
5. Stage only the stamp changes. If the diff touches anything else, abort.
6. Commit: `docs(gardener): bump last-verified stamps — <count> docs, code unchanged`.
7. `git push -u origin <branch>`.
8. `gh pr create` — **ready for review** (not draft). Body from [../assets/stamp-bump-pr.template.md](../assets/stamp-bump-pr.template.md), enumerating each doc with its watched paths and the evidence query.

### Why ready-for-review, not draft

These are low-risk, mechanical changes to a single line per doc. Drafting them invites them to rot in the PR queue, which defeats the point. The risk profile is "did the gardener's watch-set check hit the right paths?" — and the PR body makes that auditable.

### Why re-verify at action time

The report is a snapshot. If someone committed to a watched path between `governance-gardener` and `governance-gardener --bump-stamps`, the doc has drifted and the stamp bump would be wrong. A5 re-check at action time catches that.

---

## `--draft-doc-updates`

Opens **one PR per drifted doc** (A3). Each is a draft. Each carries a proposed content edit the gardener inferred from the commits on the watched paths.

### Flow

For each A3 doc in the report:

1. Re-verify A3 (watched-path log still non-empty since the stamp).
2. `git checkout -b gardener/update-<doc-slug>-<YYYY-MM-DD>`.
3. Read the doc. Read the commit messages + diffs of the changed watch-set files since the stamp. Produce:
   - A **Summary of changes** section for the PR body — one bullet per relevant commit, paraphrased (not a raw log dump).
   - A **proposed diff** against the doc. Be conservative: change what the drift actually implies, not everything that *could* be cleaner.
4. Apply the diff via `Edit`. Update the stamp to today.
5. Commit: `docs(gardener): draft update for <doc path> — code drift since <stamp_date>`.
6. `git push -u origin <branch>`.
7. `gh pr create --draft`. Body from [../assets/doc-update-pr.template.md](../assets/doc-update-pr.template.md), including:
   - **Summary of changes** (the paraphrased commit list).
   - **What I inferred** (the specific diffs from the commit log that drove each doc edit).
   - **Confidence** (high if explicit annotation; medium if inferred watch set).

### Why draft, not ready-for-review

The content edit is a *guess* from commit diffs. A human has to confirm the guess is right and the tone fits the doc. Opening ready-for-review invites rubber-stamping; drafting forces a real read.

### Never force-push

If a `gardener/update-<slug>-<YYYY-MM-DD>` branch already exists (prior run, same day), use a `-v2`, `-v3` suffix. Earlier branches may be mid-review.

---

## What the gardener never does

- **Never auto-merges.** Even low-risk bumps require a human click.
- **Never edits `CONSTITUTION.md` or `tests/governance/rules/`.** Rule-shaped candidates in the report hand off to `governance-amend`.
- **Never writes outside of `governance-health/` or the PR branches it creates.**
- **Never runs follow-up actions on its own initiative** — always gated by user opt-in (via `AskUserQuestion` in the interactive flow, or explicit `--bump-stamps` / `--draft-doc-updates` invocation).

## Draft doc update — code drift since last verified

**Status:** draft. Opened by the `governance-gardener` skill after a Governance Health Report flagged `{{DOC_PATH}}` as **A3 · Doc drift** — the `<!-- last-verified: ... -->` stamp has expired AND commits have landed on the doc's watched paths since.

Source report: `governance-health/{{REPORT_DATE}}.md`.

The gardener has proposed a content edit based on those commits. **This is a guess.** The human reviewer decides whether the guess is right.

### Summary of changes on watched paths

{{WATCH_SET_LIST}} _(from the `<!-- gardener-watches: ... -->` annotation{{INFERENCE_NOTE}})_

Commits on those paths since `{{OLD_STAMP}}`:

{{PER_COMMIT_BULLET}}

Each `PER_COMMIT_BULLET` entry:

> - **`{{SHA}}`** · _{{SUBJECT}}_ — {{ONE_LINE_PARAPHRASE}}

### What I inferred

For each doc section I edited, here's which commit drove the change:

{{PER_EDIT_MAPPING}}

Each `PER_EDIT_MAPPING` entry:

> - Section **"{{HEADING}}"** — updated to reflect `{{SHA}}` ({{SHORT_REASON}}).

### Confidence

**{{CONFIDENCE}}** — {{CONFIDENCE_REASON}}

- `high`: doc has an explicit `<!-- gardener-watches: ... -->` annotation, watch set is narrow, commits have focused subjects.
- `medium`: watch set was inferred, or the commits span multiple concerns, or the paraphrase required judgment.
- `low`: watch set is broad, commit subjects are vague — the draft is a starting point, not a proposal.

### Stamp

The `<!-- last-verified: ... -->` stamp has been advanced to **{{TODAY}}**.

**Only merge this PR if the content changes above are correct.** A merged PR with wrong content under a fresh stamp is strictly worse than a missing stamp — it lies to every future reader.

### Reviewer options

- **Merge as-is** — the content edit is right, the stamp is now current.
- **Edit and merge** — the gardener's edit is close but not right. Fix it on the branch, then merge.
- **Close without merging** — the gardener got it wrong. Close the PR; the next gardener run will flag it again. Consider tightening the `<!-- gardener-watches: ... -->` annotation so the next draft is narrower.

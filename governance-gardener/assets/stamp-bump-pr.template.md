## Stamp bumps — code unchanged since last verified

Opened by the `governance-gardener` skill after a Governance Health Report flagged these docs as **A4 · Bump-eligible** — the `<!-- last-verified: ... -->` stamp has expired, but `git log` on each doc's watched paths returned empty since the stamp. The content is still accurate; only the date is advanced.

Source report: `governance-health/{{REPORT_DATE}}.md`.

### What's in this PR

{{PER_DOC_BLOCK}}

Each `PER_DOC_BLOCK` entry (repeated per doc):

> #### `{{DOC_PATH}}`
>
> - **Previous stamp:** {{OLD_STAMP}} ({{DAYS_OLD}} days old)
> - **New stamp:** {{TODAY}}
> - **Watched paths:** {{WATCH_LIST}}
> - **Evidence the content is still accurate:**
>   ```
>   git log --since="{{OLD_STAMP}}" -- {{WATCH_LIST}}
>   ```
>   returned no commits.

### What's NOT in this PR

- Any change outside the `<!-- last-verified: ... -->` line of each listed doc.
- Any new documentation.
- Any change to `CONSTITUTION.md` or `tests/governance/`.

The gardener refuses to open this PR if the staged diff touches anything else.

### Reviewer checklist

- [ ] The watched-path list for each doc looks right. If a doc watches too narrowly, a real content change could have been missed.
- [ ] The `git log` evidence above is plausible (spot-check one or two).
- [ ] The new stamp is today.

### How to reject

If any doc in this PR actually *has* drifted (the watch set was too narrow):

1. Close this PR (don't merge partially — the batch re-runs cleanly next time).
2. Add a more specific `<!-- gardener-watches: ... -->` annotation to the affected doc.
3. Re-run `governance-gardener` — the doc will now show up as **A3 · Doc drift**, and `--draft-doc-updates` will open a content-update draft.

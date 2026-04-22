## Stamp bumps — <count> docs, no code drift

Automated by the `doc-gardener` skill. Every doc listed below was re-verified: the code its `<!-- gardener-watches: ... -->` annotation points at has **not** changed since the previous `<!-- last-verified: ... -->` stamp. The docs are still accurate; the stamps have been advanced to today.

### Docs updated

<!-- One bullet per doc. Format:
- `<path>` — previous stamp: `YYYY-MM-DD` → `YYYY-MM-DD` (no drift across N files: <list>)
-->

### Review checklist

- [ ] Spot-check one or two of the listed docs against their watch set — does "no drift" look right?
- [ ] If any bump is wrong, remove that file from this PR and open the doc for real editing.

### What this PR does NOT contain

- Any prose changes.
- Any new annotations.
- Any changes outside the `<!-- last-verified: ... -->` stamps.

If you see anything else in the diff, something went wrong — do not merge. Open an issue.

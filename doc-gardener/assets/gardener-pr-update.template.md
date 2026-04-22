## Draft update — `<doc path>`

**Status:** draft. The code this doc watches has drifted since the last `<!-- last-verified: ... -->` stamp; the gardener has proposed an update. This PR needs a human review before merging.

### Watched set

<!-- List the paths from the doc's <!-- gardener-watches: ... --> annotation, or the inferred watch set. -->

- `<path>`
- `<path>`

### Summary of changes in the watched code since `<stamp_date>`

<!-- Paraphrased bullets — one per relevant commit. Not a raw git log dump.
Example:
- `<short-sha>` — refactored `TokenSigner` to use HS512; doc still references HS256.
- `<short-sha>` — removed the `legacy_refresh()` entrypoint the doc walks through.
-->

### What I changed in the doc

<!-- One bullet per substantive edit in this PR's diff.
Example:
- Updated the signing-algorithm reference from HS256 to HS512 (section "Session lifecycle").
- Removed the paragraph describing `legacy_refresh()` — the function no longer exists.
-->

### What I inferred (and where I might be wrong)

<!-- Be specific about confidence. Reviewers need to know which edits are mechanical (high confidence) and which are interpretive (low confidence). Flag any place the gardener guessed.
Example:
- High confidence: the HS256 → HS512 swap — the commit message and diff are unambiguous.
- Lower confidence: the replacement paragraph for `legacy_refresh()` — the commit that removed it didn't leave a replacement, so the new wording is a best guess from surrounding context.
-->

### Stamp

Updated `<!-- last-verified: YYYY-MM-DD -->` to today's date. **Only merge this PR if the content changes above are correct** — a merged PR with wrong content under a fresh stamp is strictly worse than a missing stamp.

### Review checklist

- [ ] Do the "Summary of changes" bullets accurately reflect what happened in the watched code?
- [ ] Do the "What I changed" edits accurately translate those changes into doc updates?
- [ ] Is any low-confidence inference wrong? (Edit or revert before merging.)
- [ ] Are there drifts in the watched code that the gardener missed? (Add them in a follow-up commit.)

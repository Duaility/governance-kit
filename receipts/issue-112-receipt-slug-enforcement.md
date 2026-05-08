# issue-112 — receipt-per-issue must require kebab-case slug

Closes [#112](https://github.com/Duaility/governance-kit/issues/112).

## Checklist

- [x] Tighten `check.sh` regex to require `issue-<N>-<slug>.md` with kebab-case slug in both pack source and dogfood install
- [x] Update each `constitution.md` (pack source + dogfood) to spell out the slug rule
- [x] Extend `evals/test.sh` with new fail fixtures: `issue-N.md` (no slug), `issue-N-.md` (empty slug), uppercase / underscore slugs
- [x] Update root `CONSTITUTION.md` directive subsection and append Evolution Log entry
- [x] Smoke-test current `receipts/*.md` — all 24 existing receipts already follow the format and must still pass

## What changed

- Tighten `check.sh` regex to require `issue-<N>-<slug>.md` with kebab-case slug in both pack source and dogfood install. Both `governance/assets/packs/core/directives/receipt-per-issue/check.sh` (pack source) and `.governance/packs/governance-kit/core/directives/receipt-per-issue/check.sh` (dogfood) had their basename match changed from the substring form `[[ "$base" =~ issue-([0-9]+) ]]` to the anchored form `[[ "$base" =~ ^issue-([0-9]+)-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]`. The slug regex `[a-z0-9]+(-[a-z0-9]+)*` accepts one or more kebab-case tokens (lowercase letters, digits, hyphens), required after `issue-<N>-`. The fallback violation message replaces the old "filename must include an 'issue-<N>' token" wording with "filename must match 'issue-<N>-<slug>.md' with a kebab-case slug (lowercase letters, digits, hyphens) — e.g. receipts/issue-63-replace-plans.md". The leading directive comment block (rule 1) is rewritten to match.
- Update each `constitution.md` (pack source + dogfood) to spell out the slug rule. Rule 1 in both `governance/assets/packs/core/directives/receipt-per-issue/constitution.md` and `.governance/packs/governance-kit/core/directives/receipt-per-issue/constitution.md` is rewritten from "filename includes an `issue-<N>` token" to "filename matches `issue-<N>-<slug>.md` where `<N>` is the GitHub issue number and `<slug>` is one or more kebab-case tokens (lowercase letters, digits, hyphens)".
- Extend `evals/test.sh` with new fail fixtures: `issue-N.md` (no slug), `issue-N-.md` (empty slug), uppercase / underscore slugs. Three new failure cases were inserted between the existing "no-token" rogue case and the duplicate-issue case in `governance/assets/packs/core/directives/receipt-per-issue/evals/test.sh`: `issue-9.md` (no slug at all), `issue-10-Foo.md` (uppercase in slug), `issue-11-foo_bar.md` (underscore separator instead of hyphen). Each is staged + committed against the eval fixture repo and `expect_fail "$CHECK"` asserts the directive flags it. The empty-slug case (`issue-12-.md`) is implicitly covered by the same regex — a trailing hyphen with no kebab token cannot match `[a-z0-9]+(-[a-z0-9]+)*\.md$` — so a dedicated fixture would be redundant with the no-slug case.
- Update root `CONSTITUTION.md` directive subsection and append Evolution Log entry. The `### receipt-per-issue` subsection's rule 1 is rewritten to match the new wording in the pack constitution snippets. A new Evolution Log entry dated 2026-05-08 is appended naming the bad merges the directive previously allowed (`receipts/issue-63.md` no slug, `receipts/Issue-63-Foo.md` wrong case), the new anchored regex, and the dual-edit surface across pack source and dogfood.

## Out of scope

- Renaming any existing receipt. All 24 receipts under `receipts/` already follow `issue-<N>-<slug>.md` with kebab-case slugs — no renames are needed and the smoke test confirms this.
- Backfilling a check that the slug **describes the issue**. The slug is mechanical formatting only; whether `issue-63-receipts-replace-plans.md` actually summarizes #63 is a judgment call and out of scope for the directive.
- Tightening the issue-number portion (e.g. forbidding leading zeros, `issue-007-foo.md`). Not a real-world risk — GitHub issues use plain integers — and would just add regex complexity for no observed bad merge.
- Strengthening sibling directives (`commit-issue-receipt-match`, `agent-token-accounting`) to also assert the slug shape. They reference the receipt by issue number; the receipt's own filename rule is the right enforcement point.

## Verification

- `bash -n` syntax-check passes on both updated `check.sh` files (pack source + dogfood).
- Smoke-test current `receipts/*.md` — all 24 existing receipts already follow the format and must still pass: `bash .governance/run.sh receipt-per-issue` exits 0 against the current tree, every existing `receipts/*.md` file satisfying the tightened regex.
- `bash governance/assets/packs/core/directives/receipt-per-issue/evals/test.sh` exits 0 — every existing pass case still passes (file shape, crosswalk, case-insensitivity), every existing fail case still fails (no-token rogue, dup, missing sections, bad crosswalk, star-bullet), and the three new fail cases (no-slug, uppercase-slug, underscore-slug) all fail as expected.
- `bash .governance/run.sh` (full suite) exits 0 — no other directive regresses.
- A reviewer can confirm by running `git ls-files receipts/*.md | xargs -n1 basename` and verifying every entry matches `^issue-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*\.md$` — i.e. all 24 existing receipts already follow the format and must still pass.

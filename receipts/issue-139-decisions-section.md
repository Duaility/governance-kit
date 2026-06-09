# Receipt: add a `## Decisions` section to receipt-per-issue

Closes [#139](https://github.com/Duaility/governance-kit/issues/139).

The issue links the running-implementation-notes prompt pattern (@trq212): while
implementing a spec, keep a running note of the decisions you had to make that
weren't in the spec, the things you had to change, and the tradeoffs. The four
existing receipt sections capture the *what* (surface area, deferred work,
verification) but nothing captures the *why-it-diverged*. This change adds that
fifth dimension as a `## Decisions` section, scoped to newly added receipts so
the historical corpus is never retroactively swept.

## Checklist

- [x] Add a Decisions section to the receipt-per-issue directive
- [x] Scope the Decisions requirement to receipts added in the change set
- [x] Keep the four original sections and the checklist crosswalk on every tracked receipt
- [x] Mirror the directive text into CONSTITUTION.md and add an Evolution Log entry
- [x] Update the DIRECTIVES_CATALOG.md row
- [x] Extend the pack eval with change-set Decisions cases

## What changed

- **Add a Decisions section to the receipt-per-issue directive**: `check.sh`,
  `directive.yaml`, and `constitution.md` under
  `packs/core/directives/receipt-per-issue/` now describe and enforce a fifth
  `## Decisions` section recording off-spec decisions, forced changes, and
  tradeoffs.
- **Scope the Decisions requirement to receipts added in the change set**:
  `check.sh` computes `ADDED_RECEIPTS` (the union of staged additions via
  `git diff --cached --diff-filter=A` and `base..HEAD` additions via a
  default-branch merge-base walk) and gates the section check behind a
  `receipt_in_scope` test, so pre-existing receipts are grandfathered.
- **Keep the four original sections and the checklist crosswalk on every
  tracked receipt**: the filename, `## Checklist` / `## What changed` /
  `## Out of scope` / `## Verification` presence, and the `- [x]` crosswalk
  logic are unchanged and still run over the whole tracked corpus.
- **Mirror the directive text into CONSTITUTION.md and add an Evolution Log
  entry**: the root `CONSTITUTION.md` `receipt-per-issue` block matches the pack
  `constitution.md`, and a dated entry records the change.
- **Update the DIRECTIVES_CATALOG.md row**:
  `governance/references/DIRECTIVES_CATALOG.md` now reflects the change-set
  scope.
- **Extend the pack eval with change-set Decisions cases**:
  `packs/core/directives/receipt-per-issue/evals/test.sh` gained four cases.

## Out of scope

- The legacy `receipts/*.md` corpus is left untouched — grandfathered by the
  change-set scope rather than backfilled or waived.
- A pre-existing checklist-crosswalk defect in
  `receipts/issue-140-mac-argv-utf8-mangling.md` is unrelated to this change and
  tracked separately.
- Bumping `packs.lock` / the core pack version to roll this rule into this
  repo's own enforcement is a separate release step.

## Verification

- `bash packs/core/directives/receipt-per-issue/evals/test.sh` is green,
  including the four change-set cases: a newly added receipt missing
  `## Decisions` fails; a newly added receipt with `## Decisions` (and with
  `## Decisions` = "None") passes; a committed pre-existing receipt without
  `## Decisions` is grandfathered and passes.
- Running the new `check.sh` against this repo's real `receipts/` tree confirms
  the historical corpus is unaffected by the new section.

## Decisions

- **Scoped the requirement to the change set instead of the whole repo.** The
  first cut made `## Decisions` a fifth always-checked section, which would have
  retroactively failed all ~39 existing receipts at once. The fix was to require
  the section only on receipts *added* in the change set, which grandfathers the
  historical corpus for free.
- **Discarded a section-scoped waiver token.** An intermediate design added a
  `governance: allow-receipt-per-issue decisions <reason>` waiver plus 39 waiver
  lines across the existing receipts to grandfather them. Both were dropped once
  the rule became change-set-scoped — the scope already grandfathers honestly,
  and reconstructing past off-spec decisions after the fact would have been
  fiction. Only the existing full-receipt waiver remains.
- **Required on *added* receipts, not *modified* ones.** Touching an old receipt
  (e.g. a typo fix) does not newly owe a `## Decisions` section; only genuinely
  new receipts do. This keeps the line clean and the rule unintrusive.
- **Reused `commit-issue-receipt-match`'s Mode B base-resolution pattern** for
  the CI side rather than inventing a new change-set mechanism, so the two
  directives agree on what "the change set" means.

# Issue 316: Restructure README into a themed section hierarchy

Closes [#316](https://github.com/Duaility/governance-kit/issues/316).

## Checklist

- [x] README sections are grouped under themed `##` headers with question-form `###` subsections.
- [x] Quickstart leads with install then the command surface.
- [x] "What are packs?" precedes "What ships with it?".
- [x] Adopt/compare/agents/proof sections are clustered together.
- [x] The redundant "What do you get?" section is folded in, not duplicated.
- [x] Top navigation anchors resolve to the new themed sections.
- [x] Governance checks pass.

## What changed

- `README.md` now groups the previously flat list of question-form sections under five themed `##` headers — `Why Governance Kit`, `Quickstart`, `Concepts`, `Should you adopt it?`, and `Reference and community` — with each prior question section demoted to a `###` subsection.
- `README.md` Quickstart now leads with `How do you install it in 60 seconds?` followed immediately by `Which commands will you use?` (the command surface and the manual-install/lifecycle material moved up from the former standalone late-document section).
- `README.md` Concepts orders `How strict can a rule be?`, then `What are packs?`, then `What ships with it?`, so the pack concept is introduced before the bundled packs are listed.
- `README.md` clusters the decision-oriented sections — `Does this repo use it?`, `When does it fit?`, `How does it compare?`, and `Can you use it from any agent?` — under the `Should you adopt it?` theme.
- `README.md` folds the former `What do you get?` bullet list into a `Concepts` lead-in instead of repeating it as a separate section, removing the duplicate benefits list that bookended the document.
- `README.md` repoints the top navigation strip to the five themed anchors (`#why-governance-kit`, `#quickstart`, `#concepts`, `#should-you-adopt-it`, `#reference-and-community`) and renames the final theme to "Reference and community" to keep a clean slug.
- `receipts/issue-316-readme-section-hierarchy.md` records the README information-hierarchy restructure for this issue.

README sections are grouped under themed `##` headers with question-form `###` subsections.
Quickstart leads with install then the command surface.
"What are packs?" precedes "What ships with it?".
Adopt/compare/agents/proof sections are clustered together.
The redundant "What do you get?" section is folded in, not duplicated.
Top navigation anchors resolve to the new themed sections.

## Out of scope

- No kit runtime, skill shim, bundled pack source, consumed `.governance/` tree, or generated docs site pages changed.
- No product behavior or directive behavior changed.
- The section prose itself was not rewritten beyond folding the one duplicate benefits list; this is a structural reorganization.

## Decisions

- Kept terse non-reader-flow labels where the README convention is clearer than a question, such as table column labels and `<details>` summaries.
- Preserved the existing question-form heading text (and therefore anchors) for every moved section except the install heading, so inbound links to those sections survive the demotion to `###`.
- Named the final theme "Reference and community" rather than "Reference & community" to avoid an ampersand-mangled GitHub slug.

## Verification

```sh
bash .governance/run.sh
```

Result: all governance directives passed locally after adding this receipt, including `internal-doc-links` (so every new nav anchor and cross-reference resolves).

Governance checks pass.

## Audit

PASS - Checked against the working-tree diff for issue #316. The product-facing change is limited to `README.md`, and this receipt names the actual edits: five themed `##` sections with the prior questions as `###`, install-then-commands Quickstart ordering, packs-before-ships in Concepts, a clustered adopt section, the folded `What do you get?` benefits list, and the repointed five-anchor navigation. A fresh-context reviewer independently confirmed every new nav anchor and the `#which-commands-will-you-use` cross-link map to real headings and that all relative links resolve on disk. The checklist items crosswalk into `## What changed` and `## Verification`.

## Layer boundaries

PASS - The diff stays in the documentation and audit layers: `README.md` is public repo documentation and this receipt lives under `receipts/`. No `skill/`, `kit/`, `packs/`, or consumed `.governance/` runtime/source files are modified, and the moved prose (the Quickstart kit-vs-packs paragraph and the loop diagram) restates the declared skill -> kit -> packs -> consumed repo model verbatim without rewording any dependency edge.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-4fcdf619-5b7-1781695684-1 | claude-code | 4fcdf619-5b70-46fb-b397-0e104ad715ee | #316 | claude-opus-4-8 | 7006 | 33576 | 30540 | 672 | 41254 | 0.2769 | 7006 | 33576 | 30540 | 672 | docs(readme): restructure into themed section hierarchy (#316) |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-494f28e3446-1781695684-1 | 494f28e3-446a-4a46-9806-e83fc29839fc | #316 | correction | classifier | Wanted a structured section/subsection hierarchy, not the flat reorder proposed | docs(readme): restructure into themed section hierarchy (#316) | 1 | 2026-06-17T11:15:47.211Z |

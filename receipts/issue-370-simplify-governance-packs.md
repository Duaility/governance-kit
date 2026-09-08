# Receipt: simplify governance packs (#370)

## Checklist

- [x] Source retirement of all five directives and their preset/catalog/runtime references
- [x] Also retire `issues-tracked` (explicit follow-up to the issue's original out-of-scope list)
- [x] A smaller receipt contract, corresponding checks and review rubric
- [x] The necessary adjustment to `commit-issue-receipt-match` so completed-change traceability replaces per-commit receipt-touch bookkeeping
- [x] Compatibility of the simplified receipt with immutable historical receipts (including leftover `## Session` / `## Accounting` stubs)
- [x] Fresh-install and existing-install lifecycle behavior, documentation, regression coverage
- [x] Retire `agent-session-identity`; session identifiers are a harness concern
- [x] Fold `commit-message-format` into `governance-kit/audit` and delete the one-directive `governance-kit/commits` pack
- [ ] Post-release dogfood update — separate PR after `scripts/release.sh` publishes pack tags (`governance pack remove governance-kit/commits` once audit carries the moved directive)

## What changed

Retired bundled directives from pack source (not the consumed `.governance/` tree): `internal-doc-links`, `repo-hygiene`, `required-docs` (`packs/foundation`), `no-orphan-todos`, `no-unjustified-suppressions` (`packs/commits`), `issues-tracked` and `agent-session-identity` (`packs/audit`). Moved `commit-message-format` from `packs/commits` into `packs/audit` and deleted the `governance-kit/commits` pack. Updated `packs/*/pack.yaml` presets so foundation minimal is `managed-tree-integrity` only and audit standard is the remaining audit-chain set (including `commit-message-format`). Session identifiers are a harness trailer (Claude Code's `Claude-Session:`, and equivalents); the kit no longer stamps or requires a receipt `## Session` table.

Simplified `receipt-per-issue` (`packs/audit/directives/receipt-per-issue/check.sh`, `directive.yaml`, `constitution.md`, `evals/test.sh`) to unique issue association, optional slug, completed-change `## What changed` + `## Verification` evidence (fence plus outcome, or an `http(s)` URL; a fence alone is not evidence), optional `## Decisions`, required `## Audit`. Session stubs cannot satisfy a completed change. Dropped checklist, crosswalk, file inventory, mandatory empty sections, and mandatory slugs.

Changed `commit-issue-receipt-match` so Mode A gates only direct-to-default pending commits and Mode B requires a receipt in the aggregate `base..HEAD` diff, not each intermediate commit.

Taught `packplan.py` / `packapply.py` to classify and apply upstream directive removals: delete folders, strip constitution subsections, leave user overlays listed as `conf_orphaned`, rewrite lock `directives:`/`digest:`, regen hooks, and recompile an already-enrolled schedule workflow. Covered by `scripts/test-packverb-apply.py`.

Updated catalog and flows: `kit/references/DIRECTIVES_CATALOG.md`, `INIT_FLOW.md`, `PACK_VERBS.md`, `LOCK_SCHEMA.md`, `UNINSTALL_MATRIX.md`, `kit/assets/receipt.bootstrap.template.md`, `kit/assets/dot-governance/run.sh` comments, `README.md`, `ARCHITECTURE.md`, `docs/concepts/audit-chain.mdx`, `docs/guide/introduction.mdx`, `docs/guide/configuration.mdx`, `docs/guide/quickstart.mdx`, generated `docs/reference/directive-catalog.mdx` and `docs/reference/schemas.mdx`, plus `kit/evals/init/evals.json`, `kit/evals/init/files/README.md`, `kit/evals/pack/evals.json`, `scripts/test-packs.sh`.

Did not hand-edit `.governance/` or live `CONSTITUTION.md`. Version stamps are unchanged (release process only).

## Out of scope

- Post-release `governance pack update` / `governance update` dogfood of this repo
- Removing `managed-tree-integrity`, `commit-message-format`, `issue-templates`, `doc-integrity`, or `toolchain-config-protection`
- Installing linters as replacements
- Retroactive rewrite of historical receipts

## Verification

```sh
bash scripts/test.sh
npm run docs:gen:check
bash packs/audit/directives/receipt-per-issue/evals/test.sh
bash packs/audit/directives/commit-issue-receipt-match/evals/test.sh
bash packs/audit/directives/commit-message-format/evals/test.sh
python3 scripts/test-packverb-apply.py
```

All of the above exited 0. `bash scripts/test.sh` reported every kit-internal layer passed, including 2 packs / 7 remaining bundled directives / 7 evals. `npm run docs:gen` regenerated `docs/reference/*.mdx` from `kit/references`.

## Decisions

- Also retired `issues-tracked` because the operator asked to delete it after the issue text had listed it as out of scope.
- Retired `agent-session-identity` rather than folding it into the receipt or a kit-owned trailer: Claude Code already stamps `Claude-Session:` / `Co-Authored-By:` on the commit, and other harnesses will follow. The kit does not police those trailers.
- Folded `commit-message-format` into `governance-kit/audit` (the `(#N)` suffix is the audit-chain issue anchor) instead of keeping a one-directive commits pack. Existing installs drop the leftover pack with `governance pack remove governance-kit/commits` after the audit pack update that adds the moved directive.
- Kept `commit-issue-receipt-match` as a separate directive with documented change-set semantics rather than folding it into `receipt-per-issue`.
- Direct-to-default completion is "HEAD is `main`/`master`" for Mode A; PR completion is a clean index plus a merge-base (CI / `run.sh` on a feature branch).
- Verification evidence stays Markdown: fence plus an outcome token, or a durable URL. Overlays for retired ids are left in place and listed, not silently deleted.
- `QUALITY.md` remains in this repo as a historical file; `doc-integrity` still freezes its `Resolved` section when the file exists.

## Audit

Independent review against `git diff HEAD`, this receipt, and issue #370 (operator later required retiring `issues-tracked` and `agent-session-identity`, and folding `commit-message-format` into audit). A recorded verdict is not proof of execution.

- PASS — `## What changed` matches the diff: seven directive trees deleted under `packs/` (the original six plus `agent-session-identity`), `commit-message-format` moved into `packs/audit`, `packs/commits` removed, receipt and match checks rewritten, `packplan.py`/`packapply.py` classify and apply removals, catalog/flow/site docs updated. It does not claim a consumed-tree or version-stamp change; none is in the diff.
- PASS — each `- [x]` item is in the diff. Retirement is the `git rm` of the directive folders plus preset/catalog edits. The smaller receipt contract and completed-change match live in `packs/audit/directives/{receipt-per-issue,commit-issue-receipt-match}/`. Pack-update retirement is `kit/assets/packs/lib/pack{plan,apply}.py` plus `scripts/test-packverb-apply.py`. Historical stub grandfathering remains in `receipt-per-issue/check.sh`. The commits-pack fold is the `git mv` of `commit-message-format` plus deletion of `packs/commits`. Docs and evals are the `kit/references`, `docs/`, and test edits. The unchecked dogfood item has no corresponding consumed-tree change.
- PASS — the checklist is issue #370's in-scope plan (source retirement, smaller receipt, match adjustment, historical-receipt compatibility, lifecycle/docs/evals) plus the operator's follow-ups (`issues-tracked`, `agent-session-identity`, fold `commit-message-format` into audit), with post-release dogfood left open as the issue requires.

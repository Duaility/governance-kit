# issue-208 — canonicalize conf-knob default docs and fix the doc-integrity frozen-section OOM

Closes [#208](https://github.com/Duaility/governance-kit/issues/208).

## Checklist

- [x] Canonicalized all seven conf-knob defaults to a commented KEY=default line
- [x] Tightened conf-knob-doc-sync to canonical-only
- [x] Fixed the doc-integrity frozen-section OOM
- [x] Pack evals and full suite pass

## What changed

- **Canonicalized all seven conf-knob defaults to a commented KEY=default line.** The `conf_get` scalar knobs were documented in two textual forms across the bundled packs — a commented `KEY=<default>` line in `doc-freshness`, and `Default <n>.` prose in `repo-hygiene` and `required-docs`. All seven (`repo-hygiene`'s `MAX_FILE_SIZE_MB`/`FILE_SIZE_LIMIT`, `required-docs`'s `AGENTS_MD_MIN`/`AGENTS_MD_MAX`/`AGENTS_MD_MIN_LINKS`/`ARCHITECTURE_MIN`, `doc-freshness`'s `FRESHNESS_DAYS`) now state their default once, as a commented `# KEY=<default>` line carrying the real default (postgres-style, uncomment-and-edit to override). The `Default <n>.` prose and the made-up example values are gone; `doc-freshness`'s redundant "default of 90" prose was dropped since the canonical line already states it.
- **Tightened conf-knob-doc-sync to canonical-only.** The repo-local dogfood lint accepted either the canonical line or `Default <n>` prose; the prose branch is now dead code, so it is removed. The value match drops the `[Dd]efault( of)?` alternation and gains a left word-boundary anchor, so the default is matched exactly on the `KEY=value` token rather than heuristically — closing the cross-knob false-pass where two knobs sharing a default value could satisfy each other's prose. The directive's `constitution.md` and the live `CONSTITUTION.md` subsection were updated to state canonical-only, with an Evolution Log entry.
- **Fixed the doc-integrity frozen-section OOM.** `check_frozen_section` tested each baseline line for presence in the current section with a per-line `grep -Fxq`. On the multi-KB single-line `Evolution Log` entries, `ugrep` on macOS exits `out of memory` (rc=2), and `if ! grep` misread that non-zero exit as "line missing", raising a false frozen-section violation that blocked the local commit-msg hook (Mode A only; Linux CI grep was unaffected). The per-line grep is replaced with a single `awk` whole-line set-membership pass — one process, no pathological allocation, identical blank-line skipping and verbatim matching.

## Out of scope

- Releasing the `audit` pack and repinning the dogfood lock so this repo's own vendored commit-msg hook picks up the OOM fix. The committed `.governance/` consumed tree lags `packs/` by one release by design (Lane 1), so the fix reaches the live hook only via a post-release `governance pack update`. Until then, Evolution-Log appends — including this one — still carry an `allow-doc-integrity CONSTITUTION.md` waiver.
- A kit-bundled (shipped-to-consumers) version of `conf-knob-doc-sync` — it is meaningful only in the kit source repo and stays a repo-local dogfood directive.

## Verification

```sh
# conf-knob-doc-sync green on the unified tree; prose defaults now rejected
bash .governance/run.sh conf-knob-doc-sync
#   negative test (reverted): regressing a knob to prose-only ->
#   "does not document the code default for FILE_SIZE_LIMIT as a commented FILE_SIZE_LIMIT=500 line"

# doc-integrity OOM fix: old grep vs new awk on the real 5218-byte Evolution Log entry
#   old: ( ulimit -v 2000000; grep -Fxq -- "$longest" section.txt )  -> grep: out of memory, rc=2
#   new: awk whole-line set-membership pass under the same 2GB cap    -> correct, no OOM;
#        edit of the longest entry still reported as 1 missing line

# pack evals (19 directives) and doc-integrity evals (20 cases)
bash scripts/test-packs.sh

# full suite
bash .governance/run.sh
```

Pack evals and full suite pass: 19 pack directives plus 20 doc-integrity eval cases, and the full 21-directive `.governance/run.sh` suite green.

## Decisions

- **One issue, one PR for two changes.** The conf-knob canonicalization (a `conf-knob-doc-sync` amendment) and the `doc-integrity` OOM fix (a bundled-pack code fix) ship together per the user's instruction. Only the former is a constitutional amendment, so only it carries an Evolution Log entry; the OOM fix is a behavior-preserving implementation change validated by the existing `doc-integrity` evals.
- **Left-boundary anchor added, not just prose removed.** Removing the prose branch alone would still allow a key-substring false match (e.g. `SIZE_MB` inside `FILE_SIZE_MB=5`); the added `(^|[^A-Za-z0-9_])` boundary makes the canonical match fully exact, which the directive's rationale now claims.
- **Source-only edits to bundled packs.** The `config.conf` templates and `doc-integrity/check.sh` are edited in `packs/` only; the vendored `.governance/` twins are left untouched (Lane 1 — `consumed-tree-integrity` would reject a hand-edit, and they catch up at release).

# Receipt: harness-engineering directives + doc-link consolidation (issue-184)

Borrowed ideas from OpenAI's *Harness engineering* post and turned the
enforceable ones into core directives.

## Checklist

- [x] toolchain-config-protection directive
- [x] no-unjustified-suppressions directive
- [x] internal-doc-links directive
- [x] receipt-per-issue fenced Verification rule
- [x] catalog and preset reconciliation

## What changed

- Added the **toolchain-config-protection directive** (`packs/core/directives/toolchain-config-protection/`): a commit touching lint/format/type-check/CI/git-hook config must carry a `governance: allow-toolchain-config <reason>` body line. commit-msg Mode A + CI Mode B, mirroring `commit-issue-receipt-match`. Protected paths come from `.governance/protected-config.conf` or a built-in multi-ecosystem default. Added to the `standard` preset.
- Added the **no-unjustified-suppressions directive** (`packs/core/directives/no-unjustified-suppressions/`): every lint/type-checker suppression (`@ts-ignore`, `# noqa`, `#[allow(...)]`, …) must reference an issue on the same line, the checker-silencing sibling of `no-orphan-todos`. Added to the `strict` preset.
- Added the **internal-doc-links directive** by merging the new `doc-reachability` check into the existing `no-broken-internal-doc-links` as one rolled-up directive with a `resolve` sub-check (always on) and an opt-in `reachable` sub-check (no-op without `.governance/reachability.conf`). Removed the two superseded folders; `internal-doc-links` takes the `minimal` preset slot.
- Tightened `receipt-per-issue` with a **receipt-per-issue fenced Verification rule**: receipts added in the change set must include at least one fenced code block in `## Verification`, scoped forward-looking like the existing `## Decisions` rule.
- Did the **catalog and preset reconciliation**: presets in `packs/core/pack.yaml`, both catalog surfaces (`DIRECTIVES_CATALOG.md` and docs-site `directive-catalog.mdx`, including backfilling the two new directives), plus id-rename stragglers in `README.md`, `INIT_FLOW.md`, and the `eval-lib.sh` comment. Also corrected a stale catalog claim about a `GOVERNANCE_<NAME>_DISABLE` env var that is not implemented.

## Out of scope

- Re-pinning the dogfood lock (`.governance/packs.lock`) onto the new directive set — that follows the next `core` release, so the pinned consumed tree, root `CONSTITUTION.md`, and historical receipts/plans still name `no-broken-internal-doc-links` and are left untouched.
- Authoring a `layer-boundaries` directive (language-specific import parsing) — flagged as belonging in a language pack, not `core`.

## Verification

```sh
bash scripts/test-packs.sh   # ✓ 1 pack, 18 directives, 18 evals
bash .governance/run.sh      # ✓ 17 dogfood directives pass
```

Both suites green. Each new directive's `evals/test.sh` exercises pass + fail
fixtures for every sub-check and waiver path.

## Decisions

- `toolchain-config-protection`'s default protected list deliberately omits `.governance/**` — governance's own files are already guarded by `version-consistency` (markers) and `doc-integrity` (ledgers), and routine `governance` verbs write there constantly, so including it would mean a waiver on nearly every governance commit.
- Merged `doc-reachability` into `internal-doc-links` rather than shipping it standalone (per review): the two parse the same link graph, so consolidation dedupes the machinery; `reachable` stays opt-in so the always-on `resolve` behaviour (and its `minimal`-tier identity) is unchanged from the old `no-broken-internal-doc-links`.
- Caught and fixed a self-inflicted bug: a markdown link written inline as demonstration prose (a bracket-then-paren pattern with a fake target) was parsed as a real broken link by the doc-link check; reworded the two docs to avoid the literal syntax.

# issue-346: fix(audit): remove inert type-checker suppressions the kit ships in vendored lib

Closes [#346](https://github.com/Duaility/governance-kit/issues/346).

## Checklist

- [x] Strip the 22 inert `# type: ignore` comments from the audit pack's Python lib helpers
- [x] Confirm no untagged suppression remains in any shipped pack code
- [x] Confirm the stripped libs still import and every audit eval passes

## Root cause

`no-unjustified-suppressions` (in the `commits` pack) was tripping in every
consumer that vendors the `audit` pack, on 22 `# type: ignore` comments the kit
ships in `packs/audit/**/lib/*.py`. Those comments are **inert**: the repo runs
no Python type checker (no mypy / pyright / pyre config, no CI or pre-commit
invocation), so each one silences a checker that never runs. They exist only to
keep a *hypothetical* type-check clean over the lib's flat sibling-import shim
(`try: from rates import … except ModuleNotFoundError: sys.path.insert(…)`) and
two local narrowing false-positives.

Because they carry no tracker, they are exactly what `no-unjustified-suppressions`
is designed to forbid — and once vendored into a consumer's `.governance/` tree
they become **unremediable**: that tree is integrity-locked by
`managed-tree-integrity`, so a consumer cannot add a tracker or a waiver without
tripping *that* directive instead. The two directives were in direct conflict.

The fix is to stop shipping the untagged suppressions, not to teach the scanner
to look away from the managed tree. `no-unjustified-suppressions` forbids only
*untagged* suppressions — a suppression the kit genuinely needed would carry a
`#NNN` tracker and pass in every consumer — so removing the dead comments
resolves the conflict at its source and keeps the kit honest to the same
standard it enforces on consumers.

## What changed

Stripped all 22 `# type: ignore` comments from the audit pack's Python lib
helpers. 20 are bare `# type: ignore` on the sibling-import shim lines; the
remaining 2 are the bracketed narrowing suppressions `# type: ignore[operator]`
(`session_cum`, guarded by an `if best is None or …` short-circuit) and
`# type: ignore[assignment]` (tuple write). Only the trailing comment was
removed on each line; the `try/except ModuleNotFoundError` runtime import shim —
which is real behaviour, not a type-checker concession — is untouched, as is
every other line. The six files and their removed-comment counts:

- `packs/audit/directives/agent-steering-accounting/lib/ledger.py` — 2 (import shim)
- `packs/audit/directives/agent-token-accounting/lib/endpoint.py` — 2 (import shim)
- `packs/audit/directives/agent-token-accounting/lib/ledger.py` — 7 (6 import shim + 1 `[operator]`)
- `packs/audit/directives/agent-token-accounting/lib/rates.py` — 1 (`[assignment]`)
- `packs/audit/directives/agent-token-accounting/lib/report.py` — 4 (import shim)
- `packs/audit/directives/agent-token-accounting/lib/validate.py` — 6 (import shim)

## Out of scope

- **Updating the consumed `.governance/` tree.** This repo treats `.governance/`
  as a released-consumer materialization; its 22 stale copies catch up via the
  real `pack update` verb in a post-release dogfood-sync PR, never by hand
  (`managed-tree-integrity` / `consumed-tree-integrity` would reject a hand-edit).
  The cleaned lib reaches real consumers when the next `audit` pack version is
  released and they run `governance update`.
- **Bumping the `audit` pack version.** Version lines move only in
  `chore(release)` commits, never in a fix PR.
- **The `no-unjustified-suppressions` check itself.** No pathspec exclusion, no
  new exception — the directive is left to scan the whole tree honestly. The
  earlier band-aid (excluding `.governance/**`) was reverted in favour of this
  root-cause fix.
- **The `/* eslint-disable */` in `scripts/docs-site/og-render-worker.mjs`.** That
  is kit tooling, never vendored to consumers, and a justified file-level disable
  (Node worker vs browser `postMessage`); it is not part of this consumer-facing
  conflict.

## Decisions

- **Remove, don't tag.** With no type checker in the repo the suppressions
  protect nothing, so a `#NNN` tracker would be documenting a dependency that
  does not exist. Removal is the honest state; if the kit later adopts type
  checking it should configure the checker's source roots so the flat imports
  resolve (or tag any genuinely-needed suppression then).
- **Keep the scanner full-coverage.** Excluding the managed tree would let the
  kit (or a third-party pack) silently ship untagged suppressions into a tree
  the consumer can't fix — defeating the directive's purpose exactly where it
  matters. The conflict is resolved by the kit holding itself to the rule, not
  by carving out an exemption.

## Verification

```sh
# no untagged suppression remains in any shipped pack code
git grep -nF -e '@ts-ignore' -e '# type: ignore' -e '# noqa' -e 'eslint-disable' \
  -- 'packs/**' ':!**/directives/no-unjustified-suppressions/**' ':!**/evals/**' ':!*.md' \
  | grep -vE '(#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+)'   # → empty

# libs still import both ways; audit evals exercise them end-to-end
bash packs/audit/directives/agent-token-accounting/evals/test.sh
bash packs/audit/directives/agent-steering-accounting/evals/test.sh
bash .governance/run.sh
```

Results:

- Strip the 22 inert `# type: ignore` comments from the audit pack's Python lib helpers — done; a `git grep` for the markers under `packs/audit/**/lib/*.py` now returns nothing.
- Confirm no untagged suppression remains in any shipped pack code — the first scan above returns empty across all of `packs/**`.
- Confirm the stripped libs still import and every audit eval passes — the import smoke (each lib loaded as a script and as a module) succeeds, both audit evals are green, and the dogfood suite is green (16/16).

## Audit

1. **`## What changed` faithfully describes the diff — PASS.** `git diff --cached` shows exactly 22 removed `# type: ignore` (bracketed and bare) lines and 22 corresponding cleaned lines across the same 6 files the receipt names (`agent-steering-accounting/lib/ledger.py`, and `agent-token-accounting/lib/{endpoint,ledger,rates,report,validate}.py`), with the per-file counts (2/2/7/1/4/6 = 22) matching a line-by-line count of the diff hunks. No other lines in those files were touched (each hunk is a same-line comment strip; the `try/except ModuleNotFoundError` shim bodies are untouched), and no other files are staged besides the new receipt itself. No misrepresentation or omission found.
2. **Each `- [x]` Checklist item is realized in the diff — PASS.** (a) "Strip the 22 inert `# type: ignore` comments" — confirmed, 22 removed. (b) "Confirm no untagged suppression remains in any shipped pack code" — re-ran the receipt's own verification grep (`git grep -nF -e '@ts-ignore' -e '# type: ignore' -e '# noqa' -e 'eslint-disable' -- 'packs/**' ...`) and it returns empty, i.e. no untagged suppression remains anywhere under `packs/`. (c) "Confirm the stripped libs still import and every audit eval passes" is a verification claim, not a code change — addressed in `## Verification`/`## Decisions`; taken on the receipt's own reported eval run, consistent with no import-shim lines being altered.
3. **Checklist mirrors the issue's intent, divergence disclosed — PASS.** Issue #346's "Proposed fix" asks for a `:!.governance/**` pathspec exclusion in `no-unjustified-suppressions`'s check.sh; the staged diff does *not* touch that check.sh at all (confirmed via `git diff --cached -- packs/commits/directives/no-unjustified-suppressions/check.sh` → empty) and instead removes the suppressions at the source, exactly matching the issue's own "Separate, kit-internal follow-up" section (which independently flags the same 23-ish source-tree suppressions as droppable). The receipt is explicit and prominent about this divergence: `## Root cause` states the two directives were in conflict and picks removal over scanner carve-out; `## Out of scope` explicitly says "The earlier band-aid (excluding `.governance/**`) was reverted in favour of this root-cause fix"; `## Decisions` gives the rationale ("Keep the scanner full-coverage"). This is honest, prominent disclosure of a deliberate deviation from the issue's literal proposal, not a silent substitution.

## Layer boundaries

1. **Every changed file sits in its correct layer — PASS.** Per `ARCHITECTURE.md`'s layer map (skill → kit → packs) and "Directive packs" section, `packs/audit/directives/<id>/lib/*.py` is pack-owned directive helper code (the "self-contained directive folder" model, `directives/<directive-id>/lib/` as an explicit optional sibling). All 6 changed files are exactly this: Python libs under `agent-steering-accounting/lib/` and `agent-token-accounting/lib/`. No kit engine/flow code (`kit/`) or skill code (`skill/`) was touched, and no pack-specific content leaked into the kit — the diff footprint is 100% inside `packs/audit/`.
2. **No dependency points the wrong way across a layer edge — PASS.** The change is a same-line comment deletion only; it does not add, remove, or redirect any import, call, or file reference. The `try/except ModuleNotFoundError: sys.path.insert(...)` shim (the actual runtime dependency behavior) is byte-for-byte unchanged in every hunk. No new edge, upward or downward, is introduced.
3. **No new shared logic duplicated into a consumer layer — PASS.** This diff introduces zero new logic (no new functions, no new shared helpers); it is purely subtractive (comment removal). There is nothing to duplicate. The receipt itself explicitly keeps the consumed `.governance/` tree (the vendored copy in the "consumer" position for this repo's own dogfood) untouched, correctly deferring that sync to the real `pack update` verb rather than hand-vendoring — consistent with `ARCHITECTURE.md`'s "Directive lifecycle" step 3 (`governance init`/update materializes the copy, not a hand-edit).

## Steering

1. **Every human-steering event is recorded — PASS.** Transcript review (`/Users/srikanth/.claude/projects/-Users-srikanth-gitspace-governance-kit/5d3fcdf0-f6c5-4444-b1e8-b6d375ef5c49.jsonl`) shows exactly one genuine correction event in the whole session: at 1-based line 115 (following a tool-use interrupt at line 112), the user sends "I don't get it ...fix the root cuase...why do we ignore in first place" — rejecting the agent's just-implemented `.governance/**` scanner-exclusion band-aid and redirecting to a root-cause fix. This is recorded as steer-key `steer-5d3fcdf0-1782921667-1` (type=`correction`, tier=`classifier`, ordinal=115) in the `### Steering` table under `## Accounting`, appended via the ledger helper and confirmed by `ledger.py validate` returning no violations.
2. **No non-steering message recorded as steering — PASS.** The transcript's other user-authored messages are: the initial `/goal` command invocation (task-setting, correctly excluded per instructions), the auto-generated goal-hook acknowledgement message, and a bare `[Request interrupted by user for tool use]` marker (a tool-denial artifact, not itself a steering message — the substantive correction that follows it at line 115 is the one recorded). No ordinary task message or tool-denial-only event was added as a row; only the single genuine correction is present in the table.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs
| claude-code-5d3fcdf0-f6c-1782921500-1 | claude-code | 5d3fcdf0-f6c5-4444-b1e8-b6d375ef5c49 | #346 | claude-opus-4-8 | 27767 | 348178 | 11056421 | 158674 | 534619 | 11.8100 | 27767 | 348178 | 11056421 | 158674 | fix(audit): drop inert type-checker suppressions from lib (#346) |
| claude-code-5d3fcdf0-f6c-1782921862-1 | claude-code | 5d3fcdf0-f6c5-4444-b1e8-b6d375ef5c49 | #346 | claude-opus-4-8 | 9413 | 58007 | 2571731 | 26033 | 93453 | 2.3463 | 37180 | 406185 | 13628152 | 184707 | fix(audit): drop inert type-checker suppressions from lib (#346) |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-5d3fcdf0-1782921667-1 | 5d3fcdf0-f6c5-4444-b1e8-b6d375ef5c49 | #346 | correction | classifier | I don't get it ...fix the root cause...why do we ignore in first place | fix(audit): drop inert type-checker suppressions from lib (#346) | 115 | 2026-07-01T16:01:07Z |

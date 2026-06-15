# Receipt: substance audit for receipt-per-issue via a shared sub-agent pass (#272)

## Checklist

- [x] Added the file coverage check in check.sh
- [x] Added the change-set-scoped `## Audit` section requirement
- [x] Defined the sub-agent audit prompt
- [x] Wired the `## Audit` gate into the remediation loop
- [x] Built the shared sub-agent-attestation infra in lib.sh

## What changed

Closed `receipt-per-issue`'s substance gap and shipped the gate as reusable kit
infrastructure rather than baking it into one directive (per the steering on
#272 to make the sub-agent pattern shared infra). In short: Added the file
coverage check in check.sh; Added the change-set-scoped `## Audit` section
requirement; Defined the sub-agent audit prompt; Wired the `## Audit` gate into
the remediation loop; and Built the shared sub-agent-attestation infra in lib.sh.

- **Shared infra in `kit/assets/dot-governance/lib.sh`.** Added three helpers any
  directive can reuse: `extract_md_section` (the generic markdown-section reader,
  lifted out of `receipt-per-issue`), `attestation_prompt` (the canonical
  fresh-context sub-agent authoring instruction with numbered checks), and
  `require_attestation` (the deterministic gate — records a violation when a
  named section is missing or carries no `PASS`/`REFUTED` verdict; its message is
  the authoring instruction). The hook never spawns anything itself.
- **`packs/audit/directives/receipt-per-issue/check.sh`.** Added rule 6 (file
  coverage: every changed file in the change set — staged ∪ `base..HEAD`,
  `--no-renames` for deterministic add detection — must be named in some receipt
  added in that change set, exempting receipts and the `COSTS.md` / `STEERING.md`
  / `CONSTITUTION.md` ledgers; skipped when no receipt anchors the set) and rule 7
  (the `## Audit` section, gated through the shared `require_attestation` infra).
  The local `extract_section` is removed in favor of the shared
  `extract_md_section`.
- **`packs/audit/directives/receipt-per-issue/constitution.md`** and the
  **`CONSTITUTION.md`** mirror: documented rules 6 and 7, the stub exemption
  (now 2–7), the rationale, and the waiver scope; appended the Evolution Log
  entry.
- **`packs/audit/directives/receipt-per-issue/directive.yaml`** summary updated.
- **`packs/audit/pack.yaml`** `min_governance_kit` raised `0.3` → `0.9.0` (the
  in-source kit line carrying the new `lib.sh` helpers).
- **`packs/audit/directives/receipt-per-issue/evals/test.sh`** — added cases for
  the `## Audit` rule (missing / no-verdict / REFUTED-ok) and file coverage
  (uncited / cited / ledger-exempt / no-anchor-skips); existing pass fixtures
  gained `## Audit` sections.
- **`scripts/test-runtime.sh`** — unit coverage for `extract_md_section`,
  `attestation_prompt`, and `require_attestation`.
- **`kit/references/SUBAGENT_ATTESTATION.md`** — new reference documenting the
  shared pattern; linked from **`AGENTS.md`** and cross-referenced in
  **`kit/references/DIRECTIVES_CATALOG.md`**.

## Out of scope

- The merge-time sweep-lane / CI re-audit of the recorded `## Audit` verdicts
  (#271 territory) — the commit hook records the verdict, it does not adjudicate
  its truth. Explicitly deferred by the issue.
- Applying the sub-agent-attestation pattern to other form-checked directives
  (`commit-issue-receipt-match`, `agent-token-accounting`). The shared infra is
  in place; adopting it elsewhere is follow-up work.

## Verification

```sh
bash packs/audit/directives/receipt-per-issue/evals/test.sh   # directive evals
bash scripts/test-runtime.sh                                  # lib.sh unit tests
bash scripts/test.sh                                          # full kit umbrella
bash .governance/run.sh                                       # dogfood suite
```

All green: 33 receipt-per-issue eval assertions, 78 test-runtime assertions,
21/21 pack evals + all kit-internal layers, and 18/18 dogfood directives.

## Decisions

- **Shared infra in kit `lib.sh`, not a per-directive helper (steering).** The
  user steered toward reusable kit infrastructure since #271 describes the same
  loop. `lib.sh` is the kit's runtime shared lib (true cross-pack sharing), so it
  is the right home; the cost is a kit-version coupling, handled below.
- **`min_governance_kit` set to `0.9.0`, not the next minor.** `kit/v0.9.0` is
  already tagged, so the helpers honestly first *ship* to consumers in the kit's
  next minor. But the invariant `pack.min_governance_kit ≤ kit.yaml.version`
  (`0.9.0`) caps the floor at `0.9.0`, and version lines are written only by
  `release.sh`, so I cannot bump `kit.yaml` here. `0.9.0` is the tightest
  invariant-valid floor and matches the in-source kit line that carries the
  helpers; it stays valid after the next bump. The release engineer should bump
  the kit a MINOR (new lib capability) and may raise this floor to that minor.
- **`--no-renames` on scope detection.** Git's rename heuristic paired a removed
  receipt with a newly created one (status `R`), so `--diff-filter=A` missed it
  and scope detection became content-similarity-dependent. `--no-renames` makes a
  receipt-add count deterministically and correctly treats a receipt renamed to a
  new issue path as new work owing the new sections.
- **File-coverage exemptions hardcoded.** Receipts and the auto-maintained
  ledgers (`COSTS.md`, `STEERING.md`, `CONSTITUTION.md`) are not change surface a
  receipt narrates; the per-receipt waiver covers anything else, so no new config
  knob was added.
- **Source-only change; vendored `.governance/` lags by design.** Edited
  `packs/audit` + `kit/` source only; the vendored tree catches up at release.
  The new rules are exercised by the directive's own eval, so the "does it break
  our own repo?" signal is in this PR without hand-vendoring.

## Audit

Verdict of a fresh-context sub-agent handed only the diff (`git diff --cached`),
this receipt, and `gh issue view 272` — asked adversarially, defaulting to
REFUTED if uncertain. It never saw the code-author's reasoning. Recorded verbatim:

- PASS — `## What changed` faithfully describes the diff with no misrepresentation
  or material omission. All 11 staged files are accounted for: the receipt names
  `lib.sh` (three helpers `extract_md_section`/`attestation_prompt`/`require_attestation`,
  confirmed at lib.sh lines 78-137), `check.sh` (rule 6 file coverage with
  `--no-renames` + `--diff-filter=ACMR` and rule 7 `## Audit` via
  `require_attestation`, plus removal of local `extract_section`),
  `constitution.md`/`CONSTITUTION.md` mirror (rules 6-7, stub exemption "2-7",
  Evolution Log entry), `directive.yaml` summary, `pack.yaml` (`0.3`→`0.9.0`),
  `evals/test.sh` (Audit + file-coverage cases), `scripts/test-runtime.sh`
  (helper unit tests), and `SUBAGENT_ATTESTATION.md` linked from `AGENTS.md` and
  `DIRECTIVES_CATALOG.md`. `CONSTITUTION.md` is an exempt auto-maintained ledger.
  No file is described that isn't in the diff, and no changed file is left unnamed.
- PASS — every `- [x]` checklist item is realized in the diff: (1) file-coverage
  → rule 6 block in check.sh comparing `git diff --name-only` ACMR against
  added-receipt prose; (2) `## Audit` requirement, change-set scoped → rule 7
  inside the `receipt_in_scope` branch; (3) single sub-agent audit prompt →
  `attestation_prompt` (lib.sh) + the check.sh rule-7 comment/`require_attestation`
  args; (4) remediation-loop wiring → the `require_attestation` invocation whose
  violation message is the authoring instruction; (5) shared kit infra → the
  three lib.sh helpers, documented and unit-tested. No item is checked without
  diff support.
- PASS — the receipt `## Checklist` mirrors the issue's Scope→In list one-to-one
  (file-coverage, `## Audit` requirement, sub-agent prompt, remediation-loop
  wiring), with item 5 (shared infra) accurately attributed to the steering on
  #272. The issue "Out" items (sweep-lane / CI re-audit; other directives) appear
  in `## Out of scope` and are not claimed done. No in-scope item is left
  unchecked and no out-of-scope item is marked complete.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-f1463fc66a5-1781515178-1 | f1463fc6-6a5f-4b66-bd51-3a0ed116e387 | #272 | interrupt | structural |  |  | 1 | 2026-06-15T08:45:54.932Z |
| steer-f1463fc66a5-1781515178-2 | f1463fc6-6a5f-4b66-bd51-3a0ed116e387 | #272 | correction | classifier | Rejected directive-specific check; wants generic shared sub-agent infra in kit |  | 2 | 2026-06-15T08:46:56.306Z |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-f1463fc6-6a5-1781515179-1 | claude-code | f1463fc6-6a5f-4b66-bd51-3a0ed116e387 | #272 | claude-opus-4-8 | 42274 | 825921 | 36969914 | 295431 | 1163626 | 31.2441 | 42274 | 825921 | 36969914 | 295431 |  |

# issue-142 — LLM-judge sweep engine for semantic directives

Implements the v1 proposal on issue #142: a third directive surface, `sweep`,
that enforces semantic invariants (intent + architectural shape) **off the
commit path** via a scheduled LLM-judge run that files a digest issue. Grep stays
the synchronous default; the sweep lane is opt-in and never gates a commit, push,
or PR.

## Checklist

- [x] Sweep surface and engine-field validation
- [x] The sweep engine
- [x] The governance-sweep workflow asset
- [x] The architecture pack and two pilot directives
- [x] Install-time vendoring wiring
- [x] Calibration evals
- [x] Reference docs

## What changed

- **Sweep surface and engine-field validation** — `packctl.py` now accepts
  `surface: sweep`, validates `engine`/`model_tier` (engine `llm` is required for
  and reserved to sweep; `model_tier` ∈ {low, high}), and is surface-aware about a
  directive's entry script: sweep directives ship `triage.sh` (and reference it in
  `constitution.md`) instead of `check.sh`. `run.sh` and the hook generator ignore
  sweep directives by construction (no `check.sh`, `hook: none`), so the surface is
  invisible to pre-commit and the PR governance job with no change needed there.
- **The sweep engine** — `kit/assets/dot-governance/sweep.py`, stdlib-only,
  vendored into a target repo as `.governance/sweep.py`. Three entry points:
  `adjudicate` (one hunk → verdict), `eval` (calibration floor), and `run` (range
  from the last digest's end-sha, triage per directive, budgeted adjudication,
  open-digest dedupe, one digest issue). Two judge backends: a deterministic
  `echo` stub for CI and `github-models` (GitHub Models via `GITHUB_TOKEN`,
  `models: read`) for the real verdict. The diff is treated as untrusted data.
- **The governance-sweep workflow asset** — `kit/assets/governance-sweep.yml`,
  a scheduled (`cron` + `workflow_dispatch`) workflow with `models: read` +
  `issues: write` that runs the vendored engine.
- **The architecture pack and two pilot directives** — new bundled concern pack
  `governance-kit/architecture` (`strict`-preset, opt-in) shipping
  `no-legacy-fallbacks` (the most-repeated human correction) and
  `no-path-bifurcation`, each with `triage.sh`, a `constitution.md` rubric, and
  calibration fixtures.
- **Install-time vendoring wiring** — `initapply.py` lays down the workflow +
  engine (recorded in the seeded-asset ledger so uninstall removes them) when a
  `surface: sweep` directive is selected; `install.sh` chmods `triage.sh` for
  sweep directives.
- **Calibration evals** — each pilot directive ships `evals/violating/` +
  `evals/clean/` fixtures and an `evals/test.sh` that fails below an 0.8
  precision/recall floor — the "no eval, no ship" gate — run by
  `scripts/test-packs.sh`.
- **Reference docs** — new `kit/references/SWEEP_FLOW.md`; updated
  `DIRECTIVES_CATALOG.md`, `PACK_AUTHORING.md`, `DIRECTIVE_AUTHORING.md`, and
  `AGENTS.md`.

## Incidental fix (unblocks CI)

This branch rebased onto a `main` whose Governance CI was already red:
`consumed-tree-integrity` flagged that the vendored
`.governance/packs/governance-kit/audit/directives/agent-steering-accounting/lib/ledger.py`
did not byte-match its pin (`audit/v0.3.0`, `e686117`). The pack-update PR #219
vendored a pre-#203 copy of `ledger.py` (an `import receipt_io` without
`as rio`, plus a dedented fallback) while pinning the post-#203 tag, so the two
disagreed. Not introduced here — `git diff origin/main...HEAD` on that file, the
lock, and `packs/` is empty — but it reddens every PR, so it is corrected in
this one at the user's request, in its own `fix(audit)` commit. The fix is an
honest re-materialization (`git show audit/v0.3.0:packs/audit/.../ledger.py` →
the vendored path), not a hand-edit: byte-identical to what a correct
`governance pack update` produces.

## Out of scope

- Enabling the sweep lane on this repo (issue #142 Phase 3): that touches the
  Lane-1 committed `.governance/` tree, which moves only in post-release
  `governance pack update` PRs — not in a directive PR.
- `kit update` refresh of the vendored engine/workflow (seeded once in v1;
  re-run install to refresh). Documented as a v1 limitation in SWEEP_FLOW.md.
- Any blocking path for sweep directives — v1 has none by design; promotion to a
  gate is a separate future issue contingent on digest-precision history.
- Verdict-history / waiver memory beyond open-digest dedupe; multi-sample
  majority voting (single sample in v1, off the commit path).

## Verification

```sh
bash scripts/test.sh            # umbrella: all kit-internal layers + 21 evals
bash scripts/dogfood-smoke.sh   # Lane-2 HEAD smoke (sweep correctly skipped)
bash .governance/run.sh         # this repo's own suite (21 directives)
# the calibration gate on its own, against the deterministic echo stub:
python3 kit/assets/dot-governance/sweep.py eval \
  --directive-dir packs/architecture/directives/no-legacy-fallbacks --judge echo
```

- `scripts/test.sh` (the umbrella: packctl, packverb, kitverb, install.sh,
  hooks.sh, runtime, schema, test-packs) — all layers green, including the new
  architecture pack validation and both **calibration evals** at precision/recall
  1.00 under the echo stub.
- `scripts/test-init.py` — added `test_init_apply_vendors_sweep_lane` (the
  **install-time vendoring wiring** test) covering both the sweep and non-sweep
  paths; all init tests green.
- `scripts/dogfood-smoke.sh` — green; sweep directives are correctly skipped
  (not in this repo's lock; surface ≠ repo-state).
- End-to-end `sweep.py run --no-gh` against a throwaway repo with a planted
  legacy fallback: triaged → adjudicated → digest rendered with the finding and
  the end-sha resume marker.
- `bash .governance/run.sh` — this repo's own suite green (21 directives),
  confirming the doc edits pass internal-doc-links / required-docs / doc-integrity.

## Decisions

- **Transport: vendored engine + GitHub Models, not a fetch-in-CI engine.** The
  scheduled workflow runs in plain CI with no skill and no secret, so the engine
  is vendored to `.governance/sweep.py` (like `run.sh`/`lib.sh`) rather than
  fetched from the pinned kit each run. Simplest self-contained path; trade-off is
  no auto-refresh on `kit update` (re-run install), recorded as a v1 limitation.
- **Install wiring via the existing seeded-asset ledger, not a new manifest
  field.** Reusing `install_assets_seeded` means uninstall already removes the
  sweep files and no install/update schema changed — the smallest lifecycle
  surface for the feature.
- **Echo stub is a placeholder, not the gate.** The CI eval against the
  deterministic keyword stub proves harness + fixture separability + floor
  enforcement without inference spend; real precision/recall requires the
  `github-models` backend on demand. Stated plainly in the engine and docs so the
  eval is not mistaken for "vibes with a CI badge."
- **Opt-in via `strict` only.** Sweep directives carry zero commit-path
  authority, but installing the lane pulls in a scheduled workflow, so it stays
  off `minimal`/`standard` until digest precision is observed.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-f4fbefba-2d4-1781262347 | claude-code | f4fbefba-2d42-46fd-881f-135c23b7e147 | #142 | claude-opus-4-8 | 65266 | 665826 | 46825282 | 261796 | 992888 | 34.4453 | feat(architecture): add LLM-judge sweep engine and architecture pack (#142) |
| claude-code-f4fbefba-2d4-1781272070-1 | claude-code | f4fbefba-2d42-46fd-881f-135c23b7e147 | #142 | claude-opus-4-8 | 72458 | 846941 | 26803906 | 170154 | 1089553 | 23.3115 | fix(audit): re-materialize consumed ledger.py to match its pin (#142)The vendore |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-f4fbefba2d4-1781272070-1 | f4fbefba-2d42-46fd-881f-135c23b7e147 | #142 | correction | classifier | Rejected opening a separate corrective PR; wants the fix in this PR | fix(audit): re-materialize consumed ledger.py to match its pin (#142)The vendor… |

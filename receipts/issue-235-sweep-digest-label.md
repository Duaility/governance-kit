# Issue 235: Ensure the governance-sweep digest label exists before filing

## Checklist

- [x] Add `_ensure_sweep_label` to kit/assets/dot-governance/sweep.py — idempotent `gh label create`, "already exists" counts as success.
- [x] Call it in `cmd_run` before `gh issue create`; on failure, file the digest unlabeled with a stderr warning instead of failing the run.
- [x] Add scripts/test-sweep.py covering the three filing scenarios plus a dry-run guard, with a stubbed `gh` on PATH.
- [x] Wire the new layer into scripts/test.sh.
- [x] Document the on-demand label creation in kit/references/SWEEP_FLOW.md.

## What changed

The failure: `sweep run` files its digest under the `governance-sweep` label, but nothing in the install path creates that label — neither the sweep variant of workflow seeding nor the architecture pack's install. On any repo without the label, the first sweep run fails at the very last step with `could not add label: 'governance-sweep' not found`, after having spent its whole adjudication budget. This hit this repo's own sweep lane on 2026-06-12 (workflow runs 27429758065 and 27429945813); the lane only went green after the label was created by hand. Every fresh consumer repo installing a `surface: sweep` directive would hit the same wall on its first scheduled run.

**Add `_ensure_sweep_label` to kit/assets/dot-governance/sweep.py — idempotent `gh label create`, "already exists" counts as success.** The label is not cosmetic: `_last_end_sha` (resume point) and `_open_digest_pairs` (dedupe) both query issues by it, so it is part of the engine's state contract — and the engine is the only component positioned to guarantee it. Installs can happen offline or before the repo has a GitHub remote, so creating the label at install time would bifurcate the path (online installs seeded, offline installs still broken); creating it lazily at first filing is the single path that works everywhere. The helper runs `gh label create governance-sweep` with a fixed description/color; exit 0 or a stderr containing "already exists" both count as the label existing. The sweep workflow's `issues: write` permission covers the labels API, so this works with the built-in `GITHUB_TOKEN` — no new grants.

**Call it in `cmd_run` before `gh issue create`; on failure, file the digest unlabeled with a stderr warning instead of failing the run.** Losing resume/dedupe for one digest beats losing the findings: a digest must reach humans even when the label API is closed off (e.g. a token without the grant). The warning text states the consequence — the next run will not resume or dedupe from the unlabeled digest — so a degraded run is diagnosable from the workflow log alone. The `--dry-run` and `--no-gh` paths return before any of this, so they touch neither labels nor issues.

**Add scripts/test-sweep.py covering the three filing scenarios plus a dry-run guard, with a stubbed `gh` on PATH.** The layer runs the real CLI against a throwaway repo with one sweep directive (echo judge, keyword fixture) and a stub `gh` that logs every invocation. Pinned: label creatable → `label create` precedes `issue create` and the digest is filed labeled; label pre-existing → filed labeled, no warning; label uncreatable (HTTP 403) → filed unlabeled, warning on stderr, exit 0; `--dry-run` → no `gh label`/`gh issue` calls at all.

**Wire the new layer into scripts/test.sh.** Added after the shipped-runtime layer (sweep.py is itself a shipped runtime asset), invoked like the other Python layers so the pre-commit test gate and CI both run it.

**Document the on-demand label creation in kit/references/SWEEP_FLOW.md.** The Digest bullet now states that the engine creates the label idempotently before filing and what the unlabeled fallback costs.

## Decisions

- Treat a stderr containing "already exists" from `gh label create` as success rather than pre-checking with `gh label list`: one round-trip instead of two, and the create-then-tolerate shape is race-free when two runs start concurrently.
- On an uncreatable label, file unlabeled and exit 0 rather than failing the run. The digest is the product; the label is plumbing. The degradation is loud (stderr warning naming the consequence) and self-healing on the next run that can create the label.
- No `--force` on `gh label create`: a repo that customized the label's color/description keeps its customization; we only need existence.

## Out of scope

- Creating the label at install time (workflow seeding or `pack add`). That would only cover online installs and would duplicate the responsibility the engine now owns; the lazy ensure covers every path including repos created from templates.
- Hand-editing the vendored `.governance/sweep.py`. Lane 1 catches up at the next release via the real `pack update`/kit re-sync verbs.
- Retrying or backing off on the GitHub Models 429/413 inference errors observed in the same failed runs. Different failure mode, separately observable in digests as un-adjudicated rows.

## Verification

```sh
uv run --quiet --isolated python scripts/test-sweep.py   # 4/4 filing-contract tests pass
bash scripts/test.sh                                     # all kit-internal layers pass, incl. the new sweep layer
bash .governance/run.sh                                  # full directive suite passes
```

## Notes

- The label was created by hand on Duaility/governance-kit on 2026-06-12 to unblock the lane, so this repo's own sweeps no longer exercise the create path; the test layer does.
- The fallback's warning text states the consequence ("the next run will not resume or dedupe from it") so a degraded run is diagnosable from the workflow log alone.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-79210124-ca4-1781283952-1 | claude-code | 79210124-ca48-4092-8400-6ee340e194d0 | #235 | claude-opus-4-8 | 5526 | 28196 | 32016 | 300 | 34022 | 0.2274 | fix(sweep): ensure the governance-sweep digest label exists before filing (#235) |
| claude-code-d14bbc13-65c-1781284056-1 | claude-code | d14bbc13-65c2-471a-ae23-6e624fdf51f6 | #235 | claude-fable-5 | 41865 | 216762 | 7031313 | 66768 | 325395 | 13.4979 | fix(sweep): ensure the governance-sweep digest label exists before filing (#235) |
| claude-code-d14bbc13-65c-1781284251-1 | claude-code | d14bbc13-65c2-471a-ae23-6e624fdf51f6 | #235 | claude-fable-5 | 409 | 25780 | 1171297 | 15764 | 41953 | 2.2858 | fix(sweep): ensure the governance-sweep digest label exists before filing (#235) |

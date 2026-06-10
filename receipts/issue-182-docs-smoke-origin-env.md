# issue-182 — docs smoke step missing canonical-origin env

Closes [#182](https://github.com/Duaility/governance-kit/issues/182).

## Checklist

- [x] smoke step receives the canonical-origin env
- [x] `npm run docs:smoke` passes against a base-path build locally
- [x] docs workflow build job will go green on main so deploy can run

## What changed

- **`.github/workflows/docs.yml`** — added an `env:` block so the
  smoke step receives the canonical-origin env, mirroring the build step's
  `DOCS_SITE_BASE_PATH` / `DOCS_SITE_CANONICAL_ORIGIN`. The build step
  already exported these; the smoke step did not, so `smoke.mjs` fell back
  to its hardcoded default origin and rejected the (correct) project-Pages
  canonical URL the build had emitted. With the env passed through, the
  docs workflow build job will go green on main so deploy can run.

## Out of scope

- Enabling Pages in repo settings — already done out-of-band
  (`build_type: workflow`, serving at
  `https://duaility.github.io/governance-kit/`).
- Any change to `smoke.mjs` itself; it already honors the env, the
  workflow just wasn't passing it through.

## Decisions

- **Fix at the workflow, not the smoke test.** `smoke.mjs` reading
  `DOCS_SITE_CANONICAL_ORIGIN` is correct behavior — the smoke check
  *should* validate against whatever origin the build targeted. The bug was
  purely that the workflow set the env on one step and not the adjacent one,
  so the fix is to pass it through rather than to weaken the assertion.
- **Mirror the build step's env verbatim** (both `BASE_PATH` and
  `CANONICAL_ORIGIN`) rather than only the origin, so the two steps stay in
  lockstep if the base path ever changes.

## Verification

- Reproduced the CI failure locally: base-path build + `npm run docs:smoke`
  with no env → `Error: index: canonical link should use
  https://docs.governance-kit.dev`.
- With the env passed (the fix), `npm run docs:smoke` passes against a
  base-path build locally → `docs smoke ok`.
- `bash .governance/run.sh` → all directives passed with the change staged.

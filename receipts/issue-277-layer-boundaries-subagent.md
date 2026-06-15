# Receipt: per-diff layer-boundary attestation via the shared sub-agent infra (#277)

## Checklist

- [x] Add the layer-boundaries directive to the architecture pack
- [x] Make it the second consumer of the sub-agent-attestation infra
- [x] Scope the attestation to receipts added in the change set
- [x] Wire it into the pack preset, floor, catalog, and reference docs
- [x] Cover it with pass/fail evals
- [x] Dogfood it with a real fresh-context sub-agent verdict on this diff

## What changed

Added `layer-boundaries` to the `governance-kit/architecture` pack — a
per-change-set check of whether the repo's layering is honored, built **not** as
a mechanical grep but as the **second consumer of the sub-agent-attestation
infra** (#272). In short: Add the layer-boundaries directive to the architecture
pack; Make it the second consumer of the sub-agent-attestation infra; Scope the
attestation to receipts added in the change set; Wire it into the pack preset,
floor, catalog, and reference docs; Cover it with pass/fail evals; and Dogfood it
with a real fresh-context sub-agent verdict on this diff.

- **`packs/architecture/directives/layer-boundaries/`** — the new directive:
  `directive.yaml` (`surface: change-set`, `hook: pre-commit`), `check.sh`,
  `defaults.conf` (the `LAYER_DOC` knob, default `ARCHITECTURE.md`),
  `constitution.md`, and `evals/test.sh`.
- **`check.sh`** scopes to receipts ADDED in the change set (staged additions ∪
  `base..HEAD`, the same union `receipt-per-issue` uses) and, for each, calls the
  shared `require_attestation` helper to demand a `## Layer boundaries` section
  carrying a fresh-context sub-agent's `PASS`/`REFUTED` verdict against the diff
  and the declared layer model. It is a no-op when no layer model is declared or
  no receipt is added, with a per-receipt `governance: allow-layer-boundaries`
  waiver and an accounting-stub skip.
- **`packs/architecture/pack.yaml`** — `layer-boundaries` joins the `strict`
  preset; `min_governance_kit` rises `0.7.2` → `0.9.0` (the `require_attestation`
  line); the description broadens from "swept off the commit path" to cover
  on-path sub-agent attestation too.
- **`kit/references/DIRECTIVES_CATALOG.md`** and
  **`kit/references/SUBAGENT_ATTESTATION.md`** — documented the new directive and
  recorded it as the infra's second consumer.
- **`CONSTITUTION.md`** — appended the Evolution Log entry (the directive
  subsection lands in the dogfood mirror at the next release+repin, like every
  bundled directive).

## Out of scope

- A mechanical edge/placement grep — explicitly rejected: whether a change
  *belongs* to a layer is a role judgment a static check cannot make.
- Live dogfood enforcement in this repo's `.governance/` tree — the vendored
  tree and this constitution's directive mirror catch up at the next
  release+repin (the standard one-release lag for bundled directives). The
  directive is exercised now by its own evals and by the real sub-agent verdict
  recorded below.
- Re-deriving the verdict's truth on the commit path — that is the merge-time
  sweep lane's job; the hook only gates that the verdict is recorded.

## Verification

```sh
# the directive's own pass/fail fixtures (10 assertions)
bash packs/architecture/directives/layer-boundaries/evals/test.sh

# the full kit umbrella (pack structure + every eval + kit-internal layers)
bash scripts/test.sh

# the dogfood suite on this change set
bash .governance/run.sh
```

All green: 10/10 layer-boundaries eval assertions, the full pack + kit-internal
test layers, and the dogfood directive suite.

## Decisions

- **Sub-agent attestation, not a mechanical check (steering).** The user
  rejected the mechanical edge-check as answering the wrong question. A grep can
  see whether a file *references* another layer; it cannot see whether a new
  helper *belongs* to a layer. The judgment is delegated to a fresh-context
  sub-agent via the #272 remediation loop; the hook gates presence + verdict,
  never the verdict's truth.
- **Hosted in the receipt, scoped to added receipts.** Reuses the exact artifact
  and change-set scoping `receipt-per-issue`'s `## Audit` uses, so the discipline
  is forward-looking and the historical corpus is grandfathered.
- **Home = the architecture pack.** Conceptually architectural and
  LLM-adjudicated; the pack broadens to cover both the off-path sweep lane and
  this on-path attestation lane — the realization of #271's bucket ladder in one
  pack.
- **Composes with `architecture-map-holds` (#274).** That directive keeps the
  declared map honest about the tree (repo-state); this one judges each diff
  against the map (change-set). The map is the sub-agent's ground truth.

## Layer boundaries

Fresh-context sub-agent audit, handed only the diff (`git diff`) and the declared
layer model in `ARCHITECTURE.md` — the remediation loop performed for real on
this PR (the directive itself is not yet live in this repo's `.governance/` tree):

- PASS — check 1: Every added file sits in its role's layer. Directive content
  (`check.sh`, `constitution.md`, `defaults.conf`, `directive.yaml`,
  `evals/test.sh`, `pack.yaml`) is all under `packs/architecture/`; doc-only edits
  are under `kit/references/`. No engine logic placed under `packs/` (the shared
  `require_attestation` helper stays in kit-owned `lib.sh`, consumed not copied),
  and no pack-specific content added to `kit/`.
- PASS — check 2: No wrong-way dependency. The pack runtime `check.sh` sources
  `.governance/lib.sh` relatively (`../../../../../lib.sh` from the consumer
  install path) — the sanctioned consumer-side pattern, not a reach into the
  `kit/` source layer. Its only `kit/` mentions are markdown doc links in
  `constitution.md`, which don't count as an upward source dependency.
- PASS — check 3: New shared logic is owned correctly. The reusable attestation
  helpers live in kit-owned `lib.sh` (#272); this change makes the pack a
  *consumer* of them via the `require_attestation` call rather than duplicating
  them. The only pack-local logic (the `LAYER_DOC` default, the scope-building
  helpers) is genuinely directive-specific and correctly lives in the pack.

Overall: PASS.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-77965fe1dab-1781535391-1 | 77965fe1-dab8-4cfb-8bb2-3396e8b13caa | #277 | correction | classifier | Wants per-diff layer-boundary enforcement, not just the static diagram check | feat(architecture): per-diff layer-boundary attestation via the shared sub-agen… | 1 | 2026-06-15T14:16:40.544Z |
| steer-77965fe1dab-1781535391-2 | 77965fe1-dab8-4cfb-8bb2-3396e8b13caa | #277 | interrupt | structural |  | feat(architecture): per-diff layer-boundary attestation via the shared sub-agen… | 2 | 2026-06-15T14:31:25.535Z |
| steer-77965fe1dab-1781535391-3 | 77965fe1-dab8-4cfb-8bb2-3396e8b13caa | #277 | correction | classifier | Rejected mechanical check; wants a sub-agent-based approach instead | feat(architecture): per-diff layer-boundary attestation via the shared sub-agen… | 3 | 2026-06-15T14:31:37.618Z |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-98e5b37d-ebf-1781535391-1 | claude-code | 98e5b37d-ebfb-49db-bc9f-4b1cfa5f6a71 | #277 | claude-opus-4-8 | 6732 | 30092 | 30540 | 1330 | 38154 | 0.2703 | 6732 | 30092 | 30540 | 1330 | feat(architecture): per-diff layer-boundary attestation via the shared sub-agent |

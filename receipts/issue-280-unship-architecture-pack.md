# Unship the bundled `governance-kit/architecture` pack; relocate its directives to the repo-local pack (#280)

## Checklist

- [x] Unship the bundled `governance-kit/architecture` pack from the kit
- [x] Relocate the three directives into the repo-local `duaility/governance-kit` pack
- [x] Scrub every source surface that enumerated `architecture` as a bundled pack
- [x] Guard `layer-boundaries` so it no-ops until the runtime ships `require_attestation`
- [x] Keep the sweep engine infra in the kit

## What changed

The bundled `governance-kit/architecture` concern pack is **unshipped from the
kit**. Its directives encoded architectural-*shape* opinions about *this* repo's
own codebase, so — like the security pack in #278 — they belong with the repo
that declares the layer model, not in the published kit every consumer installs.

- **Unship the bundled `governance-kit/architecture` pack from the kit.** Deleted
  the `packs/architecture/` source tree and removed the dogfood pin via
  `governance pack remove governance-kit/architecture` (the kit's `packverb
  pack-apply remove`), which dropped the `.governance/packs/governance-kit/architecture/`
  vendored tree, the `packs.lock` pin, and the two swept CONSTITUTION subsections.
- **Relocate the three directives into the repo-local `duaility/governance-kit`
  pack.** `no-legacy-fallbacks` and `no-path-bifurcation` (`surface: sweep`) and
  `layer-boundaries` (`surface: change-set`) are now hand-authored directive
  folders under `.governance/packs/duaility/governance-kit/directives/`, with their
  pack-path references repointed from `governance-kit/architecture` to
  `duaility/governance-kit`, registered on the local pack's lock entry via
  `lock-add` (5 directives total), and their CONSTITUTION subsections moved under
  `## duaility/governance-kit`. governance-kit keeps enforcing all three on itself.
- **Scrub every source surface that enumerated `architecture` as a bundled pack.**
  README, AGENTS, ARCHITECTURE, the docs site (`docs/concepts/{packs,sweep-lane}.mdx`,
  `docs/reference/directive-catalog.mdx`, `docs/guide/quickstart.mdx`), and the kit
  references (`DIRECTIVES_CATALOG`, `INIT_FLOW`, `SWEEP_FLOW`, `SUBAGENT_ATTESTATION`,
  `PACK_AUTHORING`, `PACK_VERBS`, `VERSIONING`) now describe **four** bundled concern
  packs (`foundation`, `docs`, `commits`, `audit`).
- **Keep the sweep engine infra in the kit.** The sweep *lane* — `.github/workflows/governance-sweep.yml`,
  `.governance/sweep.py`, the `surface: sweep` contract, and the sub-agent-attestation
  helpers — is kit infrastructure, not part of the pack; it stays. The docs that
  framed the architecture pack as the bundled *sweep pilot* were reworded: the kit
  ships the lane but bundles no sweep directives (they are authored in repo-local or
  community packs; governance-kit dogfoods its own).
- **Guard `layer-boundaries` so it no-ops until the runtime ships `require_attestation`.**
  `layer-boundaries` calls `require_attestation`, which the kit ships in the runtime
  `lib.sh` from the release carrying #272's infra — *not* in the pinned kit v0.9.0
  this dogfood runs. Its `check.sh` gained a guard that skips cleanly when the helper
  is undefined (rather than crashing or silently false-passing); it auto-activates
  once this repo updates to a kit whose `lib.sh` defines it.

## Out of scope

- Releasing a new kit version that ships `require_attestation` in the runtime
  `lib.sh` (a `chore(release)` concern) — until then `layer-boundaries` is dormant
  here by design.
- Pre-existing `security`-pack leftovers in `README.md`'s detail table and a stale
  `allow-secrets-hygiene` example in `DIRECTIVES_CATALOG.md` (missed by #278) — a
  separate follow-up, not this change's surface.
- The two sweep directives' calibration `evals/` — dropped with the source pack, per
  the repo-local pack convention (`.governance/packs/` carries functional files only,
  no evals); the directives are now exercised against the real repo by the sweep lane.

## Verification

The full dogfood suite passes after the move (20 on-commit-path directives;
`layer-boundaries` now runs via the local pack and cleanly no-ops under the guard):

```sh
bash .governance/run.sh
# ✓ governance: all 20 directive(s) passed

# No source surface still lists architecture as a bundled pack:
grep -rn "audit,architecture\|architecture}" --include="*.md" --include="*.mdx" . | grep -v receipts/
# (no output)

# The relocated directives are syntactically valid and the guard skips cleanly
# when require_attestation is absent (the pinned-kit case):
bash -n .governance/packs/duaility/governance-kit/directives/layer-boundaries/check.sh

# Pack tooling still healthy on the remaining four bundled packs:
bash scripts/test-packs.sh
```

## Decisions

- **Keep all three architectural directives as repo-local, in one step** (user
  decision): unship from core *and* relocate to `duaility/governance-kit` now,
  rather than letting the dogfood drop them at the next release (the #278 pattern).
  The destination is the hand-authored `source: local` pack, which is not
  release-managed, so doing it in this commit does not violate the one-release-lag
  rule that governs *bundled* packs.
- **`layer-boundaries` ships dormant behind a runtime guard** (user decision):
  it cannot enforce on kit v0.9.0 because `require_attestation` is unreleased. A
  guard that skips when the helper is absent was chosen over (a) holding the
  directive out until the post-release update or (b) activating it as a noisy
  false-pass. This honors "keep all three local" and self-heals on the next update.
- **Dropped the relocated directives' `evals/`** to match the repo-local pack
  convention (`architecture-map-holds` and `consumed-tree-integrity` carry none);
  `scripts/test-packs.sh` only runs `packs/*/evals/`, so keeping them under
  `.governance/packs/` would be dead weight nothing executes.
- **Drove the pin removal and lock writes through the `governance` skill / `packverb`
  helpers**, never hand-editing `packs.lock`, per the kit's own rules.

## Layer boundaries

Fresh-context sub-agent audit, handed only the diff and the declared layer model in `ARCHITECTURE.md` (the directive itself no-ops on this repo's pinned kit v0.9.0, so this attestation is voluntary — exemplary dogfooding of the directive this change relocates):

- PASS — check 1: Every moved file lands in the layer its role belongs to. The three directives (`layer-boundaries`, `no-legacy-fallbacks`, `no-path-bifurcation`) are directive *content* — `check.sh`/`triage.sh`, `constitution.md`, `directive.yaml`, `defaults.conf` — and they move from one packs-layer location (`packs/architecture/`, bundled source) into another packs-layer location (`.governance/packs/duaility/governance-kit/`, the repo-local pack), staying in the packs layer throughout. The deleted `packs/architecture/pack.yaml` and the doc/lock edits are pure enumeration scrubs; no kit/engine logic is dropped under a pack and no pack-specific directive content is placed in `kit/`. The sweep *engine* (`.governance/sweep.py`, the workflow, the `lib.sh` attestation helpers) deliberately stays in the kit.
- PASS — check 2: No dependency points upward across a layer edge. The one substantive code change — the guard added to the relocated `layer-boundaries/check.sh` — keeps the directive *consuming* the kit-owned runtime `lib.sh` by relative source (`../../../../../lib.sh`) and calling `require_attestation` from it; the new `declare -F require_attestation` block is a downward-only presence check that skips cleanly when the kit runtime hasn't shipped the helper, exactly the consume-don't-reach-up relationship the model prescribes. No pack file reaches into `kit/` or `skill/` paths.
- PASS — check 3: New shared logic stays in the layer that owns it. The only genuinely new logic is the runtime guard, and it adds no shared helper to the pack — it gates on the kit-owned `require_attestation` rather than copying it. The shared sub-agent-attestation infra remains kit-owned and is sourced, not duplicated into the consumer pack.

Overall: PASS.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-461b8141-1ab-1781544133-1 | claude-code | 461b8141-1abc-4a09-aaf9-03940c8fe798 | #280 | claude-opus-4-8 | 6642 | 33068 | 30540 | 772 | 40482 | 0.2745 | 6642 | 33068 | 30540 | 772 | chore(architecture): unship the bundled architecture pack from v0, relocate its  |
| claude-code-0631ecc4-9c6-1781544300-1 | claude-code | 0631ecc4-9c60-46d7-9c06-61fc2c8a350e | #280 | claude-opus-4-8 | 44184 | 1590599 | 38130785 | 389631 | 2024414 | 38.9683 | 44184 | 1590599 | 38130785 | 389631 | chore(architecture): unship the bundled pack; relocate its directives to the loc |

# issue-218 — pack update: foundation/docs/commits → v0.2.1, audit → v0.3.0

Closes [#218](https://github.com/Duaility/governance-kit/issues/218).

Post-release Lane-1 catch-up. `.governance/` is re-pinned to the just-released
pack tags and the committed consumed tree is re-materialized from those pins by
the real `pack-apply` verb, so the repo stays an honest customer of the latest
releases.

## Checklist

- [x] Re-pin foundation, docs, commits to v0.2.1 in packs.lock
- [x] Re-pin audit to v0.3.0, adopting the receipt-homed accounting regime
- [x] Materialize the consumed tree from the new pins (config.conf → defaults.conf rename)
- [x] Preserve the standard preset — skip the new strict-only commits directives
- [x] Governance suite green

## What changed

- **Re-pin foundation, docs, commits to v0.2.1 in packs.lock**, and **re-pin
  audit to v0.3.0, adopting the receipt-homed accounting regime** (#201): each
  pack's `ref`/`sha`/`version` in `.governance/packs.lock` now points at the
  released `<pack>/vX.Y.Z` tag. `security` is unchanged — `v0.2.0` is still the
  latest security release.
- **Materialize the consumed tree from the new pins (config.conf → defaults.conf
  rename)**: `.governance/packs/governance-kit/{foundation,docs,commits,audit}/`
  is rewritten from the pinned tags via `packverb pack-apply add`. The conf
  artifact rename lands across every updated directive, and audit picks up the
  #201 receipt-homed accounting machinery (`lib/receipt_io.py`, `lib/report.py`,
  the receipt-writing `hooks/pre-commit.sh`).
- **Preserve the standard preset — skip the new strict-only commits directives**:
  the commits pack grew `no-orphan-todos` and `no-unjustified-suppressions` at
  v0.2.1, both `strict`-only. This repo tracks the `standard` preset, so the
  apply was run with `--decisions '{"no-orphan-todos":"skip",
  "no-unjustified-suppressions":"skip"}'` and the lock still lists only
  `commit-message-format` for the commits pack.

## Out of scope

- The `kit_ref` pin (`install.yaml`) still reads `kit/v0.4.0`; `kit_version` is
  already `0.6.0` and the runtime hooks are already 0.6.0-stamped, so no kit
  runtime files change here. Re-aligning the lagging `kit_ref` tag is a separate
  `governance update` concern.
- Migrating the historical `COSTS.md` / `STEERING.md` rows into per-issue
  receipts. Audit v0.3.0 treats those ledgers as sealed history it no longer
  reads; only commits going forward home their accounting in receipts.
- Adopting the two new strict-only commits directives — deferred with the
  `standard` preset.

## Decisions

- **Repinned via `pack-apply add <ref@newtag>`, not `pack update`.** The lock
  stores immutable `@<pack>/vX.Y.Z` tag refs, so a plain `pack update` re-resolves
  the same SHA and reports every pack `skip`. Bumping to a new tag is an `add`
  that upserts the existing pack id's pin — the established repin path for this
  repo's Lane-1 catch-up.
- **Used the in-tree (HEAD, kit 0.6.0) `packverb.py`, not the `kit_ref`-pinned
  v0.4.0 engine.** The v0.4.0 engine rejects the new packs (`always_install` on a
  concern pack was reserved to `governance-kit/core` before the namespace
  redesign). The repo's installed `kit_version` is already `0.6.0` and its hooks
  are 0.6.0-stamped, so the in-tree engine matches the live runtime and
  regenerated the hook dispatcher byte-identically.
- **Skipped the two new strict-only commits directives** to hold the `standard`
  preset, consistent with this repo's standing choice to keep `no-orphan-todos`
  out.

## Verification

Full governance suite green after staging the re-materialized tree:

```sh
git add -A
SKIP_GOVERNANCE= bash .governance/run.sh
# → ✓ governance: 21 directive(s) passed
```

Lock pins now point at the released tags:

```sh
uv run --with PyYAML python kit/assets/packs/lib/packverb.py \
  lock-list .governance/packs.lock --long
# audit       0.3.0  …@audit/v0.3.0
# commits     0.2.1  …@commits/v0.2.1
# docs        0.2.1  …@docs/v0.2.1
# foundation  0.2.1  …@foundation/v0.2.1
# security    0.2.0  …@security/v0.2.0
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-77475844-5a8-1781268983-1 | claude-code | 77475844-5a83-4502-b842-ac0d39c797b3 | #218 | claude-opus-4-8 | 27591 | 283122 | 8221647 | 137699 | 448412 | 9.4608 | chore(governance): pack update — consume latest concern-pack tags (#218) -m Re-p |

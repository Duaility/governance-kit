# issue-254 — managed-tree-integrity eval no longer hardcodes kit_version

Closes [#254](https://github.com/Duaility/governance-kit/issues/254).

## Checklist

- [x] Derive fixture `kit_version` from the `lib.sh` marker in `write_manifest`
- [x] Eval passes at the current kit version and survives a kit version bump

## What changed

- **Derive fixture `kit_version` from the `lib.sh` marker in `write_manifest`.**
  `packs/foundation/directives/managed-tree-integrity/evals/test.sh` built its
  fixture by copying the repo's real `.governance/lib.sh` (which carries the
  `kit-version=` marker) but paired it with a manifest hardcoding
  `kit_version: "0.7.2"`. A kit release re-stamps that marker, so a version bump
  (`0.7.2 → 0.8.0`) made the marker disagree with the hardcoded manifest, the
  directive's marker-vs-manifest check fired, and the `match` / `restored` /
  `re-added` PASS cases failed — reddening `tests.yml` on the release commit and
  blocking any kit release. The fix reads the marker into a `KIT_VER` variable
  and writes that into the manifest, so the fixture tracks whatever kit version
  the checkout is at. The `1b` fail case keeps its `9.9.9` impossible-version
  sentinel (it must disagree with the marker by construction).

## Out of scope

- The hooks/git-env fragility that makes `scripts/test.sh` eval fixtures
  misbehave when run *nested inside* a live agent-session commit — separate from
  this version-coupling bug and not triggered by CI.
- Any change to the `managed-tree-integrity` directive itself; this is an
  eval-only fix.

## Decisions

- **Derive from the marker rather than re-pin in `release.sh`.** `release.sh`
  already re-pins the `up-to-date-repo` eval fixture on a kit bump, so adding
  this fixture there was an option — but the eval writes its manifest through a
  `printf` heredoc, not a `version:`-line that `set_quoted_field` can patch, and
  coupling another fixture path into `release.sh` is more fragile than making the
  eval version-agnostic. Deriving from the marker is the eval's already-stated
  intent ("the marker's version").
- **Kept the `1b` `9.9.9` sentinel hardcoded.** That case deliberately needs a
  manifest version that *cannot* equal the real marker; a v0 kit will not reach
  `9.9.9`, so the sentinel stays correct.

## Verification

The eval passes at the current kit version and survives a kit version bump
(verified against the actual `0.8.0` release target by temporarily re-stamping
the asset marker):

```sh
# current version
bash packs/foundation/directives/managed-tree-integrity/evals/test.sh   # ✓ exit 0

# simulate the real release bump, then restore
sed -i.bak 's/kit-version=0.7.2/kit-version=0.8.0/' kit/assets/dot-governance/lib.sh
bash packs/foundation/directives/managed-tree-integrity/evals/test.sh   # ✓ exit 0
mv kit/assets/dot-governance/lib.sh.bak kit/assets/dot-governance/lib.sh
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-30ab4f9998f-1781367137-1 | 30ab4f99-98f9-43e2-a227-36c3af4f8431 | #254 | correction | classifier | Called dogfood story broken; asked to rethink approach from scratch | fix(governance): derive managed-tree-integrity eval kit_version from marker (#2… | 1 | 2026-06-12T04:20:52.507Z |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-30ab4f99-98f-1781367137-1 | claude-code | 30ab4f99-98f9-43e2-a227-36c3af4f8431 | #254 | claude-opus-4-8 | 34399 | 212495 | 1550766 | 46082 | 292976 | 3.4275 | 34399 | 212495 | 1550766 | 46082 | fix(governance): derive managed-tree-integrity eval kit_version from marker (#25 |

# issue-215 — pre-waive toolchain-config on kit release commits

Closes [#215](https://github.com/Duaility/governance-kit/issues/215).

## Checklist

- [x] release.sh writes a kit-axis-only `allow-toolchain-config` pre-waiver
- [x] Pack releases carry no toolchain waiver (conditional on AXIS == kit)

## What changed

A `kit` release re-stamps the `kit-version=` marker on the hook files
(`.githooks/*`) and the governance workflow
(`.github/workflows/governance.yml`). `toolchain-config-protection` guards those
paths and blocked the `chore(release)` commit. Earlier kit releases predate the
directive being active in the dogfood, so they never hit it.

- **release.sh writes a kit-axis-only `allow-toolchain-config` pre-waiver.** The
  hardcoded single `git commit` is now a `commit_args` array; the
  `allow-toolchain-config` `-m` is appended only when `AXIS == kit`. The re-stamp
  is a marker-only, no-behavior change, so pre-waiving it is sound.
- **Pack releases carry no toolchain waiver (conditional on AXIS == kit).** A
  pack release touches only `packs/<pack>/pack.yaml`, never toolchain config, so
  the waiver would be dangling there — the conditional keeps it off pack commits.

## Verification

```sh
# A real kit release now commits past toolchain-config-protection:
bash scripts/release.sh kit 0.6.0 --push    # (run as part of the release batch)
# A pack release commit body has no allow-toolchain-config line.
```

## Out of scope

- The two other release-commit pre-waivers (doc-integrity #214, the original
  message-format / issue-receipt pair) are unchanged.

## Decisions

- **Scope the waiver to the kit axis, not unconditional.** An unconditional
  waiver would sit unused on every pack release commit (which touches no
  toolchain config) — a dangling waiver a reviewer would rightly question.
  Gating on `AXIS == kit` keeps each release commit's waiver set honest: it
  carries exactly the waivers its own changeset needs.

# issue-156 — re-pin dogfood lock to core/v0.4.0 standard preset

Addresses [#156](https://github.com/Duaility/governance-kit/issues/156).

## Checklist

- [x] Re-pin core entry to `core/v0.4.0`
- [x] Add `doc-integrity` and `version-consistency` to the directive list
- [x] Rebuild consumed tree via `reconcile.sh`
- [x] All 17 directives green

## Problem

The dogfood `.governance/packs.lock` pinned `governance-kit/core` at the stale
`@main` / `ff76a2827` / `version: 0.3.2` with only **13** directives. The live
source pack (`packs/core/`) is **v0.4.0** and this repo is installed at the
`standard` preset, which gained two directives the repo was not enforcing on
itself:

- `version-consistency` — `install.yaml` `kit_version` must equal every
  managed-file `kit-version=` marker.
- `doc-integrity` — `always_install: true`; system-of-record docs are
  append-only (`.governance/integrity.conf` was already configured, and recent
  commits already carried `allow-doc-integrity` waivers, so the intent was
  always for it to run — it was simply never added to the lock).

`reconcile.sh` prunes the consumed tree down to the lock's explicit
`directives:` list, so the two new directives never materialised regardless of
the live working-tree content the resolver serves.

## What changed

- **Re-pin core entry to `core/v0.4.0`** — the `.governance/packs.lock` core
  entry moved from `@main` / `ff76a2827` / `0.3.2` to `@core/v0.4.0` /
  `e9d339cf` / `0.4.0`.
- **Add `doc-integrity` and `version-consistency` to the directive list** —
  extended from 13 to the full `standard` preset (15), alphabetically placed. No
  other fields changed.

## Out of scope

- `no-orphan-todos` — `strict`-only and `recommended: false`; not part of the
  `standard` preset this repo is installed at, so it stays out.
- Multi-PR-epic support — explicitly not a goal. The `doc-integrity`
  frozen-receipt vs `receipt-per-issue` tension only arises for an issue
  spanning multiple PRs; the canonical workflow is one issue → one PR → one
  receipt, frozen once on the trunk. No directive change is warranted.

## Decisions

- **Re-pinned to the `core/v0.4.0` tag, not `@main`.** Now that tagged releases
  exist, the dogfood consumes a pinned released version rather than tracking a
  moving branch — matching the tag-based pinning the new versioning flow
  prescribes for all consumers.
- **Matched the `standard` preset exactly.** Added only the two directives that
  `standard` gained (`doc-integrity`, `version-consistency`); deliberately did
  not pull in `strict`-only `no-orphan-todos`.
- **Hand-edited the lock + ran `reconcile.sh`** rather than the `governance pack
  update` verb. The edit is surgical and the working-tree resolver already
  serves live `packs/core` content; only the lock's `directives:` prune-list and
  pin fields needed changing, so the outcome is deterministic and fully
  inspected.

## Verification

- **Rebuild consumed tree via `reconcile.sh`** —
  `bash governance/assets/packs/lib/reconcile.sh "$(git rev-parse --show-toplevel)"`
  rebuilt it; `doc-integrity` and `version-consistency` now present under
  `.governance/packs/governance-kit/core/directives/`.
- `bash .governance/run.sh` → **all 17 directives green** (15 core standard + 2
  local), including the newly-activated `doc-integrity` and `version-consistency`.
- Markers and manifest already agree (`kit-version=0.3.5` everywhere,
  `install.yaml kit_version: 0.3.5`), so `version-consistency` passes; on `main`
  `doc-integrity` is a no-op (baseline falls back to HEAD), and on a feature
  branch it freezes only trunk receipts.

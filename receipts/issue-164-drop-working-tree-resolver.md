# issue-164 — delete the working-tree resolver; dogfood pack update via real fetch

Addresses [#164](https://github.com/Duaility/governance-kit/issues/164).

## Checklist

- [x] Delete the working-tree resolver and its test
- [x] Remove the resolver from packverb fetch_ref
- [x] Fix reconcile to fetch by sha (strip the ref rev)
- [x] Re-point the dogfood lock to @main
- [x] Validate a real network fetch

## Problem

The working-tree resolver (`working_tree.py`, #115) short-circuited
`packverb fetch` to read the live monorepo when a ref pointed at the repo you
were inside. Once the consumed tree became committed (#158) and reconcile left
CI (#162), the resolver worked *against* the goal of dogfooding `pack update`:
it bypassed the exact network-fetch path every consumer hits. Directive
correctness is covered by each directive's `evals/` (run by `scripts/test.sh`),
not the dogfood — so the dogfood should track a real fetch of the published
pack, like a consumer.

## What changed

- **Delete the working-tree resolver and its test** — removed
  `governance/assets/packs/lib/working_tree.py` and `scripts/test-working-tree.py`,
  and dropped the "working-tree resolver" layer (and its comment) from
  `scripts/test.sh`.
- **Remove the resolver from packverb fetch_ref** — dropped the
  `from working_tree import …` import, the resolver call/short-circuit, and the
  now-unused `_read_pack_id` helper from `packverb.py`; `fetch_ref` always does a
  real clone. (`_slugify_pack_id` / `PACK_ID_RE` stay — used by the clone path.)
- **Fix reconcile to fetch by sha (strip the ref rev)** — removing the resolver
  exposed a latent bug: `reconcile.sh` built `${ref}@${sha}`, and since the lock
  `ref` already carries `@<rev>` (e.g. `@main`) that produced a malformed
  `@main@<sha>` clone target. The resolver had masked it by ignoring the rev
  entirely. `reconcile.sh` now strips the trailing `@<rev>` (`base_ref="${ref%@*}"`)
  before appending the locked `@<sha>`, fetching the exact pinned commit.
- **Re-point the dogfood lock to @main** — `.governance/packs.lock` core ref
  `@core/v0.4.0` → `@main` and sha re-pinned to `origin/main` (`fd38a10`). With a
  real fetch, `ref` and `sha` are now internally consistent (both track the tip);
  the tag-pin only ever "worked" because the resolver ignored it.
- Updated the stale resolver references in `INIT_FLOW.md` and `RESET_FLOW.md`.

## Out of scope

- Relocating `packs/core` into `.governance` for a single home — the kit keeps
  its author-source / committed-consumer split (the split is what `pack update`
  bridges and dogfoods). Core stays `source: gh` so `pack update` keeps applying
  to it.

## Decisions

- **Kept core `source: gh`, only removed the resolver.** Marking core
  `source: local` would make `pack update` skip it (no dogfood of the verb).
  Removing just the resolver keeps `pack update` applicable *and* routes it
  through the real fetch path — the faithful dogfood.
- **Accepted that the dogfood tracks published core, not same-branch edits.**
  Adopting a new/tightened directive is now: land it in `packs/core` (evals gate
  it) → `pack update` vendors it → fix compliance. The atomic same-branch loop
  the resolver enabled is given up; evals cover in-development correctness.
- **Fixed the reconcile `@rev@sha` bug here** rather than deferring — it was
  latent (masked by the resolver) and removing the resolver makes it live for any
  gitignore-it consumer with a normal rev-ref, so it ships in the same change.

## Verification

- **Validate a real network fetch** —
  `packverb fetch gh:duaility/governance-kit/packs/core@main` cloned over the
  network (no resolver) and resolved to `origin/main` sha `fd38a10`.
- `bash governance/assets/packs/lib/reconcile.sh "$PWD"` then re-vendored from
  the pinned sha and produced a **byte-identical** committed tree
  (`git status` clean under `.governance/packs/governance-kit/`).
- `bash scripts/test.sh` → all kit-internal layers green (the working-tree layer
  is gone; `test-packverb` still covers `fetch_ref`'s clone path).
- `bash .governance/run.sh` → all 17 directives green.

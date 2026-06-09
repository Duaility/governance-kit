# issue-162 — drop reconcile from the kit's own CI and clone setup

Addresses [#162](https://github.com/Duaility/governance-kit/issues/162).

## Checklist

- [x] Remove the reconcile step (and Install uv) from governance.yml
- [x] Remove the reconcile block from enable-governance.sh
- [x] Suite stays green running the committed tree directly

## Problem

Since #158/#159 the kit commits its consumed `governance-kit/core` directive
tree (no longer gitignored/reconstructed). That left `reconcile.sh` redundant in
the kit's *own* loop: the committed tree is what should run, exactly like every
consumer. The shipped CI template and `enable-governance.sh` asset never call
reconcile; only the kit's own copies did — a leftover from the gitignore era.

## What changed

- **Remove the reconcile step (and Install uv) from governance.yml** —
  `.github/workflows/governance.yml` now runs `.governance/run.sh` over the
  committed tree directly. The "Reconcile gh-source packs" step and its
  only-needed-for-reconcile "Install uv" step are gone (no `check.sh` needs
  `uv`); the kit's CI now matches the shipped consumer template's shape.
- **Remove the reconcile block from enable-governance.sh** — dropped the
  trailing `reconcile.sh` invocation (and its stale "gitignored / reconstructable
  artifacts" comment) from `scripts/enable-governance.sh`; a fresh clone already
  has the committed tree.

`reconcile.sh` and the working-tree resolver are intentionally kept — still
shipped for the gitignore-it consumer pattern and used by `pack update`. The
deeper "delete the resolver / make core first-party" restructure is out of scope.

## Out of scope

- The working-tree resolver (`working_tree.py`), `reconcile.sh` itself, and the
  `packs/core` ↔ committed-tree duplication — the structural simplification was
  deliberately deferred; this is the leaf cleanup only.

## Decisions

- **Accepted that the dogfood now enforces the committed/pinned core, not
  bleeding-edge `packs/core`.** Editing a directive in `packs/core` requires a
  deliberate `governance pack update governance-kit/core` + commit to re-vendor
  before the dogfood picks it up — consistent with how consumers work, and the
  point of vendoring.
- **Removed `Install uv` alongside reconcile.** It was added solely for
  `reconcile.sh`'s `uv run --with PyYAML`; nothing in the `run.sh` path needs it.

## Verification

- **Suite stays green running the committed tree directly** — `bash
  .governance/run.sh` → all 17 directives pass with no reconcile step.
- `bash .governance/run.sh workflows-hardened` → green (the trimmed
  `governance.yml` still declares `permissions:` and pins its remaining action
  to a SHA).

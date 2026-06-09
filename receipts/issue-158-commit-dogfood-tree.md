# issue-158 — commit dogfood directive tree; align reconcile with install

Addresses [#158](https://github.com/Duaility/governance-kit/issues/158).

## Checklist

- [x] Align `reconcile.sh` with the install path
- [x] Remove the gitignore entry for the kit core tree
- [x] Commit the consumer-shaped core directive tree
- [x] Suite and tests green

## Problem

The kit treated its own first-party core pack as a gitignored, reconstructed
dependency — diverging from how every consumer stores directives:

1. `.gitignore` ignored `.governance/packs/governance-kit/` (from #117), so the
   directive code that enforces this repo was never committed or reviewable
   in-tree; a `governance pack update` showed only a SHA bump, not the `check.sh`
   diff. Consumers (e.g. [srikanth235/centraid](https://github.com/srikanth235/centraid))
   commit the directive code via `governance pack add`.
2. `reconcile.sh` and `install.sh` disagreed on what a consumed tree *is*.
   `install.sh` (the `pack add` path) copies directives only, stripping `evals/`
   and `install-assets/` ("author-side tests are never copied into target
   repos", install.sh:21). `reconcile.sh` did a raw `cp -R` that kept evals,
   install-assets, and a top-level `pack.yaml`. A reconciled tree ≠ an
   installed tree — centraid had no evals; the kit did.

## What changed

- **Align `reconcile.sh` with the install path** — it now sources `install.sh`
  and materializes each locked directive through `install_directive_folder`
  (→ `copy_tree_without_evals`), the same code `governance pack add` uses, in
  place of the raw subtree copy + prune. A reconciled tree is now
  byte-identical to a freshly-installed one: directives only, `evals/` and
  `install-assets/` stripped, no top-level `pack.yaml`. There is now one
  definition of a consumed pack tree.
- **Remove the gitignore entry for the kit core tree** — dropped
  `.governance/packs/governance-kit/` (and its #117 comment) from `.gitignore`.
- **Commit the consumer-shaped core directive tree** — the reconciled
  `standard`-preset core pack (15 directives, 61 files) is now tracked under
  `.governance/packs/governance-kit/core/directives/`, matching centraid's
  shape exactly.

## Out of scope

- The duplication between `packs/core/` (authoring source) and the committed
  consumed copy is accepted, per the chosen approach (commit + keep in sync via
  reconcile). The alternative — relocating `packs/core/` under `.governance/`
  as a single home — was deliberately not taken.
- `reconcile` stays the sync mechanism (CI keeps its reconcile step); this
  change only makes its output match the install path and commits the result.

## Decisions

- **Reused `install_directive_folder` rather than re-deriving the strip rules
  in `reconcile.sh`.** One canonical materializer means install and reconcile
  can never drift again on what a consumed tree contains.
- **Matched centraid's shape exactly** (directives only, no `pack.yaml`): the
  runner discovers directives by globbing `*/directives/*/check.sh` and nothing
  reads `pack.yaml`/evals from the consumed tree, so the leaner shape is
  sufficient and is what real consumers already carry.

## Verification

- `bash governance/assets/packs/lib/reconcile.sh "$(git rev-parse --show-toplevel)"`
  now emits a tree with `directives/` only — no `evals/`, no `pack.yaml`; 15
  directives; accounting directives keep their `hooks/`/`lib/`/`runtimes/`.
- The committed file set is clean — 61 files, no `__pycache__`/`.pyc`/evals.
- **Suite and tests green:** `bash .governance/run.sh` → all 17 directives pass;
  `bash scripts/test.sh` → all kit-internal layers pass (incl. `test-install-sh`
  exercising the shared `copy_tree_without_evals` path).

# issue-166 — delete orphaned reconcile.sh

Addresses [#166](https://github.com/Duaility/governance-kit/issues/166).

## Checklist

- [x] Delete reconcile.sh
- [x] Fix the stale references that name it
- [x] Suites green

## Problem

`reconcile.sh` ("rebuild expanded pack trees from packs.lock") was fully orphaned
after the committed-tree migration: zero invocations anywhere, no skill/flow doc
instructs it, no test covers it.

- #158 committed the consumed tree → nothing to rebuild on a fresh clone.
- #162 removed its only two callers (the kit's `governance.yml` +
  `enable-governance.sh`).
- `pack add` / `pack update` / `init` materialize via `install_directive_folder`
  directly — never through reconcile.

Its job is covered elsewhere: `pack add`/`pack update` materialize the tree, and
git restores it on a fresh clone or recovery (the tree is committed).

## What changed

- **Delete reconcile.sh** — removed `governance/assets/packs/lib/reconcile.sh`.
- **Fix the stale references that name it** — the "never edit a fetched tree,
  reconcile.sh will clobber it" warning in `DIRECTIVE_AMEND_FLOW.md` now points
  at the actual clobberer (`governance pack update` re-vendoring via
  `install_directive_folder`), and the `cmd_lock_read` comment in `packverb.py`
  no longer names reconcile as the consumer of its JSON.

## Out of scope

- A lock-only / gitignore-the-tree consumer mode (Go-default style) — nothing
  ships that wiring today, so deleting reconcile removes only latent, unused
  capability. The stance is now explicit: the consumed tree is always committed.
  reconcile is reconstructable from git history if that mode is ever wanted.

## Decisions

- **Deleted rather than kept as a utility.** Everything it did is covered by the
  pack verbs (materialize) plus git (recovery, since the tree is committed);
  keeping a 137-line script nothing runs is dead weight, and removing it makes
  the "always commit the enforcement code" stance explicit — on-brand for a
  trust tool.

## Verification

- No live references to `reconcile.sh` remain (`grep` across `*.sh`/`*.py`/`*.md`/
  `*.yml`, excluding frozen receipts/ledgers/plans → none).
- **Suites green:** `bash scripts/test.sh` → all kit-internal layers pass;
  `bash .governance/run.sh` → all 17 directives pass.

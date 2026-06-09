# issue-160 — README: kit + pack lifecycle and core ideas

Addresses [#160](https://github.com/Duaility/governance-kit/issues/160).

## Checklist

- [x] Complete the verb map
- [x] Add a Lifecycle section covering kit and pack install/update/uninstall
- [x] Fold the scattered Install and Community packs sections into Lifecycle
- [x] Internal doc links resolve

## What changed

- **Complete the verb map** — the `### Verbs` box now lists all six families:
  `init`, `kit update`, `pack {list,search,add,update,remove,create}`,
  `directive {add,modify,remove}`, `reset`, and `uninstall` (was missing
  `kit update`, `pack list/create`, and `reset`), with a pointer to Lifecycle.
- **Add a Lifecycle section covering kit and pack install/update/uninstall** —
  new `## Lifecycle` opens with the two-layer model (kit `kit/vX.Y.Z` vs packs
  `<pack>/vX.Y.Z`, the Helm `Chart.version`/`appVersion` split) and the
  lock-is-truth + vendored-and-committed directive-tree core idea (#158). Then
  **The kit** (npx-skills install + manual symlink, `governance init`; update via
  re-running npx + `governance kit update`; uninstall via
  `governance uninstall --dry-run|--soft|--hard` + removing the skill symlink)
  and **Packs** (`pack list/search/add/update/remove/create`, the core pack,
  tag-pinning, the vendor-and-commit note, community-pack authoring + catalog).
- **Fold the scattered Install and Community packs sections into Lifecycle** —
  removed the standalone `## Install` and `## Community packs` sections (their
  content now lives under Lifecycle), dropped the duplicated `[!IMPORTANT]`
  hand-edit caution down to one richer copy, and fixed the Quickstart's stale
  `see Install` cross-reference to `see Lifecycle`.

## Out of scope

- The pre-existing overlap between the `### Core pack` table (under How it ships)
  and the `## What's in core` tables is left as-is; deduping the directive
  catalog tables is a separate cleanup.
- Code simplification suggested by the same mental model is tracked separately
  (not a docs change).

## Decisions

- **Kept Quickstart's short install snippet and repeated the fuller install in
  Lifecycle.** Quickstart is the 30-second teaser; Lifecycle is the reference.
  The small duplication buys a clean reading order for each audience.

## Verification

- **Internal doc links resolve** — `bash .governance/run.sh
  no-broken-internal-doc-links` → green (the new VERSIONING.md /
  PACK_AUTHORING.md / catalog links resolve).
- `bash .governance/run.sh doc-freshness` → green.
- Section structure reviewed: `Why → Visibility → Quickstart → How it ships →
  Lifecycle → What's in core → Why not pre-commit → Contributing → License`.

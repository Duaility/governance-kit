# issue-198 — publish a thin installer skill, physically separate from the kit

Closes [#198](https://github.com/Duaility/governance-kit/issues/198).

**The skill is an installer. The kit is the product** — now materialized as the
repo layout, not just a routing convention. `npx skills` installs the entire
directory holding `SKILL.md` with no exclude mechanism, so the post-#194 skill
still shipped the whole 1.8M `governance/` tree (844K of it eval fixtures) to
every machine. The published skill is now `skill/` — **116K**: an installer doc
plus a fetch-only bootstrap. Everything else lives in `kit/` and reaches
machines only as released `kit/vX.Y.Z` trees, fetched and pinned per repo.

## Checklist

- [x] skill/ thin shim (SKILL.md + fetch-only bootstrap)
- [x] kit/ rename (governance/ → kit/, KIT_SUBPATH `kit`)
- [x] All lifecycle flows read from the kit tree
- [x] Offline refuse-with-guidance
- [x] build-skill.sh + skill-build-sync drift directive
- [x] release.sh integration
- [x] Path sweep + tests + dogfood green

## What changed

- **skill/ thin shim (SKILL.md + fetch-only bootstrap).** New top-level `skill/`
  is what `npx skills` detects and installs (`governance/SKILL.md` deleted, so
  discovery is unambiguous). `skill/SKILL.md` (hand-authored source) documents
  the three lifecycle verbs as *get a kit tree, then follow that tree's doc*,
  plus one delegate rule for every other verb (`kit-current` → the pinned kit's
  `VERBS.md`); it carries no pack/directive/reset content and no flow procedure.
  `skill/assets/` is derived: `kit.yaml` (version anchor) + six bootstrap
  modules (`kitverb`, `kitresolve`, `kitapply`, `packverb`, `packctl`,
  `applylib`) — resolve/fetch/cache/pin only, no apply engines, no bash
  helpers. Verified self-contained by running `kit-current` and full subparser
  registration from a copy outside the repo.
- **kit/ rename (governance/ → kit/, KIT_SUBPATH `kit`).** The kit artifact now
  reads like the mental model: `skill/` (installer) + `kit/` (product:
  engine lib, flow docs, templates, kit.yaml) + `packs/` (content).
  `build_kit_ref` now constructs `gh:<repo>/kit@kit/vX.Y.Z`. **Subpath epoch:**
  pre-split tags keep their tree at `governance/`, so `--to` a pre-split version
  fails the fetch with a clear error; repos already pinned to such tags keep
  working — the recorded `…/governance@…` ref stays valid and `kit-current`
  parses the subpath from the ref (documented in `VERSIONING.md`). The dogfood
  pin and pre-split eval fixtures intentionally keep the old-style ref.
- **All lifecycle flows read from the kit tree.** The skill ships zero reference
  docs. `install` follows the *fetched* kit's `references/INIT_FLOW.md`;
  `update` follows the fetched *target's* `references/UPDATE_FLOW.md` (the #177
  the-engine-that-writes-X-is-X's-engine contract, extended to docs);
  `uninstall` resolves the pinned kit via `kit-current` and follows its
  `references/UNINSTALL_FLOW.md`, running `uninstall-plan`/`uninstall-apply`
  from the resolved kit's lib.
- **Offline refuse-with-guidance.** With no reachable release and nothing
  cached (`provenance: installed-skill`), `install`, `update`, and `uninstall`
  refuse with connect-once guidance instead of assembling from (or tearing down
  with) the shim — it carries no templates, packs, or apply engines.
  `kit_provenance: installed-skill` stays in the `INSTALL_SCHEMA.md` enum solely
  as the audit trail of pre-#198 installs. `INIT_FLOW.md` Step 0,
  `UPDATE_FLOW.md`'s offline matrix row, and the init evals updated to match.
- **build-skill.sh + skill-build-sync drift directive.**
  `scripts/build-skill.sh` is the single assembler of the derived
  `skill/assets/` (regenerate-wholesale; `skill/SKILL.md` exempt). New
  repo-local dogfood directive `skill-build-sync`
  (`.governance/packs/duaility/governance-kit/directives/skill-build-sync/`)
  rebuilds into a temp dir and fails on any byte drift — companion
  CONSTITUTION.md subsection and Evolution Log entry land in this same commit
  (the cardinal rule). `kit-version-consistency` amended to compare
  `kit/assets/kit.yaml` against `skill/SKILL.md` frontmatter.
- **release.sh integration.** Kit releases now stamp `skill/SKILL.md`
  frontmatter (the deleted `governance/SKILL.md` line replaced), exclude
  `skill/assets/*` from marker discovery, and re-run `build-skill.sh` as the
  last apply step so the derived tree always carries the bumped version.
  Verified with `release.sh kit 0.6.0 --dry-run`.
- **Path sweep + tests + dogfood green.** 79 files swept
  `governance/{assets,references,evals}` → `kit/…` and `/governance@kit/v` →
  `/kit@kit/v` (immutable `receipts/`, `plans/`, CHANGELOG entries, frozen
  CONSTITUTION.md Evolution Log lines, and the historical dogfood/fixture pins
  excluded; CHANGELOG's live preamble links updated). The kit's reference docs
  no longer link `../SKILL.md` (a fetched kit has no skill alongside it) — those
  became plain-text mentions. Eval 7 of `kit-update` retargeted from the
  pre-split `0.4.0` to `0.6.0` with the `kit@` ref form. SKILL.md frontmatter
  re-verified with gray-matter (guarding the #196 colon-space regression class).

## Out of scope

- **Re-pinning the dogfood lock / cutting the first kit-layout release.** The
  repo stays pinned to `kit/v0.4.0` (old-subpath tree, still resolvable); the
  first `kit/vX.Y.Z` cut after this merge is the first tag with the `kit/`
  subpath. Post-merge runtime action, per the release flow.
- **A back-compat dual-subpath fetch** (try `kit@`, fall back to
  `governance@`). V0 stance: the epoch boundary is documented instead.
- **Deprecating `npx skills` distribution** or changing pack semantics / the
  two-axis versioning scheme — non-goals of the issue.

## Decisions

- **Fetch-only shim; uninstall delegates too.** The rustup test: the installer
  carries just enough to download and verify, never the product's engines. The
  tradeoff — tear-down with a cold cache while offline refuses (connect once)
  instead of working unconditionally — was accepted explicitly in review.
- **Rename `governance/` → `kit/` rather than documenting around it.** The
  directory name was the last residue of the fat-skill era and kept the
  skill-vs-kit boundary ambiguous. V0 allows the churn; ~80 files were
  mechanical path updates.
- **The shim ships no flow docs, not even lifecycle ones.** Earlier iterations
  vendored six lifecycle reference docs; review judged that *how to assemble a
  repo from the kit is kit knowledge* — the shim only knows how to get a tree
  and which doc inside it to follow. This also erased the need for doc-link
  exclusions for vendored copies.
- **skill/ is a committed derived artifact, not built-on-publish.** Same
  contract as the consumed pack trees: lock/source is truth, the derived tree is
  reconstructable, and a directive (not a human) guards the sync.

## Verification

```sh
bash .governance/run.sh        # ✓ all 19 directives passed (incl. new skill-build-sync)
bash scripts/test.sh           # ✓ all kit-internal test layers passed
bash scripts/build-skill.sh    # ✓ deterministic; re-run produces zero diff
bash scripts/release.sh kit 0.6.0 --dry-run   # ✓ stamps skill/SKILL.md, reassembles skill/assets
```

- Shim self-containment: copied `skill/` to a temp dir outside the repo;
  `kitverb.py --help` registers every subcommand (exercising the full import
  closure) and `kit-current --offline` returns the installed-skill fallback with
  the vendored `kit.yaml` version — no `ImportError`, no repo dependency.
- Footprint: `du -sh skill` = **116K** vs 1.8M for the pre-split published tree.
- `skill/SKILL.md` frontmatter parses under gray-matter 4.0.3 (the `npx skills`
  discovery path).

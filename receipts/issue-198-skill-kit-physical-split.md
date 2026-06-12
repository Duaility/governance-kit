# issue-198 — publish a thin installer skill, physically separate from the kit

Closes [#198](https://github.com/Duaility/governance-kit/issues/198).

**The skill is an installer. The kit is the product** — now materialized as the
repo layout, not just a routing convention. `npx skills` installs the entire
directory holding `SKILL.md` with no exclude mechanism, so the post-#194 skill
still shipped the whole 1.8M `governance/` tree (844K of it eval fixtures) to
every machine. The published skill is now `skill/` — **two hand-authored
files**: an installer doc and a stdlib-only fetch script. Everything else lives
in `kit/` and reaches machines only as released `kit/vX.Y.Z` trees, fetched and
pinned per repo. The dogfood repo resolves its own pin through the exact same
downstream-consumer path — no special case.

## Checklist

- [x] skill/ = SKILL.md + bootstrap.py, all source
- [x] kit/ rename (governance/ → kit/, KIT_SUBPATH `kit`)
- [x] All lifecycle flows read from fetched kit trees
- [x] Offline refuse-with-guidance
- [x] Version axes decoupled
- [x] scripts/test-bootstrap.py locks the cache contract
- [x] Per-directive deep-dives relocated out of kit/references
- [x] Path sweep + tests + dogfood green

## What changed

- **skill/ = SKILL.md + bootstrap.py, all source.** New top-level `skill/` is
  what `npx skills` detects and installs (`governance/SKILL.md` deleted, so
  discovery is unambiguous). `skill/SKILL.md` documents the three lifecycle
  verbs as *get a kit tree, then follow that tree's doc*, plus one delegate
  rule for every other verb. `skill/bootstrap.py` is a single stdlib-only
  python3 script with two subcommands: `resolve` (latest published `kit/vX.Y.Z`
  tag or `--to`; offline `--to` is served by a content scan of the cache) and
  `current` (the repo's recorded `kit_ref`/`kit_sha` pin). Both fetch into the
  shared `~/.governance/cache/kits/<owner>__<repo>@<sha>/` layout and report
  `kit_dir`/`lib_dir`/`references_dir`/`assets_dir` as JSON — or `result:
  refused` with recovery guidance. The shim carries **no kit content**: no
  `kit.yaml` version anchor, no engine modules, no flow docs. An earlier
  review iteration vendored six kit lib modules behind a `build-skill.sh` +
  `skill-build-sync` drift directive; review killed it — the shim had
  inherited `packverb`/`packctl`/`applylib` through import-graph gravity, and
  the bundled `kit.yaml` existed only to feed `packctl`'s eager `KIT_VERSION`.
  With nothing derived there is no build step and no drift surface.
- **kit/ rename (governance/ → kit/, KIT_SUBPATH `kit`).** The kit artifact now
  reads like the mental model: `skill/` (installer) + `kit/` (product:
  engine lib, flow docs, templates, kit.yaml) + `packs/` (content).
  `build_kit_ref` now constructs `gh:<repo>/kit@kit/vX.Y.Z`. **Subpath epoch:**
  pre-split tags keep their tree at `governance/`, so `resolve --to` a
  pre-split version refuses at fetch validation with a clear
  no-`assets/kit.yaml` error; repos already pinned to such tags keep working —
  the recorded `…/governance@…` ref stays valid and `bootstrap.py current`
  parses the subpath from the ref (documented in `VERSIONING.md`). This repo's
  own `kit/v0.4.0` pin resolves through that path today.
- **All lifecycle flows read from fetched kit trees.** The skill ships zero
  reference docs and zero engines. `install`: `bootstrap.py resolve` → the
  fetched kit's `references/INIT_FLOW.md`, engines from `<lib_dir>`. `update`:
  `bootstrap.py current` → the *pinned* kit's `references/UPDATE_FLOW.md`
  (rustup model — the version you have performs the move); its Step 1 runs
  `kit-resolve` from `<lib_dir>`, which fetches the target, gates
  floor/direction, and delegates apply to the fetched *target's* own engine on
  forward/same (#177) and keeps downgrades driven by the newer pinned engine.
  `uninstall`: `bootstrap.py current` (falling back to `resolve` when
  unpinned) → that tree's `references/UNINSTALL_FLOW.md` and
  `uninstall-plan`/`uninstall-apply` engines. All version gates live in the
  kit's `kit-resolve`; the shim's only validation is structural (a delegable
  tree must carry `assets/kit.yaml`, an engine lib, and `references/`).
- **Offline refuse-with-guidance.** With no reachable release and nothing
  cached, `bootstrap.py` reports `result: refused` + `recovery` (connect once;
  the fetch is cached, so later runs are network-free) for all verbs — never a
  partial tree, never a shim-sourced fallback; there is nothing to fall back
  to. `kit_provenance: installed-skill` stays in the `INSTALL_SCHEMA.md` enum
  solely as the audit trail of pre-#198 installs; new installs record
  `published-tag` / `explicit` / `cache`.
- **Version axes decoupled.** The skill's frontmatter `version` is the
  installer's own, bumped by hand when the shim changes. The
  `kit-version-consistency` dogfood directive drops the
  `kit.yaml`-equals-`SKILL.md` equality (keeping the kit-version-present and
  pack-floor invariants), and `scripts/release.sh` kit releases no longer
  stamp `skill/SKILL.md` (header, dry-run plan, and apply step updated;
  verified with `release.sh kit 0.6.0 --dry-run`).
- **scripts/test-bootstrap.py locks the cache contract.** 15 network-free
  tests (wired into `scripts/test.sh`): ref/scalar/pin parsing, structural
  validation refusals, `current`/`resolve` CLI happy and refusal paths for
  both subpath epochs, the real clone→sha→validate→cache-move path against a
  local upstream, and the cross-codebase assertion that a tree the shim caches
  is found by the kit engines' `cached_kit_path` (and vice versa) — the one
  piece of shared knowledge between the two codebases.
- **Path sweep + tests + dogfood green.** ~80 files swept
  `governance/{assets,references,evals}` → `kit/…` and `/governance@kit/v` →
  `/kit@kit/v` (immutable `receipts/`, `plans/`, CHANGELOG entries, frozen
  CONSTITUTION.md Evolution Log lines, and the historical dogfood/fixture pins
  excluded; CHANGELOG's live preamble links updated). The kit's reference docs
  no longer link `../SKILL.md` (a fetched kit has no skill alongside it) and
  the routed-verb preambles route through `bootstrap.py current`, refusing —
  not degrading to a machine copy — when unpinned/offline-uncached. Eval 7 of
  `kit-update` retargeted from the pre-split `0.4.0` to `0.6.0` with the
  `kit@` ref form; eval 11's version-skew case rewritten (the shim has no kit
  version to be "stuck on"). SKILL.md frontmatter re-verified with gray-matter
  (guarding the #196 colon-space regression class).

- **Per-directive deep-dives relocated out of kit/references.** Same-spirit
  `kit/references/` cleanup: `AGENT_TOKEN_ACCOUNTING.md` and
  `AGENT_STEERING_ACCOUNTING.md` were the only 2 of 19 directives with a
  write-up in the kit's shared flow-doc tree — an asymmetry, and the
  consumer-facing `COSTS.template.md` linked one at a `kit/references/…` path
  that exists in no installed repo (consumers receive only `.governance/`).
  Both move into their directive folders as `README.md`
  (`packs/audit/directives/<id>/README.md` + the dual-edited consumed tree),
  so the deep-dive ships and travels with the directive like its
  `lib/`/`hooks/`/`runtimes/` already do. The redundant kit-side pointers
  (`DIRECTIVES_CATALOG.md` rows, an `INIT_FLOW.md` further-reading bullet) are
  dropped — the README is discoverable beside `check.sh`; `COSTS.template.md`
  repoints to the consumer-resolvable directive path; the six install-note
  pointers (both `constitution.md`s, both consumed copies, both root
  subsections) are de-staled and standardized (one had read
  `governance-bootstrap/references/…`); stale `governance-kit/core` pack ids
  inside the docs corrected to `audit`.

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
- **Nothing derived in skill/; no build step.** Review rejected the
  vendored-bundle iteration (`build-skill.sh` + `skill-build-sync` directive +
  six copied modules + a `kit.yaml` anchor): it rebuilt a fat path and made
  the dogfood a special case. The shim's own ~300-line bootstrap duplicates
  only the ref-parse/cache-layout contract, and `scripts/test-bootstrap.py`
  pins that contract against the kit engines so the two sides cannot drift.
- **Rename `governance/` → `kit/` rather than documenting around it.** The
  directory name was the last residue of the fat-skill era and kept the
  skill-vs-kit boundary ambiguous. V0 allows the churn; ~80 files were
  mechanical path updates.
- **The shim ships no flow docs, not even lifecycle ones.** *How to assemble a
  repo from the kit is kit knowledge* — the shim only knows how to get a tree
  and which doc inside it to follow.
- **`update` orchestrates from the pinned tree.** The version you have
  performs the move (rustup/apt): the pinned kit's `UPDATE_FLOW.md` +
  `kit-resolve` gate the target and delegate apply to the target's own engine
  — preserving both #177 contracts (target engine writes forward moves; the
  newer engine drives downgrades) without any engine carried by the shim.

## Verification

```sh
bash .governance/run.sh        # ✓ all 18 directives passed
bash scripts/test.sh           # ✓ all kit-internal test layers passed (incl. new test-bootstrap.py)
bash scripts/release.sh kit 0.6.0 --dry-run   # ✓ no skill/ stamping, no build step
python3 skill/bootstrap.py current "$(git rev-parse --show-toplevel)" --offline
                               # ✓ resolves this repo's real pre-split pin from the shared cache
```

- Shim self-containment: `test_bootstrap_is_stdlib_only_and_standalone` copies
  `bootstrap.py` alone to a temp dir and runs it on bare `python3` — no
  PyYAML, no repo, no kit modules.
- `skill/SKILL.md` frontmatter parses under gray-matter 4.0.3 (the `npx
  skills` discovery path).

# issue-194 — slim the governance skill to kit lifecycle only

Closes [#194](https://github.com/Duaility/governance-kit/issues/194).

**The skill is an installer. The kit is the product.** The `governance` skill now
keeps three first-class lifecycle verbs (`install`, `update`, `uninstall`) and is
a thin **router** for everything else — `pack *`, `directive *`, `reset` execute
from the kit version each repo pins in `install.yaml`, fetched into
`~/.governance/cache/kits/`, not from the machine copy `npx skills` installed.

## Checklist

- [x] M1 — tag-resolved install
- [x] M2 — kit-current resolver
- [x] M3 — slim SKILL.md to installer + router
- [x] Verb rename
- [x] Routed flow docs
- [x] Tests

## What changed

- **M2 — kit-current resolver** (the verb-routing primitive). Added
  `kit-current <root> [--offline]` to `governance/assets/packs/lib/kitresolve.py`
  (registered in `kitverb.py`). It reads the repo's `kit_ref`/`kit_sha` from
  `install.yaml`, returns the cached pinned tree's `lib_dir` / `references_dir` /
  `assets_dir` (fetching it once into the `kits/` cache when absent), and degrades
  to the installed skill when there is no recorded pin or the pinned tree is
  uncached and unreachable. Distinct from `kit-resolve` (which selects a *new*
  target and gates floor + direction); `kit-current` resolves the *existing* pin
  verbatim, no gates. Writes nothing.
- **M1 — tag-resolved install** + provenance. `INIT_FLOW.md` gains **Step 0 —
  Resolve and fetch the kit to install from**: `install` runs `kit-resolve` from
  the installed skill, fetches the latest published `kit/vX.Y.Z` tag (or `--to`),
  and runs every assembly engine (`packs.sh` discovery, `packverb init-apply`,
  pack `fetch`) from the **fetched** kit's `<lib_dir>` / `<assets_dir>` — the
  released artifact, not main HEAD, reaches repo state. The flow threads the
  resolved `kit_ref` / `kit_sha` / `kit_provenance` into the `decisions` object. A
  new optional `kit_provenance` field (`published-tag` / `explicit` /
  `installed-skill`) records how the install resolved its kit; added to
  `write_installed_manifest` (`install.sh`, emitted only when supplied) and
  threaded by `initapply._write_manifest`. Documented in `INSTALL_SCHEMA.md`.
  Offline → installed-skill fallback, provenance recorded.
- **M3 — slim SKILL.md to installer + router.** Rewrote `governance/SKILL.md`: the
  three lifecycle verbs (`install`/`update`/`uninstall`) are documented inline;
  `pack *` / `directive *` / `reset` move under a **Routed verbs** section with a
  normative **Step R — Resolve the pinned kit** (`kit-current`) that tells the
  agent to run those verbs from the resolved kit's `<lib_dir>` + `<references_dir>`.
  The verb-dispatch table classifies each verb lifecycle-vs-routed.
- **Verb rename.** User-facing `init` → `install` and `kit update` → `update`
  (both keep their old names as recognized aliases; the internal engine
  subcommands keep their `init-*` / `kit-*` names to avoid CLI/test churn).
  Reflected in `INIT_FLOW.md`, `UPDATE_FLOW.md`, `VERBS.md`, and `AGENTS.md`.
- **Routed flow docs** (`RESET_FLOW.md`, `PACK_VERBS.md`, `DIRECTIVE_AMEND_FLOW.md`,
  `DIRECTIVE_VERBS.md`) each gained a "Routed verb — runs from the repo-pinned
  kit" note pointing at SKILL.md's Step R and re-anchoring their engine/template
  paths to `<lib_dir>` / `<assets_dir>`. `last-verified` bumped on the two docs
  that carry the marker.
- **Tests.** `test-kitresolve.py` gains 3 `kit-current` cases (cache hit returns
  the pinned tree; no-pin and offline-uncached fall back to the installed skill).
  `test-init.py` gains a provenance round-trip (`kit_provenance` in decisions →
  manifest; absent by default). `governance/evals/init/evals.json` updated for
  Step 0 + the `kit_provenance` assertion.

## Out of scope

- **Physically deleting `references/` + `assets/` from the machine skill.** In
  this monorepo `governance/` is *both* the installed skill and the tagged kit
  artifact, so the files cannot relocate to a separate directory (see Decisions).
- **Renaming the engine subcommands** (`init-plan`/`init-apply`, `kit-resolve`/
  `kit-plan`/`kit-apply`) or the reference filenames (`INIT_FLOW.md`,
  `UPDATE_FLOW.md`). Kept stable to avoid CLI/test churn and `internal-doc-links`
  breakage; only the user-facing verb names changed.
- **Deprecating `npx skills` distribution** and changing pack semantics or the
  two-axis versioning scheme — all stated non-goals of the issue.
- **Re-pinning the dogfood lock** to a kit that ships `kit-current`. The dogfood
  repo stays pinned to `kit/v0.4.0`; its routed verbs would resolve that (older)
  kit until a release ships this change and the lock is re-pinned — the intended
  repo-pinned behavior, not a gap.

## Decisions

- **One source tree, two roles → realize the split at consumption time.**
  `governance/` is both the installed skill and the kit artifact, so "move
  flows/assets into the kit artifact" cannot be a physical directory move. Instead
  the slimmed SKILL.md documents only lifecycle inline and routes non-lifecycle
  verbs to the *pinned kit's* `references/` + `assets/` via `kit-current`, so the
  machine working copy stops being authority for those verbs. That routing — not a
  file relocation — is what closes the `npx-skills-tracks-main` skew.
- **Reuse `kit-resolve` for install rather than a new install-resolver.** Milestone
  1 generalizes the #177 delegation; `kit-resolve` already resolves+fetches the
  latest tag and (on a fresh repo with no pin) classifies `direction: unknown`
  with no downgrade gate, so install reuses it and only the flow doc + provenance
  field are new.
- **Keep `init`/`kit update` as aliases and keep internal engine names.** V0 has no
  back-compat promise, but renaming the `init-*`/`kit-*` CLI subcommands and the
  `INIT_FLOW.md`/`UPDATE_FLOW.md` filenames would churn tests and every internal
  doc link for no behavioral gain; only the user-facing verb names changed.

## Verification

```sh
bash .governance/run.sh        # ✓ all 18 directives passed
bash scripts/test.sh           # ✓ all kit-internal test layers passed
```

- `bash scripts/test.sh` green across every layer: `test-packctl`,
  `test-packctl-validate`, `test-packverb`, `test-kitverb`, `test-kitresolve`
  (+3 new `kit-current` cases), `test-packverb-apply`, `test-reset-uninstall`,
  `test-init` (+1 provenance case), `test-install-sh`, `test-hooks-sh`,
  `test-runtime`, `test-schema-split`, and `test-packs` (5 packs / 19 directives /
  19 evals).
- `kit-current` smoke against this repo: cache miss → online fetch resolves the
  pinned `kit/v0.4.0` tree (version 0.4.0); the second call is a cache hit;
  `--offline` with an uncached pin falls back to the installed skill with the
  assumption noted.
- Evolution Log: not amended — this PR changes the skill/kit architecture, not the
  directive set, so there is no constitution directive to log.

---
name: governance
description: Installer and lifecycle entry point for governance-kit — `governance install` (bootstrap a repo from the released kit), `governance update` (re-pin/re-sync to a published kit version), `governance uninstall` (clean tear-down). Every other governance request is delegated to the kit version the repo pins in `install.yaml`, fetched at run time — `governance pack {search,create,add,update,remove,list}`, `governance directive {add,modify,remove}`, `governance reset`. Use when the user says "governance install", "governance init", "set up governance", "bootstrap governance", "governance uninstall", "tear down governance", "update governance-kit", "pull new kit version", "kit update", "governance reset", "reset directives", "restore to original", "undo my amendments", "install a pack", "add pack X", "create a pack", "scaffold a pack", "update packs", "remove pack X", "list installed packs", "add a directive", "amend the constitution", "new directive", "modify directive X", "remove directive X", or otherwise asks to manage governance-kit lifecycle, packs, or directives.
license: MIT
compatibility: Designed for Claude Code and Codex; requires git and bash.
metadata:
  author: governance-kit
  version: "0.5.0"
---

# governance

**The skill is an installer. The kit is the product.** Same contract as
rustup/toolchain or nvm/node (issues [#194](https://github.com/Duaility/governance-kit/issues/194),
[#198](https://github.com/Duaility/governance-kit/issues/198)).

This skill is a **thin shim**: this `SKILL.md` plus a fetch-only bootstrap
(resolve, fetch, cache, pin — nothing that applies). Its only responsibility is
moving a repo between kit versions: **`install`**, **`update`**, **`uninstall`**.
The **kit** (released as `kit/vX.Y.Z`, fetched into `~/.governance/cache/kits/`,
pinned per repo in `.governance/install.yaml`) owns everything: the rules,
packs, templates, every engine that writes files, every flow doc — including
the lifecycle flows themselves — and every other verb.

So every verb here is the same two moves: **get a kit tree, then follow that
tree's doc.** The shim never carries procedure of its own.

> **`<skill_dir>`** below is the directory holding this `SKILL.md` — wherever
> `npx skills` installed the skill. The bootstrap engine is
> `<skill_dir>/assets/packs/lib/`. Engine calls run as:
> `uv run --quiet --isolated --with PyYAML python <skill_dir>/assets/packs/lib/kitverb.py <subcommand> …`

## Which path?

1. **`install` / `update` / `uninstall`** → the three sections below.
2. **Anything else** — `pack *`, `directive *`, `reset`, or any other governance
   request → [delegate to the pinned kit](#delegate-everything-else-to-the-pinned-kit). Do not answer it from this skill.

Two disambiguations:
- **uninstall vs reset:** "remove governance entirely" → `uninstall`. "restore the rules to their pinned version" → `reset` (delegate).
- **update vs pack update:** "new kit-runtime files (`run.sh`, hook dispatcher)" → `update`. "new directive content from a pack" → `pack update` (delegate). Both → `update --with-packs`.

## `governance install` — bootstrap a repo from the released kit

1. Requires a git repo (else stop). If governance is already installed and the
   user asked a question or one targeted change, don't bootstrap — answer or
   delegate.
2. Run `kitverb.py kit-resolve "<root>" [--to X.Y.Z]` (engine call above). It
   resolves the latest published `kit/vX.Y.Z` tag (or `--to`), fetches that tree
   into the cache, and reports `kit_dir` / `hooks_lib` / `assets_root` /
   `kit_ref` / `kit_sha` / `provenance`.
3. **If `provenance` is `installed-skill`** (offline and nothing cached): the
   shim has no kit to assemble from — **refuse with guidance** (connect once to
   fetch the release, or `--to` a version already in the cache). Never write a
   partial tree.
4. Otherwise follow **`<kit_dir>/references/INIT_FLOW.md`** — the fetched kit's
   own install flow — running its engines from the fetched tree. The released
   artifact reaches repo state; this shim never does.

## `governance update` — move the repo to a published kit version

1. Run `kitverb.py kit-resolve "<root>" [--to X.Y.Z] [--offline]`. It gates
   direction/floor against the repo's recorded pin and names the engine to
   delegate to.
2. Follow **`<kit_dir>/references/UPDATE_FLOW.md`** — the fetched *target's* own
   update flow (the engine that writes version X's files is version X's engine,
   issue #177). The flow ends by recording the new `kit_ref`/`kit_sha` pin.

## `governance uninstall` — clean tear-down

1. Locate the repo's pinned kit: `kitverb.py kit-current "<root>" [--offline]`.
2. Follow **`<kit_dir>/references/UNINSTALL_FLOW.md`**, running its
   `uninstall-plan` / `uninstall-apply` engines from the resolved kit's
   `<lib_dir>`.
3. **If `provenance` is `installed-skill`** (no pin, or offline + uncached): the
   shim carries no uninstall engine — refuse with guidance (connect once; the
   fetched tree is cached, so the retry and any later uninstall are
   network-free).

# Delegate everything else to the pinned kit

`pack *`, `directive *`, `reset`, and any other governance request are **not
documented here** — they live in the kit. Resolve the kit the repo pins:

```sh
uv run --quiet --isolated --with PyYAML python \
    <skill_dir>/assets/packs/lib/kitverb.py kit-current "<root>" [--offline]
```

`kit-current` reads `kit_ref`/`kit_sha` from `install.yaml` and returns (as
JSON) the pinned kit's `kit_dir` / `lib_dir` / `references_dir` / `assets_dir`,
fetching it once into the cache when absent. Then:

1. Open **`<references_dir>/VERBS.md`** in the resolved kit and follow it — that
   doc owns the dispatch for every non-lifecycle verb and names the engine (in
   `<lib_dir>`) and flow doc (in `<references_dir>`) to run.
2. If `provenance` is `installed-skill` (no recorded pin, or offline + uncached),
   the kit's docs are **not** on the machine. Say so, and tell the user to run
   `governance update` (online once) to record/refresh the pin and populate the
   cache.

## Rules

- **Never hand-execute file operations.** Every mutating verb runs a tested
  plan/apply engine from a fetched or pinned kit tree. No ad-hoc `cp` / `rm` /
  marker stamping / manifest edits.
- **Don't grow this shim.** Anything beyond resolve-fetch-delegate belongs in
  the kit. If procedure seems missing here, it lives in the kit's docs.
- **No network at commit time.** Fetching happens only inside user-invoked
  verbs; commit hooks never reach the network.

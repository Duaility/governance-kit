---
name: governance
description: Installer and lifecycle entry point for governance-kit — `governance install` (bootstrap a repo from the released kit), `governance update` (re-pin/re-sync to a published kit version), `governance uninstall` (clean tear-down). Every other governance request is delegated to the kit version the repo pins in `install.yaml`, fetched at run time — `governance pack {search,create,add,update,remove,list}`, `governance directive {add,modify,remove}`, `governance workflow generate` for cron schedules, or `governance reset`. Use when the user says "governance install", "governance init", "set up governance", "bootstrap governance", "governance uninstall", "tear down governance", "update governance-kit", "pull new kit version", "kit update", "governance reset", "reset directives", "restore to original", "undo my amendments", "install a pack", "add pack X", "create a pack", "scaffold a pack", "update packs", "remove pack X", "list installed packs", "add a directive", "amend the constitution", "new directive", "modify directive X", "remove directive X", "generate the governance workflow", "configure a schedule", or otherwise asks to manage governance-kit lifecycle, packs, directives, or scheduled triggers.
license: MIT
compatibility: Designed for Claude Code and Codex; requires git, bash, and python3.
metadata:
  author: governance-kit
  version: "0.5.0"
---

# governance

**The skill is an installer. The kit is the product.** Same contract as
rustup/toolchain or nvm/node (issues [#194](https://github.com/Duaility/governance-kit/issues/194),
[#198](https://github.com/Duaility/governance-kit/issues/198)).

This skill is a **thin shim**: this `SKILL.md` plus one stdlib-only script,
`bootstrap.py`, that knows how to *get a kit tree* — resolve a published
`kit/vX.Y.Z` release (or the repo's recorded pin), fetch it once into
`~/.governance/cache/kits/`, and report its paths. It carries **no kit
content**: no version anchor, no engines, no templates, no flow docs. The
**kit** (pinned per repo in `.governance/install.yaml`) owns everything — the
rules, packs, templates, every engine that writes files, every version gate,
every flow doc including the lifecycle flows themselves, and every other verb.

So every verb here is the same two moves: **get a kit tree, then follow that
tree's doc.** The shim never carries procedure of its own. This skill versions
independently of the kit — its frontmatter `version` is the installer's, not
the kit's.

> **`<skill_dir>`** below is the directory holding this `SKILL.md` — wherever
> `npx skills` installed the skill. Bootstrap calls run as:
> `python3 <skill_dir>/bootstrap.py <resolve|current> …`
> Each prints JSON: on `result: ok`, consume `kit_dir` / `lib_dir` /
> `references_dir` / `assets_dir` / `version` / `kit_ref` / `kit_sha`; on
> `result: refused`, surface `reason` + `recovery` to the user and stop —
> never improvise a fallback.

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
2. Run `python3 <skill_dir>/bootstrap.py resolve [--to X.Y.Z]`. It resolves the
   latest published `kit/vX.Y.Z` tag (or `--to`), fetches that tree into the
   cache, and reports its paths. Offline with nothing cached → `refused` with
   connect-once guidance; the shim has nothing to assemble from, so **never
   write a partial tree**.
3. Follow **`<kit_dir>/references/INIT_FLOW.md`** — the fetched kit's own
   install flow — running its engines from `<lib_dir>`. The released artifact
   reaches repo state; this shim never does.

## `governance update` — move the repo to a published kit version

1. Get the tree to orchestrate from: `python3 <skill_dir>/bootstrap.py current
   "<root>" [--offline]` — the repo's *pinned* kit performs its own move
   (rustup model). On `refused` because no pin is recorded, run
   `bootstrap.py resolve [--to X.Y.Z]` instead and orchestrate from the target.
2. Follow that tree's **`<kit_dir>/references/UPDATE_FLOW.md`**. Its first step
   runs `kit-resolve` from `<lib_dir>`, which resolves and fetches the target,
   gates direction/floor against the recorded pin, and names the engine —
   forward/same updates delegate apply to the fetched *target's* own engine
   (the engine that writes version X's files is version X's engine, issue
   #177). The flow ends by recording the new `kit_ref`/`kit_sha` pin.

## `governance uninstall` — clean tear-down

1. Locate the repo's pinned kit: `python3 <skill_dir>/bootstrap.py current
   "<root>" [--offline]`. On `refused` with no recorded pin but network
   available, fall back to `bootstrap.py resolve` (tear down with the latest
   released engines); offline + uncached → surface the refusal — the shim
   carries no uninstall engine.
2. Follow **`<kit_dir>/references/UNINSTALL_FLOW.md`**, running its
   `uninstall-plan` / `uninstall-apply` engines from `<lib_dir>`.

# Delegate everything else to the pinned kit

`pack *`, `directive *`, `reset`, and any other governance request are **not
documented here** — they live in the kit. Resolve the kit the repo pins:

```sh
python3 <skill_dir>/bootstrap.py current "<root>" [--offline]
```

`current` reads `kit_ref`/`kit_sha` from `install.yaml` and returns the pinned
kit's tree, fetching it once into the cache when absent. Then:

1. Open **`<references_dir>/VERBS.md`** in the resolved kit and follow it — that
   doc owns the dispatch for every non-lifecycle verb and names the engine (in
   `<lib_dir>`) and flow doc (in `<references_dir>`) to run.
2. On `refused` (no recorded pin, or offline + uncached), the kit's docs are
   **not** on the machine. Say so, and tell the user to run `governance update`
   (online once) to record/refresh the pin and populate the cache.

## Rules

- **Never hand-execute file operations.** Every mutating verb runs a tested
  plan/apply engine from a fetched or pinned kit tree. No ad-hoc `cp` / `rm` /
  marker stamping / manifest edits.
- **Don't grow this shim.** Anything beyond resolve-fetch-delegate belongs in
  the kit. If procedure seems missing here, it lives in the kit's docs.
- **No network at commit time.** Fetching happens only inside user-invoked
  verbs; commit hooks never reach the network.

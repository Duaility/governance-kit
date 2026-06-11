---
name: governance
description: Installer and lifecycle entry point for governance-kit — `governance install` (bootstrap a repo from the released kit), `governance update` (re-pin/re-sync to a published kit version), `governance uninstall` (clean tear-down). For every other verb the skill is a thin router: `governance pack {search,create,add,update,remove,list}`, `governance directive {add,modify,remove}`, and `governance reset` execute from the kit version the repo pins in `install.yaml`, not from this machine copy. Use when the user says "governance install", "governance init", "set up governance", "bootstrap governance", "governance uninstall", "tear down governance", "update governance-kit", "pull new kit version", "kit update", "governance reset", "reset directives", "restore to original", "undo my amendments", "install a pack", "add pack X", "create a pack", "scaffold a pack", "new local pack", "update packs", "remove pack X", "list installed packs", "add a directive", "amend the constitution", "new directive", "modify directive X", "remove directive X", or otherwise asks to manage governance-kit lifecycle, packs, or directives.
license: MIT
compatibility: Designed for Claude Code and Codex; requires git and bash.
metadata:
  author: governance-kit
  version: "0.5.0"
---

# governance

**The skill is an installer. The kit is the product.** Same contract as
rustup/toolchain or nvm/node (issue [#194](https://github.com/Duaility/governance-kit/issues/194)).

This skill keeps exactly three first-class **lifecycle** verbs — `install`,
`update`, `uninstall`. They are the only verbs that run from *this* machine copy.
Every other verb (`pack *`, `directive *`, `reset`) executes from the **kit the
repo pins** in `.governance/install.yaml` (`kit_ref`/`kit_sha`), fetched into
`~/.governance/cache/kits/`. For those, the skill is a pure **router**: resolve
the pinned kit, then follow *its* flow docs and run *its* engines.

Why: `npx skills` tracks `main`, so a fat skill is the one path by which
unreleased content reaches repo state. A 3-verb installer has nothing meaningful
to skew — released kits, pinned per repo, are the single authority for rules,
flows, and assets.

> **One source tree, two roles.** In this monorepo `governance/` *is* both the
> installed skill and the kit artifact (the thing tagged `kit/vX.Y.Z`). The
> separation is realized at **consumption time**: the machine SKILL.md (below)
> documents only lifecycle inline and routes non-lifecycle verbs to the pinned
> kit's `references/` + `assets/`, instead of treating its own working copy as
> authority. That routing is what closes the skew.

## Verb surface

```
governance install [--to X.Y.Z]                       # bootstrap a repo from the released kit (alias: init)
governance update  [--to X.Y.Z] [--allow-downgrade] [--offline]
                   [--with-packs] [--check-upstream] [--dry-run] [--force]
                                                      # re-pin/re-sync to a published kit version (alias: kit update)
governance uninstall [--dry-run|--soft|--hard]        # tear-down

# ── routed to the repo-pinned kit (not this machine copy) ──
governance pack search|create|add|update|remove|list  # pack lifecycle
governance directive add|modify|remove <id> [--pack <owner>/<name>]
governance reset --directive <id> | --pack <id> | --all
```

## Verb dispatch

Infer the verb from the request, then branch on **lifecycle vs routed**:

| User says | Verb | Kind |
|---|---|---|
| "governance install", "governance init", "set up governance", "bootstrap governance" | `install` | lifecycle |
| "governance uninstall", "tear down governance", "clean slate", "remove governance from this repo" | `uninstall` | lifecycle |
| "update governance-kit", "kit update", "pull the new kit version", "the kit was published — sync this repo" | `update` | lifecycle |
| "pack search / create / add / update / remove / list", "install pack X", "scaffold a pack" | `pack *` | routed |
| "add / modify / remove directive X", "amend the constitution", "new directive" | `directive *` | routed |
| "governance reset", "reset directives", "restore to original", "undo my amendments" | `reset` | routed |

Disambiguation:
- `install` vs `uninstall`: `CONSTITUTION.md` + `.governance/` both present → lean `uninstall`; both absent → `install`. Ask once when still unclear.
- `update` vs `pack update`: "new kit-runtime files (`run.sh`, hook dispatcher)" → `update`; "new directive content from a pack" → `pack update`; both → `update --with-packs`.
- `reset` vs `uninstall`: "remove governance entirely" → `uninstall`; "restore the rules to their pinned version" → `reset`.

---

# Lifecycle verbs (run from this skill)

## `governance install`

Bootstraps governance-driven development in the current repo: a `CONSTITUTION.md`,
machine-enforced tests under `.governance/`, hook dispatchers, and a CI workflow.

**Tag-resolved (issue #194, milestone 1).** `install` first resolves and fetches
the **latest published `kit/vX.Y.Z` tag** (`--to X.Y.Z` pins an exact version),
then runs every assembly engine from *that* fetched tree — the released artifact,
not whatever `npx skills` last installed, is what reaches repo state. It records
the resolved `kit_ref`/`kit_sha` and a `kit_provenance` (`published-tag` /
`explicit` / `installed-skill`) in `install.yaml`. Offline, it falls back to this
installed skill and records that provenance.

**Authoritative flow:** [references/INIT_FLOW.md](references/INIT_FLOW.md) Steps 0–9.

### When to skip the flow

- Repo is not a git repo → stop; governance requires git.
- Repo already has `CONSTITUTION.md` + `.governance/` and the user asked a question (not a setup request) → answer it; do not bootstrap.
- Repo already has governance and the user asked for one targeted directive change → route to `directive *`.

## `governance update`

Moves the repo to a pinned kit version and re-syncs the kit-runtime files
`install` seeded (`run.sh`, `lib.sh`, `enable-governance.sh`, `governance.yml`,
hook dispatchers). The **repo-pinned model** (issue #177): `install.yaml`'s
`kit_ref`/`kit_sha` are the authoritative statement of which kit this repo runs.
The verb resolves a target → fetches its tree → **delegates apply to the target's
own engine** → records the pin. Disjoint from `pack update`: this updates the
*framework* code, not the rules content.

**Authoritative flow:** [references/UPDATE_FLOW.md](references/UPDATE_FLOW.md) Steps 1–8.

Key invariants:

- Resolve → fetch → delegate. `kit-resolve` resolves the target (default: latest published `kit/vX.Y.Z` tag; `--to X.Y.Z` for an exact version; offline falls back through the cached pin → installed skill), fetches it into `~/.governance/cache/kits/`, and names the engine the shim delegates `kit-plan`/`kit-apply` to. Forward/same-version run the *fetched target's own* engine.
- Diff-before-exec per file; files without a line-2 `governance-kit:managed` marker surface as `Skipped (unmanaged)` with a `keep` / `apply anyway` / `overwrite-with-backup` choice.
- Downgrades are explicit (`--allow-downgrade`); a target below `kit/v0.4.0` ships no engine and is refused with the legacy reinstall path.
- After a successful apply the resolved `kit_ref`/`kit_sha` are recorded via `kit-pin`; absent pin fields on a pre-#177 repo are backfilled on the first update.
- `--with-packs` chains `pack update` for every `source: gh` entry. No network at hook/commit time; `--offline` skips even the verb's fetch. Refuses on a dirty tree (override `--force`). One atomic commit, no auto-push.

## `governance uninstall`

Cleanly reverses every side-effect `install` can produce, honoring the
three-layer source-of-truth model (manifest → ownership marker → heuristic
fallback that defaults to dry-run).

**Authoritative flow:** [references/UNINSTALL_FLOW.md](references/UNINSTALL_FLOW.md) Steps 1–6.
The uninstall matrix lives in [references/UNINSTALL_MATRIX.md](references/UNINSTALL_MATRIX.md).
State-file schemas: [references/INSTALL_SCHEMA.md](references/INSTALL_SCHEMA.md) (`install.yaml`)
and [references/LOCK_SCHEMA.md](references/LOCK_SCHEMA.md) (`packs.lock`).

Key invariants:

- Deterministic plan/apply pair: `packverb uninstall-plan` surveys + classifies; `packverb uninstall-apply --mode <m> [--allow-heuristic]` executes the reversal in fixed order. The skill never hand-executes the `rm` / `mv` / `git config` / AGENTS.md edits.
- Never delete a file without ownership evidence (manifest entry or line-2 `governance-kit:managed` marker). Dry-run is the default when the manifest is missing but artifacts are detected.
- No destructive git ops. Leave changes unstaged.

> **Lifecycle engines run from this skill.** `install` resolves and runs from the
> fetched released kit (its `init-apply`); `update` delegates to the fetched
> target's `kit-apply`; `uninstall` runs `packverb uninstall-apply` from this
> machine copy (it deletes the repo's own installed tree — there is no pinned kit
> to delegate to once you are tearing down). The deterministic plan/apply pairs
> mean the skill never hand-executes file operations.

---

# Routed verbs (run from the repo-pinned kit)

`pack *`, `directive *`, and `reset` are **not** documented inline here — they
execute from the kit the repo pins. The skill resolves that kit, then follows its
flow docs and runs its engines. This is the #177 `update` delegation generalized
to every non-lifecycle verb (issue #194, milestone 2).

## Step R — Resolve the pinned kit (do this first, for any routed verb)

```sh
uv run --quiet --isolated --with PyYAML python \
    governance/assets/packs/lib/kitverb.py kit-current "<root>" [--offline]
```

`kit-current` reads the repo's `kit_ref`/`kit_sha` from `install.yaml`, returns
the cached pinned tree (fetching it once into `~/.governance/cache/kits/` when
absent), and degrades to this installed skill when there is no recorded pin or
the pinned tree is uncached and unreachable. It writes nothing. Consume its JSON:

| Field | Use |
|---|---|
| `result` | `ok`. |
| `provenance` | `cache` / `fetch` / `installed-skill` — name it if you surface assumptions. |
| `lib_dir` | The pinned kit's `assets/packs/lib`. **Run the verb's engine from here** (`<lib_dir>/packverb.py …`). |
| `references_dir` | The pinned kit's `references/`. **Read the verb's flow doc from here**, not from this skill's own `references/`. |
| `assets_dir` | The pinned kit's `assets/` — templates, bundled `packs/`, `catalog.community.json`. |
| `assumptions[]` | Offline / unpinned notes to surface in the verb's report. |

Then open the routed verb's flow doc **in `<references_dir>`** and run its engines
**from `<lib_dir>`**. The paths below name the doc inside the pinned kit:

| Verb | Flow doc (read from `<references_dir>`) | Engine (run from `<lib_dir>`) |
|---|---|---|
| `pack search/create/add/update/remove/list` | `PACK_VERBS.md` | `packverb.py` (`catalog-search`, `pack-plan`, `pack-apply`, `lock-*`) |
| `directive add/modify/remove` | `DIRECTIVE_VERBS.md` → `DIRECTIVE_AMEND_FLOW.md` | `packverb.py` + `assets/amend/` templates |
| `reset --directive/--pack/--all` | `RESET_FLOW.md` | `packverb.py` (`reset-plan`, `reset-apply`) |

> **When `kit-current` falls back to `installed-skill`** (no pin, or offline +
> uncached), `<references_dir>`/`<lib_dir>` are this machine copy. The verb still
> works; surface the assumption so the user knows it ran from the local skill
> rather than the pinned release, and suggest `governance update` to record/refresh
> the pin.

The kit-resident copies of these flow docs live alongside this skill at
[references/PACK_VERBS.md](references/PACK_VERBS.md),
[references/DIRECTIVE_VERBS.md](references/DIRECTIVE_VERBS.md),
[references/DIRECTIVE_AMEND_FLOW.md](references/DIRECTIVE_AMEND_FLOW.md), and
[references/RESET_FLOW.md](references/RESET_FLOW.md) — but at run time read the
**pinned kit's** copies (`<references_dir>`), which may differ from this working
copy. Authoring guidance: [references/PACK_AUTHORING.md](references/PACK_AUTHORING.md),
[references/DIRECTIVES_CATALOG.md](references/DIRECTIVES_CATALOG.md).

---

## Key design rules

- **Installer vs product.** The skill installs and updates; the kit *is* the rules, flows, and assets. Lifecycle verbs run from the skill; everything else runs from the repo-pinned kit. Don't enrich the machine skill with routed-verb logic — move it into the kit and route through the pin.
- **One writer.** Mutations to the governance surface (`CONSTITUTION.md`, `.governance/`, hooks, `install.yaml`, `packs.lock`, the AGENTS.md directive block) flow through this skill — whether it runs the engine locally (lifecycle) or from the pinned kit (routed).
- **Verb dispatch before flow.** Confirm the verb before running any flow. A user who said "uninstall" is not asking for a fresh bootstrap because the repo looks unsetup.
- **No network at commit time.** All fetching happens inside user-invoked verbs (`install`/`update`/`pack *`/`kit-current`). Commit hooks never reach the network.
- **Deterministic plan/apply.** Every mutating verb resolves a plan then applies it in one tested engine call (diff-before-exec, per-file decisions, one atomic commit). The skill never hand-executes `cp` / `rm` / marker stamping / manifest edits.

## References

- [../CONSTITUTION.md](../CONSTITUTION.md) — the live directive set for this repo.
- [../GOVERNANCE_VOCABULARY.md](../GOVERNANCE_VOCABULARY.md) — shared terms across the governance surface.
- Lifecycle (run from this skill): [references/INIT_FLOW.md](references/INIT_FLOW.md), [references/UPDATE_FLOW.md](references/UPDATE_FLOW.md), [references/UNINSTALL_FLOW.md](references/UNINSTALL_FLOW.md).
- Routed (read from the pinned kit at run time): [references/PACK_VERBS.md](references/PACK_VERBS.md), [references/DIRECTIVE_VERBS.md](references/DIRECTIVE_VERBS.md), [references/DIRECTIVE_AMEND_FLOW.md](references/DIRECTIVE_AMEND_FLOW.md), [references/RESET_FLOW.md](references/RESET_FLOW.md).
- Per-verb reference: [references/VERBS.md](references/VERBS.md). State schemas: [references/INSTALL_SCHEMA.md](references/INSTALL_SCHEMA.md), [references/LOCK_SCHEMA.md](references/LOCK_SCHEMA.md).
- Catalog target of `pack search`: [assets/catalog.community.json](assets/catalog.community.json).

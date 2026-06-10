---
name: governance
description: Single entry point for governance-kit's lifecycle verbs — `governance init` (bootstrap a repo), `governance uninstall` (clean tear-down), `governance reset` (restore amended directives to their pinned pack version), `governance kit update` (re-sync runtime files when a new kit version is published), `governance pack {search,create,add,update,remove,list}` (pack lifecycle — `create` scaffolds a hand-authored repo-local pack at `.governance/packs/<repo-owner>/<name>/`; `add`/`update`/`remove` cover community packs with SHA pinning + capability enforcement), and `governance directive {add,modify,remove}` (hand-authored directive amendments via the atomic triple, optionally `--pack <owner>/<name>` to target a specific pack). Use when the user says "governance init", "set up governance", "bootstrap governance", "governance uninstall", "tear down governance", "governance reset", "reset directives", "restore to original", "undo my amendments", "kit update", "update governance-kit", "pull new kit version", "install a pack", "add pack X", "create a pack", "create a frontend pack", "scaffold a pack", "new local pack", "update packs", "remove pack X", "list installed packs", "add a directive", "amend the constitution", "new directive", "modify directive X", "remove directive X", or otherwise asks to manage governance-kit lifecycle, packs, or directives.
license: MIT
compatibility: Designed for Claude Code and Codex; requires git and bash.
metadata:
  author: governance-kit
  version: "0.4.0"
---

# governance

This skill is the **unified lifecycle entry point** for governance-kit. It exposes a verb surface inspired by [spec-kit](https://github.com/github/spec-kit) — a single writer for the governance surface rather than a fleet of per-lifecycle skills that each mutate `CONSTITUTION.md`, `.governance/`, hooks, and ownership markers.

Tracking issue: [Duaility/governance-kit#31](https://github.com/Duaility/governance-kit/issues/31).

## Verb surface

```
governance init                                       # bootstrap a repo
governance kit update [--with-packs] [--check-upstream] [--dry-run] [--force]
                                                      # re-sync runtime files (run.sh, lib.sh, enable-governance.sh,
                                                      # governance.yml, hook dispatchers) when a new kit
                                                      # version is on PATH; --with-packs also re-pins gh packs;
                                                      # --check-upstream reports if the installed skill is behind
governance pack search [query]                        # search community catalog
governance pack create <name>                         # scaffold a repo-local pack at packs/<repo-owner>/<name>/
governance pack add <ref>                             # e.g. gh:acme/soc2-pack@main
governance pack update [<pack-id>]                    # re-pin SHAs, diff-before-exec
governance pack remove <pack-id>                      # uninstall a pack (community or repo-local)
governance pack list                                  # enumerate installed packs
governance directive add|modify|remove <directive-id> [--pack <owner>/<name>]
                                                      # hand-authored directives (atomic triple);
                                                      # --pack defaults to the repo's own local pack
governance reset --directive <id> | --pack <id> | --all
                                                      # restore drifted directives to pinned pack version
                                                      #   --drop-handauthored: also delete user-added directives (only with --all)
                                                      #   --dry-run, --force
governance uninstall [--dry-run|--soft|--hard]        # tear-down
```

`pack *` verbs run through `packverb` helpers (`fetch`, `parse-ref`, `capability-check`, `lock-*`, `catalog-search`) in [`assets/packs/lib/packverb.py`](assets/packs/lib/packverb.py) — see [references/PACK_VERBS.md](references/PACK_VERBS.md) for the full flow of each verb.

## Verb dispatch

Infer the intended verb from the user's request:

| User says | Verb |
|---|---|
| "governance init", "set up governance", "bootstrap governance", "install governance-kit" | `init` |
| "governance uninstall", "tear down governance", "uninstall governance-kit", "clean slate", "remove governance from this repo" | `uninstall` |
| "governance reset", "reset directives", "restore to original", "undo my amendments", "the directive I changed broke something — put it back" | `reset` — see [references/RESET_FLOW.md](references/RESET_FLOW.md). Disambiguate from `uninstall` by asking "do you want to remove governance entirely, or just restore the rules to their pinned version?" if intent is unclear. |
| "kit update", "update governance-kit", "pull the new kit version", "the kit was published — sync this repo", "update run.sh / governance.yml from the kit" | `kit update` — see [references/UPDATE_FLOW.md](references/UPDATE_FLOW.md). Disambiguate from `pack update` by asking "do you want the new kit-runtime files (`run.sh`, hook dispatcher) or new directive content from a pack?" — if both, suggest `kit update --with-packs`. |
| "add / modify / remove directive X", "amend the constitution", "new directive" | `directive *` — see [references/DIRECTIVE_VERBS.md](references/DIRECTIVE_VERBS.md). |
| "pack search / create / add / update / remove / list", "install pack X", "create a frontend pack", "new local pack", "scaffold a pack", "pin pack X", "update all packs" | `pack *` — see [references/PACK_VERBS.md](references/PACK_VERBS.md). `pack create <name>` scaffolds a hand-authored repo-local pack; `pack add <ref>` installs a community pack. Do **not** fall back to editing the in-tree pack tree by hand. |

If the user's intent is ambiguous between `init` and `uninstall`, look at the repo state: `CONSTITUTION.md` + `.governance/` both present → `uninstall` is more likely; both absent → `init`. Ask once when still ambiguous.

## `governance init`

Bootstraps governance-driven development in the current repo:

1. `CONSTITUTION.md` at the root — the evolving source of truth.
2. Machine-enforced tests under `.governance/`, one folder per directive.
3. A pre-commit hook (and `commit-msg` / `prepare-commit-msg` / `post-commit` / `pre-push` dispatchers when selected directives need them) honoring `SKIP_GOVERNANCE=1` and `git commit --no-verify` / `git push --no-verify`.
4. A GitHub Actions workflow at `.github/workflows/governance.yml`.

**Authoritative flow:** [references/INIT_FLOW.md](references/INIT_FLOW.md) Steps 1–8. Pack manifests are validated against the `KIT_VERSION` constant in [`assets/packs/lib/packctl.py`](assets/packs/lib/packctl.py); packs declaring a newer `min_governance_kit` are rejected.

Deterministic plan/apply: the skill owns the elicitation (packs/preset/directives, principles, collision choices, the Step-8 finding loop, the commit); [`assets/packs/lib/packverb.py`](assets/packs/lib/packverb.py) `init-plan`/`init-apply` (engines `initplan.py`/`initapply.py`) do the mechanical assembly — directive installs, CONSTITUTION assembly from subsections, runtime/CI stamping, hook generation, manifest + lock writes, smoke test — from a serialized `--decisions` object. It never hand-executes those writes.

### When to skip the flow

- Repo is not a git repo → stop, tell the user governance requires git.
- Repo already has `CONSTITUTION.md` + `.governance/` and the user asked a question (not a setup request) → answer the question; do not bootstrap.
- Repo already has governance and the user asked for one targeted directive change → route to `directive *`.

## `governance uninstall`

Cleanly tears down a previously-bootstrapped governance-kit setup. Reverses every side-effect `init` can produce, honoring the three-layer source-of-truth model (manifest → ownership marker → heuristic fallback that defaults to dry-run).

**Authoritative flow:** [references/UNINSTALL_FLOW.md](references/UNINSTALL_FLOW.md) Steps 1–6. The uninstall matrix lives in [references/UNINSTALL_MATRIX.md](references/UNINSTALL_MATRIX.md). The two governance state files have separate schemas: [references/INSTALL_SCHEMA.md](references/INSTALL_SCHEMA.md) (`install.yaml`) and [references/LOCK_SCHEMA.md](references/LOCK_SCHEMA.md) (`packs.lock`).

Key invariants:

- Deterministic plan/apply pair: `packverb uninstall-plan` surveys + classifies and `packverb uninstall-apply --mode <m> [--allow-heuristic]` (engines `uninstallplan.py`/`uninstallapply.py`) executes the reversal in fixed order in one tested call. The skill never hand-executes the `rm` / `mv` / `git config` / AGENTS.md edits.
- Never delete a file without ownership evidence (manifest entry or line-2 `governance-kit:managed` marker).
- Dry-run is the default when the manifest is missing but artifacts are detected.
- No destructive git ops — no `git clean`, no `git reset --hard`, no stash.
- Leave changes unstaged; the user's first post-uninstall commit is intentional.

## `governance kit update`

Re-syncs the kit-runtime files installed at `init` (`run.sh`, `lib.sh`, `enable-governance.sh`, `governance.yml`, hook dispatchers) when a newer kit is on PATH. Stamps the new version into `install.yaml.kit_version`. Disjoint from `pack update`: this verb updates the *framework* code, not the rules content.

**Authoritative flow:** [references/UPDATE_FLOW.md](references/UPDATE_FLOW.md) Steps 1–8.

Key invariants:

- Deterministic plan/apply pair: [`assets/packs/lib/kitverb.py`](assets/packs/lib/kitverb.py) `kit-plan --diff` resolves the plan (version delta, managed-file inventory, noise-free diffs) and `kit-apply` executes it (gates, pre-stamped writes, per-file decisions, hook regeneration, manifest write-through, smoke test) in one tested call. The skill elicits decisions, shows diffs, and commits — it never hand-executes `cp` / marker stamping / manifest edits.
- Refuses without `install.yaml`. The manifest is the version pin this verb writes through.
- Diff-before-exec per file. Files without a line-2 `governance-kit:managed` marker are surfaced as `Skipped (unmanaged)` and the user picks `keep` / `apply anyway` / `overwrite-with-backup`.
- No silent downgrades: a manifest stamp newer than the kit on PATH stops the verb.
- `--with-packs` chains `pack update` for every `source: gh` entry; without the flag, kit-runtime sync is a pure local file-copy and never touches the network.
- `--check-upstream` adds a read-only `git ls-remote` against the kit's upstream to report whether the *installed skill* is behind the latest published `kit/vX.Y.Z` — a signal only. It never fetches-and-applies the kit (that stays the skill manager's job, `npx skills update governance --global`); the verb only ever syncs the repo to the installed kit.
- Refuses on a dirty working tree (override with `--force`).
- One atomic commit per run, Conventional Commits subject, no auto-push.

## `governance reset`

Restores drifted directives back to their **pinned pack version** without uninstalling. Pairs with `directive *`: `directive {add,modify,remove}` is how the user amends rules over time, and `reset` is the recovery hatch when an amendment causes problems.

**Authoritative flow:** [references/RESET_FLOW.md](references/RESET_FLOW.md) Steps 1–7.

Three scopes — one is required:

- `reset --directive <id>` — restore one pack-sourced directive.
- `reset --pack <id>` — restore every directive sourced from one pack.
- `reset --all` — restore every pack-sourced directive in the install manifest.

By default, hand-authored directives (added via `directive add`, no pack source) are **preserved**. Pass `--drop-handauthored` (only valid with `--all`) to delete them in the same commit. Reset reads the install manifest and the pack lockfile — it refuses to run if either is missing, because pack provenance cannot be reconstructed by heuristic. The user's recovery path in that case is `governance uninstall` + `governance init`.

Reset restores to the **SHA already pinned**, not upstream HEAD. Use `governance pack update` when the user wants newer rules; use `governance reset` when they want pristine ones.

Key invariants:

- Deterministic plan/apply pair: `packverb reset-plan <scope> … [--diff]` resolves pinned sources + classifies restore/skip/drop and `packverb reset-apply <scope> … [--date --author]` (engines `resetplan.py`/`resetapply.py`) restores folders + CONSTITUTION subsections, regenerates hooks, and appends the Evolution Log in one tested call. The skill never hand-executes file operations.
- Refuses on a dirty working tree (override with `--force`).
- Diff-before-exec: every restore prints the per-directive diff before any file is written.
- One atomic commit per run, Conventional Commits subject, Evolution Log entry appended.
- `--dry-run` prints the plan without committing.

## `governance pack *`

Install, update, list, and remove community packs. Packs are resolved from GitHub refs (`gh:owner/repo[/subpath][@rev]`), validated, capability-checked, and pinned by resolved SHA in `.governance/packs.lock` (which also records `governance-kit/core` and any repo-local packs — see [references/LOCK_SCHEMA.md](references/LOCK_SCHEMA.md)). Shared cache at `${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<id>@<sha>/`.

See [references/PACK_VERBS.md](references/PACK_VERBS.md) for step-by-step flows. Key guarantees:

- **Deterministic plan/apply.** `add`/`update`/`remove` resolve via `packverb pack-plan {add,update,remove} … [--diff]` and execute via `packverb pack-apply {add,update,remove} …` (engines `packplan.py`/`packapply.py`) — one tested call for install/delete folders, the seeded-asset ledger, CONSTITUTION subsection surgery, hook regeneration, and lockfile upsert/prune. The skill never hand-executes file operations.
- **SHA-pinned.** `pack add gh:acme/soc2@main` resolves `main` once and records the SHA; subsequent `check.sh` runs never chase a moving branch.
- **Diff-before-exec.** Every install / update shows the `check.sh` diff before writing. The user sees the code that will start running on their commits.
- **Capability-enforced.** Directives that declare `reads:`/`writes:` globs in `directive.yaml` have their `check.sh` statically swept for out-of-bound path references; a single violation aborts the install.
- **No network at commit time.** All fetching happens inside verbs. Hook dispatchers never invoke `packctl fetch`.

## `governance directive *`

Hand-authored directive flows for adding, modifying, or removing directives. Every amendment is the **atomic triple**: a directive folder at `.governance/packs/<owner>/<repo>/directives/<id>/`, a **Directives** subsection in `CONSTITUTION.md`, and an **Evolution Log** entry — all land in one commit or none do.

**Authoritative flow:** [references/DIRECTIVE_AMEND_FLOW.md](references/DIRECTIVE_AMEND_FLOW.md) Steps 1–7. Per-verb summaries and aliases live in [references/DIRECTIVE_VERBS.md](references/DIRECTIVE_VERBS.md). Authoring guidance in [references/DIRECTIVE_AUTHORING.md](references/DIRECTIVE_AUTHORING.md). Templates at [`assets/amend/directive.template.sh`](assets/amend/directive.template.sh) and [`assets/amend/directive-section.template.md`](assets/amend/directive-section.template.md).

**Don't** use these verbs for directives that came from a community pack (tracked in `.governance/packs.lock`) — use `pack update` / `pack remove` so the lockfile stays consistent.

## Key design rules

- **One writer.** Mutations to the governance surface (`CONSTITUTION.md`, `.governance/`, hooks, `.governance/install.yaml`, `.governance/packs.lock`, AGENTS.md directive block) flow through this skill.
- **Verb dispatch before flow.** Confirm the verb before running any flow. A user who said "uninstall" is not asking for a fresh bootstrap because the repo looks unsetup.
- **Pack-contract forward-compatibility.** New community packs will declare `reads:` / `writes:` capabilities and may depend on a specific `min_governance_kit`. Both are validated by `packctl.py` today; runtime enforcement of capabilities is tied to `governance pack add`.
- **No network at commit time.** All pack fetching happens inside user-invoked verbs. Commit hooks must not reach the network — this is enforced implicitly by keeping fetch logic out of directive `check.sh` scripts.

## References

- [../CONSTITUTION.md](../CONSTITUTION.md) — the live directive set for this repo.
- [../GOVERNANCE_VOCABULARY.md](../GOVERNANCE_VOCABULARY.md) — shared terms across the governance skills.
- [references/INIT_FLOW.md](references/INIT_FLOW.md) — authoritative `init` flow.
- [references/UNINSTALL_FLOW.md](references/UNINSTALL_FLOW.md) — authoritative `uninstall` flow.
- [references/RESET_FLOW.md](references/RESET_FLOW.md) — authoritative `reset` flow.
- [references/UPDATE_FLOW.md](references/UPDATE_FLOW.md) — authoritative `kit update` flow.
- [references/DIRECTIVE_AMEND_FLOW.md](references/DIRECTIVE_AMEND_FLOW.md) — authoritative atomic-triple flow for `directive *`.
- [references/PACK_VERBS.md](references/PACK_VERBS.md) — authoritative flows for `pack *`.
- [references/VERBS.md](references/VERBS.md) — per-verb reference, aliases, assets.
- [references/DIRECTIVES_CATALOG.md](references/DIRECTIVES_CATALOG.md) — ready-made directives and the authoring template.
- [references/PACK_AUTHORING.md](references/PACK_AUTHORING.md) — pack + directive schemas, capability declarations, and scoped pack ids.
- [assets/catalog.community.json](assets/catalog.community.json) — community pack catalog (target of `governance pack search`).

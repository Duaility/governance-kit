# governance skill — verb reference

Per-verb behavior for the unified `governance` skill. This is the
reference file pointed at by [`../SKILL.md`](../SKILL.md); see the issue
[#31](https://github.com/Duaility/governance-kit/issues/31) for the
full rearchitecture context.

## `init`

- **Aliases a user might type:** `governance init`, `governance bootstrap`, `set up governance`, `install governance-kit`, `add governance to this repo`.
- **Precondition:** must be a git repo.
- **Authoritative flow:** [INIT_FLOW.md](INIT_FLOW.md) Steps 1–8.
- **Assets used:**
  - `../assets/CONSTITUTION.template.md`
  - `../assets/AGENTS.directive.md`
  - `../assets/packs/` (kit-bundled pack tree — today: `core` plus the shared `lib/`)
  - `../../extensions/packs/` (monorepo of community-shaped packs — today: `duaility/agent-governance`)
  - `../assets/dot-governance/`
  - `../assets/governance.yml`
  - `../assets/setup-clone.sh`
- **Install manifest:** `.governance/installed-packs.yaml` (`version: "1"`).
- Pack validation enforces `min_governance_kit` against `KIT_VERSION` from [`../assets/packs/lib/packctl.py`](../assets/packs/lib/packctl.py).

## `uninstall`

- **Aliases a user might type:** `governance uninstall`, `tear down governance`, `remove governance-kit`, `clean slate`, `remove governance from this repo`.
- **Not** an alias for `reset` — see disambiguation in [`../SKILL.md`](../SKILL.md). "uninstall" removes governance entirely; "reset" restores rules to pinned versions while leaving the install in place.
- **Modes:** `dry-run` (default when manifest missing), `soft` (default when manifest present), `hard` (also strips seeded docs like `QUALITY.md`, `COSTS.md`, and `.pre-governance.bak` backups).
- **Authoritative flow:** [UNINSTALL_FLOW.md](UNINSTALL_FLOW.md) Steps 1–6.
- **Source-of-truth ladder:** install manifest → `governance-kit:managed` line-2 marker → heuristic fallback (forces dry-run).
- **Directive:** never delete a file without ownership evidence.

## `reset`

- **Aliases a user might type:** `governance reset`, `reset directives`, `restore to original`, `undo my amendments`, `put the rules back`.
- **Precondition:** repo must have governance installed (`CONSTITUTION.md` + `.governance/` + `.governance/installed-packs.yaml`). Reset refuses to run without the install manifest — pack provenance cannot be reconstructed by heuristic.
- **Scopes (exactly one required):** `--directive <id>`, `--pack <id>`, `--all`.
- **Flags:** `--drop-handauthored` (only with `--all`), `--dry-run`, `--force` (override the dirty-working-tree refusal).
- **Authoritative flow:** [RESET_FLOW.md](RESET_FLOW.md) Steps 1–7.
- **Pinned, not latest.** Reset restores to the SHA in `.governance/packs.lock` (or the kit-bundled `core` tree). For newer upstream content use `pack update`.
- **Hand-authored is preserved by default.** Pass `--drop-handauthored` to delete user-added directives that have no pristine source.
- **Diff-before-exec.** Per-directive diff is shown before any file is written.
- **One atomic commit.** Conventional-commit subject + Evolution Log entry, same discipline as `directive *`.

## `pack *`

Full flows live in [PACK_VERBS.md](PACK_VERBS.md). Summary:

| Verb | Intent |
|---|---|
| `pack search [query]` | Search `extensions/catalog.community.json` and return matching entries via `packverb catalog-search`. |
| `pack add <ref>` | Fetch a pack from a GitHub ref (`gh:owner/repo[/subpath][@rev]`), resolve to a concrete SHA, validate, show `check.sh` diffs before writing (diff-before-exec), install directive folders, and record the pin in `.governance/packs.lock`. Refuse if any directive declares `reads:`/`writes:` globs and the directive's `check.sh` references paths outside those globs. |
| `pack update [<pack-id>]` | Resolve the ref to a newer SHA, re-run diff-before-exec, rewrite directive folders, update the lock. |
| `pack remove <pack-id>` | Remove installed directive folders owned by the pack (from `.governance/installed-packs.yaml`), regenerate the hook dispatcher, prune the lock entry. |
| `pack list` | Print installed packs with their pinned SHAs from `.governance/packs.lock`. |

**Never** install by hand-copying into `governance/assets/packs/` — that is governance-kit's own in-tree source tree, not a consumer's repo surface. Pack installs for a consumer repo flow through `governance pack add`.

## `directive *`

Full flows live in [DIRECTIVE_VERBS.md](DIRECTIVE_VERBS.md). Summary:

| Verb | Intent |
|---|---|
| `directive add <id>` | Draft a new directive (test + constitution subsection + Evolution Log entry) and commit atomically. |
| `directive modify <id>` | Edit an existing directive's check or rationale; append an Evolution Log entry. |
| `directive remove <id>` | Delete the directive folder, remove its subsection from `CONSTITUTION.md`, log the removal, surface dangling references. |

All three follow [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) Steps 1–7. Directives installed via `governance pack add` are off-limits for `directive *` — touch them through the matching `pack *` verb.

## Trigger words this skill should NOT claim

- "uninstall the governance skill from my machine" → this operates on **repo state**, not on `~/.claude/skills/`. Tell the user to remove the symlink themselves.

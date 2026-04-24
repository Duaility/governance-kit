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
  - `../assets/tests-bash/`
  - `../assets/governance.yml`
  - `../assets/setup-clone.sh`
- **Install manifest:** `.governance-kit/installed-packs.yaml` (`version: "1"`).
- Pack validation enforces `min_governance_kit` against `KIT_VERSION` from [`../assets/packs/lib/packctl.py`](../assets/packs/lib/packctl.py).

## `uninstall`

- **Aliases a user might type:** `governance uninstall`, `governance reset`, `tear down governance`, `remove governance-kit`, `clean slate`.
- **Modes:** `dry-run` (default when manifest missing), `soft` (default when manifest present), `hard` (also strips seeded docs like `QUALITY.md`, `COSTS.md`, and `.pre-governance.bak` backups).
- **Authoritative flow:** [UNINSTALL_FLOW.md](UNINSTALL_FLOW.md) Steps 1–6.
- **Source-of-truth ladder:** install manifest → `governance-kit:managed` line-2 marker → heuristic fallback (forces dry-run).
- **Directive:** never delete a file without ownership evidence.

## `pack *`

Full flows live in [PACK_VERBS.md](PACK_VERBS.md). Summary:

| Verb | Intent |
|---|---|
| `pack search [query]` | Search `extensions/catalog.community.json` and return matching entries via `packverb catalog-search`. |
| `pack add <ref>` | Fetch a pack from a GitHub ref (`gh:owner/repo[/subpath][@rev]`), resolve to a concrete SHA, validate, show `check.sh` diffs before writing (diff-before-exec), install directive folders, and record the pin in `.governance/packs.lock`. Refuse if any directive declares `reads:`/`writes:` globs and the directive's `check.sh` references paths outside those globs. |
| `pack update [<pack-id>]` | Resolve the ref to a newer SHA, re-run diff-before-exec, rewrite directive folders, update the lock. |
| `pack remove <pack-id>` | Remove installed directive folders owned by the pack (from `.governance-kit/installed-packs.yaml`), regenerate the hook dispatcher, prune the lock entry. |
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

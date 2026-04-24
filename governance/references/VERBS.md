# governance skill — verb reference

Per-verb behavior for the unified `governance` skill. This is the
reference file pointed at by [`../SKILL.md`](../SKILL.md); see the issue
[#31](https://github.com/Duaility/governance-kit/issues/31) for the
full rearchitecture context.

## `init`

- **Aliases a user might type:** `governance init`, `governance bootstrap`, `set up governance`, `install governance-kit`, `add governance to this repo`.
- **Precondition:** must be a git repo.
- **Authoritative flow:** [../../governance-bootstrap/SKILL.md](../../governance-bootstrap/SKILL.md) Steps 1–8.
- **Assets used:**
  - `../../governance-bootstrap/assets/CONSTITUTION.template.md`
  - `../../governance-bootstrap/assets/AGENTS.directive.md`
  - `../../governance-bootstrap/assets/packs/` (pack tree with `core` and `agent-governance`)
  - `../../governance-bootstrap/assets/tests-bash/`
  - `../../governance-bootstrap/assets/governance.yml`
  - `../../governance-bootstrap/assets/setup-clone.sh`
- **Install manifest:** `.governance-kit/installed-packs.yaml` (`version: "1"`).
- **New in this rework:** pack validation now enforces `min_governance_kit` against `KIT_VERSION` from `packctl.py`.

## `uninstall`

- **Aliases a user might type:** `governance uninstall`, `governance reset`, `tear down governance`, `remove governance-kit`, `clean slate`.
- **Modes:** `dry-run` (default when manifest missing), `soft` (default when manifest present), `hard` (also strips seeded docs like `QUALITY.md`, `COSTS.md`, and `.pre-governance.bak` backups).
- **Authoritative flow:** [../../governance-reset/SKILL.md](../../governance-reset/SKILL.md) Steps 1–6.
- **Source-of-truth ladder:** install manifest → `governance-kit:managed` line-2 marker → heuristic fallback (forces dry-run).
- **Invariant:** never delete a file without ownership evidence.

## `pack *`

Full flows live in [PACK_VERBS.md](PACK_VERBS.md). Summary:

| Verb | Intent |
|---|---|
| `pack search [query]` | Search `extensions/catalog.community.json` and return matching entries via `packverb catalog-search`. |
| `pack add <ref>` | Fetch a pack from a GitHub ref (`gh:owner/repo[/subpath][@rev]`), resolve to a concrete SHA, validate, show `check.sh` diffs before writing (diff-before-exec), install rule folders, and record the pin in `.governance/packs.lock`. Refuse if any rule declares `reads:`/`writes:` globs and the rule's `check.sh` references paths outside those globs. |
| `pack update [<pack-id>]` | Resolve the ref to a newer SHA, re-run diff-before-exec, rewrite rule folders, update the lock. |
| `pack remove <pack-id>` | Remove installed rule folders owned by the pack (from `.governance-kit/installed-packs.yaml`), regenerate the hook dispatcher, prune the lock entry. |
| `pack list` | Print installed packs with their pinned SHAs from `.governance/packs.lock`. |

**Never** install by hand-copying into `governance-bootstrap/assets/packs/` — that is governance-kit's own in-tree source tree, not a consumer's repo surface. Pack installs for a consumer repo flow through `governance pack add`.

## `rule *`

Full flows live in [RULE_VERBS.md](RULE_VERBS.md). Summary:

| Verb | Intent |
|---|---|
| `rule add <id>` | Draft a new rule (test + constitution subsection + Evolution Log entry) and commit atomically. |
| `rule modify <id>` | Edit an existing rule's check or rationale; append an Evolution Log entry. |
| `rule remove <id>` | Delete the rule folder, remove its invariant subsection, log the removal, surface dangling references. |

All three delegate to [../../governance-amend/SKILL.md](../../governance-amend/SKILL.md) Steps 1–6 until that skill is retired. Rules installed via `governance pack add` are off-limits for `rule *` — touch them through the matching `pack *` verb.

## Trigger words this skill should NOT claim

- "review the constitution", "audit governance", "find dead rules" → `governance-gardener`.
- "add a rule X", "amend rule Y", "remove rule Z" → this skill's `rule *` verb (delegates to `governance-amend`).
- "uninstall the governance skill from my machine" → this operates on **repo state**, not on `~/.claude/skills/`. Tell the user to remove the symlink themselves.

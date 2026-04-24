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

## `pack *` (planned, not yet implemented)

These verbs are tracked under issue #31 and will land in a subsequent
PR. Surface sketch:

| Verb | Intent |
|---|---|
| `pack search [query]` | Search `extensions/catalog.community.json` and return matching entries. |
| `pack add <ref>` | Install a pack from a GitHub ref. Default to SHA pinning via `.governance/packs.lock`. Show `check.sh` diffs before writing (diff-before-exec). Refuse if a rule's `reads:` / `writes:` declarations reach outside the pack's own folder or the declared globs. |
| `pack update [<pack-id>]` | Resolve to a new SHA, re-run diff-before-exec, update the lock. |
| `pack remove <pack-id>` | Remove installed rule folders owned by the pack, prune the lock entry. |
| `pack list` | Print installed packs from `.governance/packs.lock` with their pinned SHAs. |

Until these land, do not fall back to manually editing
`governance-bootstrap/assets/packs/` — that is the in-tree source tree,
not the user's repo surface.

## `rule *` (planned, not yet implemented)

Verbs: `rule add`, `rule modify`, `rule remove`. Will replace the
standalone `governance-amend` skill once parity is reached. Until then,
redirect the user there.

## Trigger words this skill should NOT claim

- "review the constitution", "audit governance", "find dead rules" → `governance-gardener`.
- "add a rule X", "amend rule Y", "remove rule Z" → `governance-amend` (not yet superseded).
- "uninstall the governance skill from my machine" → this operates on **repo state**, not on `~/.claude/skills/`. Tell the user to remove the symlink themselves.

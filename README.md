# governance-kit

A set of Claude Code skills for governance-driven development — where invariants, guidelines, and non-negotiables live in a versioned `CONSTITUTION.md` and are enforced by tests in `tests/governance/`.

The user-facing entry point is **[governance](governance/)** — a single skill with a verb surface:

- `governance init` — bootstrap governance-driven development into a fresh repo.
- `governance uninstall [--dry-run|--soft|--hard]` — tear down a previously bootstrapped setup with ownership-marker discipline.
- `governance pack {search,add,update,remove,list}` — install and manage community rule packs. SHA-pinned via `.governance/packs.lock`, capability-enforced (`reads:` / `writes:` globs), diff-before-exec.
- `governance rule {add,modify,remove}` — author, edit, or retire a rule as an atomic triple (rule folder + constitution subsection + Evolution Log entry, one commit).

Companion skill:

- **[governance-gardener](governance-gardener/)** — walks the governance surface and produces a dated Governance Health Report; pairs with the `doc-freshness` rule and hands rule-shaped candidates back to `governance rule *`.

Community-shaped packs that ship alongside the kit live under [extensions/packs/](extensions/packs/) (today: `duaility/agent-governance`). The kit-bundled `core` pack lives at [governance/assets/packs/core/](governance/assets/packs/core/).

See [governance/SKILL.md](governance/SKILL.md) for the activation flow and references.

## After cloning

Once per fresh clone, run:

```sh
./scripts/setup-clone.sh
```

It sets `core.hooksPath=.githooks` so the governance pre-commit hook fires. Worktrees (`git worktree add ...`) inherit this config from their parent checkout — no per-worktree action needed.

## License

MIT

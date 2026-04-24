# governance-kit

A set of Claude Code skills for governance-driven development — where invariants, guidelines, and non-negotiables live in a versioned `CONSTITUTION.md` and are enforced by tests in `tests/governance/`.

The user-facing entry point is **[governance](governance/)** — a single skill with a verb surface:

- `governance init` — bootstrap governance-driven development into a fresh repo.
- `governance uninstall [--dry-run|--soft|--hard]` — tear down a previously bootstrapped setup with ownership-marker discipline.
- `governance pack {search,add,update,remove,list}` — install and manage community rule packs. SHA-pinned via `.governance/packs.lock`, capability-enforced (`reads:` / `writes:` globs), diff-before-exec.
- `governance rule {add,modify,remove}` — author, edit, or retire a rule as an atomic triple (rule folder + constitution subsection + Evolution Log entry, one commit).

The following per-lifecycle skills are in **retirement in progress** under issue [#31](https://github.com/Duaility/governance-kit/issues/31): they still own the authoritative flows and assets that the unified skill delegates to, and will be deleted once the flows are absorbed and assets relocated.

- **[governance-bootstrap](governance-bootstrap/)** — authoritative 8-step flow for `governance init`; owns the pack tree, templates, hook lib, and CI workflow.
- **[governance-amend](governance-amend/)** — authoritative atomic-triple flow for `governance rule {add,modify,remove}`.
- **[governance-gardener](governance-gardener/)** — not superseded. Walks the governance surface and produces a dated Governance Health Report; pairs with the `doc-freshness` rule and hands rule-shaped candidates to `governance rule *`.
- **[governance-reset](governance-reset/)** — authoritative 6-step flow for `governance uninstall`; owns the ownership-marker discipline and mode logic.

See each skill's `SKILL.md` for activation flows and references.

## After cloning

Once per fresh clone, run:

```sh
./scripts/setup-clone.sh
```

It sets `core.hooksPath=.githooks` so the governance pre-commit hook fires. Worktrees (`git worktree add ...`) inherit this config from their parent checkout — no per-worktree action needed.

## License

MIT

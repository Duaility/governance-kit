# governance-kit

A set of Claude Code skills for governance-driven development — where invariants, guidelines, and non-negotiables live in a versioned `CONSTITUTION.md` and are enforced by tests in `tests/governance/`.

Skills included:

- **[governance-bootstrap](governance-bootstrap/)** — detect the project's stack, present a menu of sane default rules, and scaffold `tests/governance/`, git hooks, a CI workflow, and a seed constitution.
- **[governance-amend](governance-amend/)** — add, edit, or remove a governance rule as a coordinated three-artifact amendment: the test script, the invariants subsection in the constitution, and an Evolution Log entry. Enforces that these land together.
- **[governance-gardener](governance-gardener/)** — periodically walk the governance surface (constitution, rule tests, git history, tracked docs) and produce a dated Governance Health Report flagging blind spots, dead rules, escape-hatch friction, three-legged drift, and stale docs. Optional follow-up actions open bump-stamp or draft-update PRs. Pairs with the `doc-freshness` rule and hands rule-shaped candidates to `governance-amend`.

See each skill's `SKILL.md` for activation flows and references.

## License

MIT

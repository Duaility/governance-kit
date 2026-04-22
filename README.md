# governance-kit

A set of Claude Code skills for governance-driven development — where invariants, guidelines, and non-negotiables live in a versioned `CONSTITUTION.md` and are enforced by tests in `tests/governance/`.

Skills included:

- **[governance-bootstrap](governance-bootstrap/)** — detect the project's stack, present a menu of sane default rules, and scaffold `tests/governance/`, git hooks, a CI workflow, and a seed constitution.
- **[governance-amend](governance-amend/)** — add, edit, or remove a governance rule as a coordinated three-artifact amendment: the test script, the invariants subsection in the constitution, and an Evolution Log entry. Enforces that these land together.
- **[doc-gardener](doc-gardener/)** — scan docs for staleness, classify as bump-only (no code drift) or needs-update (code drifted), and open remediation PRs. Pairs with the `doc-freshness` rule.

See each skill's `SKILL.md` for activation flows and references.

## License

MIT

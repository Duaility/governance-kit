### hooks-configured

- **Rule**: `.githooks/pre-commit` is tracked and executable. If `conventional-commits` is installed, `.githooks/commit-msg` likewise. `core.hooksPath` is set to `.githooks` in the repo's local git config.
- **Rationale**: Hooks that live under `.git/hooks/` are per-clone and never shared. Tracking them under `.githooks/` and pointing `core.hooksPath` at that directory is what makes every other local check actually fire on a fresh clone.
- **Enforced by**: `tests/governance/rules/hooks-configured.sh`
- **Exceptions**: Not installed when the repo uses an existing hook framework (husky, pre-commit.com) — that framework has its own tracked hook-config mechanism.

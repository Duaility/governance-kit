### ci-workflow-exists

- **Rule**: `.github/workflows/` contains at least one workflow file other than `governance.yml`.
- **Rationale**: Governance is a backstop, not the primary gate. If governance is the only workflow, the repo has no build, no tests, and no real CI — and that is a bigger problem than any single rule can flag.
- **Enforced by**: `tests/governance/rules/ci-workflow-exists.sh`
- **Exceptions**: none.

### conventional-commits

- **Rule**: Commit messages match `<type>(scope)?!?: subject (#123)`. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`.
- **Rationale**: A trailing `(#123)` anchors every commit to a GitHub issue; the typed prefix keeps changelogs scannable. Together they make `git log` a readable audit trail instead of a stream of "fix stuff".
- **Enforced by**: `tests/governance/rules/conventional-commits.sh` (also wired into the `.githooks/commit-msg` dispatcher).
- **Exceptions**: Merge and revert commits are skipped automatically.

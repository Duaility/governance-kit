### architecture-doc-exists

- **Rule**: `ARCHITECTURE.md` (at the repo root or under `docs/`) exists, is non-empty, and is at least 20 lines long.
- **Rationale**: A one-page architecture overview is the difference between a new contributor finding the right module in fifteen minutes or two hours. Short is fine; absent is not.
- **Enforced by**: `tests/governance/rules/architecture-doc-exists/check.sh`
- **Exceptions**: none.

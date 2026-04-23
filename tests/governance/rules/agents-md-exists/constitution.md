### agents-md-exists

- **Rule**: `AGENTS.md` exists at the repo root, is between 30 and 250 lines long, and contains at least three markdown links to other documents in the repo.
- **Rationale**: Agents (and humans arriving cold) need a single discoverable entry point that routes them to the rest of the system of record. Too short → useless stub; too long → nobody reads it.
- **Enforced by**: `tests/governance/rules/agents-md-exists/check.sh`
- **Exceptions**: none.

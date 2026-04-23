### env-example-current

- **Rule**: Every key in a local `.env` file also appears in `.env.example`.
- **Rationale**: `.env.example` is the onboarding contract — a new contributor copies it to `.env` and fills in values. Missing keys cause obscure runtime failures on first run.
- **Enforced by**: `tests/governance/rules/env-example-current/check.sh`
- **Exceptions**: none.

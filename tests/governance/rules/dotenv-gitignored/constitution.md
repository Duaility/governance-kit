### dotenv-gitignored

- **Rule**: `.env` is listed in `.gitignore` and is not tracked.
- **Rationale**: `.env` is where local secrets live. If it is not in `.gitignore`, one careless `git add .` leaks production credentials.
- **Enforced by**: `tests/governance/rules/dotenv-gitignored/check.sh`
- **Exceptions**: none.

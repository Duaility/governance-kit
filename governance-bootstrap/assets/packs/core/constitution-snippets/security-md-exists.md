### security-md-exists

- **Rule**: A `SECURITY.md` file exists in the repo root, `docs/`, or `.github/` and contains a contact email or URL.
- **Rationale**: External researchers need a documented, non-public channel to report vulnerabilities. A missing `SECURITY.md` routes reports to whichever issue tracker a reporter happens to find.
- **Enforced by**: `tests/governance/rules/security-md-exists.sh`
- **Exceptions**: none.

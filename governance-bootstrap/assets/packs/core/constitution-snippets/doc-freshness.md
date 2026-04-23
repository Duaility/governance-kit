### doc-freshness

- **Rule**: Docs opted into `tests/governance/freshness.conf` carry a `<!-- last-verified: YYYY-MM-DD -->` marker dated within the last 90 days (configurable). No-op if the config file is absent.
- **Rationale**: Critical runbooks and onboarding docs decay. A periodic "someone re-read this" checkpoint keeps them honest — if the deadline passes, either the doc still reflects reality (bump the date) or it doesn't (fix it).
- **Enforced by**: `tests/governance/rules/doc-freshness.sh`
- **Exceptions**: Remove a doc from `freshness.conf` to opt it out entirely.

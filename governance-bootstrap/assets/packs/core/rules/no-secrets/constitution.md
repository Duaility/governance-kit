### no-secrets

- **Rule**: No tracked file contains a plaintext AWS / GCP / GitHub / Slack / Stripe token or a private-key block matching the rule's patterns.
- **Rationale**: A leaked credential in git history is a credential compromised — rotation is the only recourse. The cheapest moment to catch it is before the commit lands.
- **Enforced by**: `tests/governance/rules/no-secrets.sh`
- **Exceptions**: For intentional fixtures or lab credentials, append `# governance: allow-no-secrets <reason>` to the line. The waiver is visible in `git blame`.

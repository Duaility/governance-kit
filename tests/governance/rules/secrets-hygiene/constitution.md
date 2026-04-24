### secrets-hygiene

- **Rule**: No tracked file violates either of the following sub-checks. Each is enabled by default and can be opted out of individually via `GOVERNANCE_SECRETS_HYGIENE_DISABLE` (comma-separated list of sub-check keys):
    - `no-secrets` — no tracked file contains a plaintext AWS / GCP / GitHub / Slack / Stripe token, private-key block, or generic `api_key = "..."` literal, per the rule's heuristic pattern set (line-level waiver: `# governance: allow-secrets-hygiene <reason>`).
    - `dotenv` — `.env` (and `.env.*` except `.env.example` / `.env.sample` / `.env.template`) is not tracked, and `.gitignore` exists and covers `.env`.
- **Rationale**: A leaked credential in git history is a credential compromised — rotation is the only recourse. `.env` is where those credentials most commonly live, so closing the door on tracking it complements the pattern scan that catches the ones that slip past into source. Treat the two as one rule: they share a failure mode and both belong on every commit.
- **Enforced by**: `tests/governance/rules/secrets-hygiene/check.sh`
- **Exceptions**: Disable individual sub-checks via `GOVERNANCE_SECRETS_HYGIENE_DISABLE="no-secrets,dotenv"`. For documented, intentional fixtures, append `# governance: allow-secrets-hygiene <reason>` to the offending line — the waiver is visible in `git blame` and searchable by design.

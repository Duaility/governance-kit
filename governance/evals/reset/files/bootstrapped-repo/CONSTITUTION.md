<!-- last-verified: 2026-01-15 -->

# Constitution

This document is the source of truth for the rules, guidelines, and invariants that govern development in this repository. Every rule here is enforced by an executable test under `tests/governance/`. A rule with no enforcing test is not a rule — it is a wish.

> **The cardinal rule:** Amendments to this constitution must land in the same commit as the change to its enforcing test. No exceptions.

## Principles

- Changes to this constitution must land with a corresponding change to the enforcing tests.
- Escape hatches exist (`SKIP_GOVERNANCE=1`, `git commit --no-verify`) — but every skipped commit is still checked in CI.

## Invariants

### constitution-exists

- **Rule**: A `CONSTITUTION.md` exists at the repo root, is non-empty, and has at least 10 lines.
- **Rationale**: Governance without a discoverable source of truth is tribal knowledge.
- **Enforced by**: `tests/governance/rules/constitution-exists/check.sh`
- **Exceptions**: none.

### no-secrets

- **Rule**: No tracked file contains AWS / GCP / GitHub / Slack / Stripe / private-key patterns.
- **Rationale**: A committed secret is a compromised secret.
- **Enforced by**: `tests/governance/rules/no-secrets/check.sh`
- **Exceptions**: Annotate intentional fixture strings with `# governance: allow-secret <reason>` on the same line.

## Evolution Log

- 2026-01-15 — @example — Initial constitution bootstrapped via governance-bootstrap.

<!-- last-verified: 2026-01-15 -->

# Constitution

This document is the source of truth for the directives that govern development in this repository. Every directive here is enforced by an executable test under `tests/governance/`. A directive with no enforcing test is not a directive — it is a wish.

> **The cardinal rule:** Amendments to this constitution must land in the same commit as the change to its enforcing test. No exceptions.

## Principles

- Changes to this constitution must land with a corresponding change to the enforcing tests.
- Escape hatches exist (`SKIP_GOVERNANCE=1`, `git commit --no-verify`) — but every skipped commit is still checked in CI.

## Directives

### constitution-exists

- **Directive**: A `CONSTITUTION.md` exists at the repo root, is non-empty, and has at least 10 lines.
- **Rationale**: Governance without a discoverable source of truth is tribal knowledge.
- **Enforced by**: `tests/governance/directives/constitution-exists/check.sh`
- **Exceptions**: none.

### no-secrets

- **Directive**: No tracked file contains AWS / GCP / GitHub / Slack / Stripe / private-key patterns.
- **Rationale**: A committed secret is a compromised secret.
- **Enforced by**: `tests/governance/directives/no-secrets/check.sh`
- **Exceptions**: Annotate intentional fixture strings with `# governance: allow-secret <reason>` on the same line.

## Evolution Log

- 2026-01-15 — @example — Initial constitution bootstrapped via governance-bootstrap.

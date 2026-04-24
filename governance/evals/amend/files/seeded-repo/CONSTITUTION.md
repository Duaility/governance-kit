# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical directives are enforced by `tests/governance/run.sh` (pre-commit hook and CI).

## Principles

- Keep changes small and reviewable.
- Every Directive has a matching test script in `tests/governance/directives/`.
- Amendments land atomically: directive + constitution + evolution-log entry in one commit.

## Directives

### no-secrets
**Directive.** No credentials or private keys in tracked files.
**Enforced by.** `tests/governance/directives/no-secrets/check.sh`
**Waivers.** `# governance: allow-no-secrets <TICKET>` on the offending line.

## Evolution Log

- 2026-01-15 — Initial bootstrap. Seeded with `no-secrets` rule. Author: fixture-owner.

# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical invariants are enforced by `tests/governance/run.sh` (pre-commit hook and CI).

## Principles

- Keep changes small and reviewable.
- Every Invariant has a matching test script in `tests/governance/rules/`.
- Amendments land atomically: rule + invariant + evolution-log entry in one commit.

## Invariants

### no-secrets
**Rule.** No credentials or private keys in tracked files.
**Enforced by.** `tests/governance/rules/no-secrets/check.sh`
**Waivers.** `# governance: allow-no-secrets <TICKET>` on the offending line.

## Evolution Log

- 2026-01-15 — Initial bootstrap. Seeded with `no-secrets` rule. Author: fixture-owner.

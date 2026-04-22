# CONSTITUTION

## Compliance
Agents and humans follow this document. Mechanical invariants are enforced by `tests/governance/run.sh`.

## Principles
- Governance artifacts stay in sync with the code.

## Invariants

### no-secrets
**Rule.** Tracked files should not contain credentials or private keys.
**Enforced by.** `tests/governance/rules/no-secrets.sh`

### agents-md-exists
**Rule.** AGENTS.md exists at the repo root.
**Enforced by.** `tests/governance/rules/agents-md-exists.sh`

## Evolution Log
- 2025-09-10 — Bootstrap with no-secrets.
- 2025-10-02 — Added agents-md-exists invariant (test script to follow — NOTE: never landed).

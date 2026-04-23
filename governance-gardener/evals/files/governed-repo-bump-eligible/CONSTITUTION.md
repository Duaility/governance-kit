# CONSTITUTION

## Compliance
Agents and humans follow this document. Mechanical invariants in `tests/governance/run.sh`.

## Principles
- Docs are stamped with a `last-verified` line and watched paths.

## Invariants

### no-secrets
**Rule.** No credentials or private keys in tracked files.
**Enforced by.** `tests/governance/rules/no-secrets/check.sh`

## Evolution Log
- 2025-08-15 — Bootstrap with no-secrets.

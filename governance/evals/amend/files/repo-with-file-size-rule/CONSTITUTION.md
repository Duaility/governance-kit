# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical invariants are enforced by `tests/governance/run.sh`.

## Principles

- Keep files small and reviewable.
- Amendments land atomically: rule + invariant + evolution-log entry.

## Invariants

### file-size-limit
**Rule.** No single tracked source file may exceed 500 lines.
**Enforced by.** `tests/governance/rules/file-size-limit/check.sh` (limit controlled by `GOVERNANCE_FILE_SIZE_LIMIT`, default 500).
**Waivers.** Append `# governance: allow-file-size-limit <TICKET>` to the first line of the file.

## Evolution Log

- 2025-11-02 — Initial bootstrap. Added `file-size-limit` rule at 500 lines. Author: fixture-owner.

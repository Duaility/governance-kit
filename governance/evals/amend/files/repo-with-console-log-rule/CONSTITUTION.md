# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical directives are enforced by `tests/governance/run.sh`.

## Principles

- Keep logs structured, not printed.
- Amendments land atomically: directive + constitution + evolution-log entry.

## Directives

### no-console-log
**Directive.** No `console.log` / `console.debug` calls in tracked `.ts` / `.tsx` / `.js` / `.jsx` files.
**Enforced by.** `tests/governance/directives/no-console-log/check.sh`
**Waivers.** `// governance: allow-no-console-log <TICKET>` on the offending line.

## Evolution Log

- 2025-10-20 — Initial bootstrap. Added `no-console-log` rule. Author: fixture-owner.

# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical directives are enforced by `.governance/run.sh` (pre-commit hook and CI).

## Principles

- Keep changes small and reviewable.
- Every Directive has a matching test script under `.governance/packs/<owner>/<name>/directives/`.
- Amendments land atomically: directive + constitution + evolution-log entry in one commit.

## Directives

### secrets-hygiene
**Directive.** No credentials, tokens, or private keys in tracked files.
**Enforced by.** `.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`
**Waivers.** `# governance: allow-secrets-hygiene <TICKET>` on the offending line.

### no-secrets
**Directive.** Repo-specific scan: block `.env*` files committed to the tree.
**Enforced by.** `.governance/packs/acme/seeded-repo/directives/no-secrets/check.sh`
**Waivers.** `# governance: allow-no-secrets <TICKET>` on the offending line.

## Evolution Log

- 2026-01-15 — Initial bootstrap. Installed `governance-kit/core` (`secrets-hygiene`) and seeded a local pack with `no-secrets`. Author: fixture-owner.

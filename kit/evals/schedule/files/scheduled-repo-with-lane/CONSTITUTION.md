# CONSTITUTION

## Compliance

Mechanical directives enforced by `.governance/run.sh`.

## Principles

- Pack provenance is tracked in `.governance/packs.lock`.

## Directives

### secrets-hygiene
**Directive.** No credentials, tokens, or private keys in tracked files.
**Enforced by.** `.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`

### license-headers
**Directive.** Every tracked source file carries the required license header.
**Enforced by.** `.governance/packs/governance-kit/core/directives/license-headers/check.sh` (schedule-only — `hook: none`)

### naming-convention
**Directive.** Local naming-convention check.
**Enforced by.** `.governance/packs/acme/local/directives/naming-convention/check.sh`

## Evolution Log

- 2026-01-20 — Initial bootstrap with `governance-kit/core@0.2` and the repo-local `acme/local` pack.

# CONSTITUTION

## Compliance

Mechanical directives enforced by `.governance/run.sh`.

## Principles

- Pack provenance is tracked in `.governance/packs.lock`.

## Directives

### secrets-hygiene
**Directive.** No credentials, tokens, or private keys in tracked files.
**Enforced by.** `.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`

### widget-naming
**Directive.** Widgets follow the `Widget*` naming convention.
**Enforced by.** `.governance/packs/acme/widgets/directives/widget-naming/check.sh`

### team-policy
**Directive.** Team-specific check authored in this repo.
**Enforced by.** `.governance/packs/acme/repo-with-installed-pack/directives/team-policy/check.sh`

## Evolution Log

- 2026-01-15 — Initial bootstrap with `governance-kit/core@0.2`.
- 2026-03-10 — Installed `acme/widgets@5f3c0a1b`.
- 2026-03-12 — Hand-authored `team-policy` added in repo-local pack.

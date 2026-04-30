# CONSTITUTION

## Compliance

Agents and humans working in this repo must read and follow this document. Mechanical directives are enforced by `.governance/run.sh`.

## Principles

- Every Directive has a matching test under `.governance/packs/<owner>/<name>/directives/`.
- Amendments land atomically (directive + constitution + evolution-log entry in one commit).
- Pack-sourced directives are kit/community owned; reset is the recovery hatch when local edits cause regressions.

## Directives

### secrets-hygiene
**Directive.** No credentials, tokens, or private keys in tracked files.
**Rationale.** Leaked secrets are the most expensive class of repo-level mistake to recover from.
**Enforced by.** `.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`
**Exceptions.** `# governance: allow-secrets-hygiene <TICKET>` on the offending line.
**LOCAL DRIFT NOTE.** Subsection edited in-place by a contributor — reset must restore the pristine text.

### widget-naming
**Directive.** Widgets follow the `Widget*` naming convention.
**Rationale.** Internal style; pinned at acme/widgets@5f3c0a1b.
**Enforced by.** `.governance/packs/acme/widgets/directives/widget-naming/check.sh`

### team-policy
**Directive.** Team-specific check authored in this repo.
**Rationale.** Local team standard; not from any pack.
**Enforced by.** `.governance/packs/acme/drifted-repo/directives/team-policy/check.sh`

## Evolution Log

- 2026-01-15 — Initial bootstrap. Installed `governance-kit/core@0.2` and `acme/widgets@5f3c0a1b`. Author: fixture-owner.
- 2026-03-12 — Hand-authored `team-policy` added in repo-local pack. Author: fixture-owner.

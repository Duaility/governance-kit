### secrets-hygiene
**Directive.** No credentials, tokens, or private keys in tracked files.
**Rationale.** Leaked secrets are the most expensive class of repo-level mistake to recover from — credentials must be rotated, dependents must be redeployed, and the leak window is not always recoverable.
**Enforced by.** `.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`
**Exceptions.** `# governance: allow-secrets-hygiene <TICKET>` on the offending line.

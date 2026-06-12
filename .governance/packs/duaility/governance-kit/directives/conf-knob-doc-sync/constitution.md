### conf-knob-doc-sync

- **Directive**: Every scalar knob a bundled directive's `check.sh` reads via `conf_get <id> <KEY> <default>` (under `packs/*/directives/*/`) must be documented in that directive's sibling `config.conf` template as a commented canonical `<KEY>=<default>` line whose value matches the literal default in the code.
- **Rationale**: Scalar defaults deliberately live as constants at the `conf_get` read site — replace-semantics knobs need no `defaults.conf` data file (only merge-semantics list directives ship one). That leaves the `config.conf` comment as the only user-facing statement of the default, with nothing tying it to the code: bumping a default in `check.sh` without touching the template would silently mis-document the knob for every consumer. This lint closes the drift channel identified in the 2026-06-12 review of the scalar-vs-list defaults design.
- **Enforced by**: `.governance/packs/duaility/governance-kit/directives/conf-knob-doc-sync/check.sh`
- **Exceptions**: Same-line waiver comment `governance: allow-conf-knob-doc-sync <reason>` on the `conf_get` line in the scanned `check.sh`.

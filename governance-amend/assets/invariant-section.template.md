### <rule-name>

- **Rule**: <one-sentence present-tense statement of what code must or must not do>.
- **Rationale**: <why this matters — link to the incident, policy, or constraint that motivates it>.
- **Enforced by**: `tests/governance/rules/<rule-name>/check.sh`
- **Exceptions**: <one of:
    - `none` — no deviations allowed.
    - `Waiver comment: # governance: allow-<rule-name> <ticket-id>` — approved deviation, per-line.
    - `Config file: tests/governance/<rule-name>.conf` — opt-in / opt-out via a tracked list.
  >

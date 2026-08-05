# scheduled-repo

Post-init repo with three installed directives, used by the `governance
schedule` evals:

- `secrets-hygiene` (`governance-kit/core`) — `hook: pre-commit`, explicit
  `triggers: [pre-commit, schedule]` — schedule-eligible.
- `license-headers` (`governance-kit/core`) — `hook: none`, explicit
  `triggers: [schedule]` — schedule-eligible, sweep-style (no commit-time
  hook at all).
- `naming-convention` (`acme/local`, a repo-local pack) — `hook: pre-commit`,
  no `triggers:` field, so its effective triggers derive to `[pre-commit]`
  only — **not** schedule-eligible until an overlay override adds `schedule`.

No `.github/workflows/governance-schedule-*.yml` lane exists yet in this
fixture. Used by the "create a lane" and "refuse an ineligible member, fix
via overlay" schedule evals.

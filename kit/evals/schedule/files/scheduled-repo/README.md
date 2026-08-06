# scheduled-repo

Post-init repo with three installed directives, used by the `governance
workflow generate` evals:

- `secrets-hygiene` (`governance-kit/core`) — `hook: pre-commit`, explicit
  `triggers: [pre-commit, schedule]`, with a non-empty `SCHEDULE_CRON` overlay —
  schedule-eligible and enrolled.
- `license-headers` (`governance-kit/core`) — `hook: none`, explicit
  `triggers: [schedule]`, with a non-empty `SCHEDULE_CRON` overlay —
  schedule-eligible, with no commit-time hook at all.
- `naming-convention` (`acme/local`, a repo-local pack) — `hook: pre-commit`,
  no `triggers:` field, so its effective triggers derive to `[pre-commit]`
  only — **not** schedule-eligible until an overlay override adds `schedule`.

No `.github/workflows/governance-schedule.yml` exists yet in this fixture.
Used by the workflow-generation and author-owned eligibility evals.

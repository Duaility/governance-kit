# Schedule flow — consumer-defined at-rest judge lanes

Scheduled lanes re-run directive checks and judgments away from the commit
path. Each lane is one generated
`.github/workflows/governance-schedule-<lane>.yml` with its own cron, explicit
members, and budget. Findings enter through the issue → agent → PR loop.

## Eligibility and membership

Schedule eligibility is author-owned and explicit:

```yaml
hook: pre-commit
triggers: [pre-commit, schedule]
```

A schedule-only directive uses `hook: none` and `triggers: [schedule]`.
Overlays cannot add or remove triggers. A named member without an explicit
`schedule` trigger is rejected by both planning and execution. Eligibility
does not enroll a directive; the generated workflow's member list does.

## Create a lane

```text
governance schedule create nightly \
  --cron "0 3 * * *" \
  --member receipt-per-issue \
  --member no-orphan-todos \
  --budget 20
```

There is no lane-wide evidence flag. The generated workflow invokes:

```text
bash .governance/run.sh --scheduled --lane nightly \
  --budget 20 receipt-per-issue no-orphan-todos
```

`schedule create` validates every member, writes or updates the workflow, and
records its managed digest. `schedule remove <lane>` removes that workflow and
its ledger rows.

## Per-directive evidence

Each member chooses its own evidence grain through fixed config:

```yaml
config:
  - name: SCHEDULE_EVIDENCE
    type: scalar
    doc: Evidence grain used by scheduled re-adjudication.
    default: commits
    tunable: false
```

Allowed values are `range` and `commits`. When omitted, `repo-state` surfaces
derive `range` and `change-set` surfaces derive `commits`. A mixed lane can
therefore evaluate one member once over the accumulated range and another
once per commit without duplicating the whole lane.

The runtime resolves the range from explicit `--range`, the lane's last digest
marker, or `--since` (default 24 hours), always ending at `HEAD`.

## Staleness advisory

A directive may declare `SCHEDULE_STALENESS_DAYS` as a positive scalar. Lane
planning compares it with the cron's conservative interval and emits a warning
when the cadence can exceed the directive's stated maximum. This is advisory;
it does not silently rewrite the consumer's schedule.

## Judge resolution and outcomes

For judge members, command resolution is:

1. the directive's author-fixed `SCHEDULE_CMD` config;
2. un-adjudicated, reported honestly and retried later.

Environment variables neither override nor supply directive config.

Mechanical `check.sh` failures fail the job because they are facts. Judge
answers do not directly fail the scheduled job: editable attestation artifacts
receive a round, while discovery findings and frozen-artifact findings go to
the lane's digest issue. An unavailable judge is never treated as PASS.

## State and deduplication

Digest labels, resume markers, and issue titles are lane-scoped, so multiple
cadences can share members without colliding. Finding markers suppress
duplicates already present in an open lane digest. With no GitHub CLI access,
the runtime still performs the work and prints the digest to stderr.

# Scheduled workflow generation

Scheduled governance is directive-owned and compiled into one managed GitHub
workflow. The source of truth is each installed directive's `directive.yaml`
and its consumer overlay; the generated workflow is an artifact, never a
second policy surface.

## Eligibility and enrollment

A directive opts into the scheduled lane explicitly:

```yaml
hook: pre-push
triggers: [pre-push, schedule]

config:
  - name: SCHEDULE_CRON
    type: scalar
    doc: Consumer-selected cadence; empty disables scheduled enrollment.
    default: ""
    tunable: true
```

Schedule-only directives use `hook: none` and `triggers: [schedule]`. A
non-empty effective `SCHEDULE_CRON` enrolls the directive; an empty or missing
value leaves it eligible but unscheduled. Overlays cannot add or remove the
author-owned `schedule` trigger, but they may set `SCHEDULE_CRON` when the
manifest marks it tunable.

## Generate the workflow

The only user-facing scheduling command is:

```text
governance workflow generate
```

The pinned kit scans every installed directive, validates its cron shape,
groups directives that share the exact same cron expression, and writes:

```text
.github/workflows/governance-schedule.yml
```

The workflow contains one GitHub `schedule` entry for each distinct cron and a
dispatcher that runs the matching member directives. A manual
`workflow_dispatch` can select one cron or run every generated cadence. If no
directive has a non-empty cadence, generation removes the managed workflow and
its install-ledger entry.

`workflow generate` is idempotent. It is the single writer of the generated
file, records the path in `.governance/install.yaml`, and refreshes the
`managed_digests` block. It also reconciles legacy generated
`governance-schedule-<lane>.yml` files from the former lane-based interface.

There is no schedule-wide budget. Every scheduled judge invocation runs unless
its own command is unavailable; the runtime reports unavailable judgments as
un-adjudicated and never guesses a verdict. The CLI's own per-call timeout and
the generated workflow's 30-minute job timeout remain in force. A timeout is
reported by GitHub as a failed job; it is not a hidden per-directive budget.

## Per-directive evidence and independent judges

Each directive keeps its own `SCHEDULE_EVIDENCE` and optional
`SCHEDULE_STALENESS_DAYS` config. When omitted, `repo-state` derives `range`
and `change-set` derives `commits`. Staleness is advisory and does not rewrite
the cron.

Every directive is judged independently. Directives that share a cron expression
share the GitHub workflow trigger, but each gets its own prompt, command
invocation, response, receipt round, and finding. There is no batching or
cross-directive judge configuration.

## Runtime behavior

The generated workflow checks out full history and invokes the installed
runtime for the selected cadence:

```text
bash .governance/run.sh --scheduled --lane <stable-cron-id> <member>...
```

The internal stable cadence id scopes resume markers, digest labels, and issue
titles. Mechanical `check.sh` failures fail the GitHub job. Judge answers do
not directly fail the scheduled job: editable receipts receive adjudication
rounds, while frozen-artifact and discovery findings enter the
`governance-schedule-<stable-cron-id>` digest issue. Findings follow the issue
→ agent → PR loop.

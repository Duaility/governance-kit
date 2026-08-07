# Judge declaration

Some directives ask whether an artifact corresponds to reality. That requires
a fresh-context model judgment against ground truth, not another grep. The kit
declares that judgment once and can execute it live (`attest`) or at rest
(`schedule`).

## Semantics-only `judge:`

`judge:` describes only the question:

```yaml
judge:
  inputs: [diff, receipt, issue]
  checks:
    - "'## What changed' faithfully describes the diff"
    - "each checked item is realized in the diff"
  gate: verdict
```

- `inputs` is a non-empty list of evidence tokens. Built-ins include `diff`,
  `receipt`, `issue`, `layer-map`, and `range-diff`.
- `checks` is a non-empty, numbered rubric.
- `gate` is `record` (default), `verdict`, or `verdict-contestable`.

No lane behavior belongs in this block. `section`, `cmd`, evidence,
cadence, and retry limits are configuration, so `packctl` rejects them under
`judge:`.

## Execution configuration

Declare lane behavior in the directive's typed `config:` registry:

```yaml
config:
  - name: ATTEST_SECTION
    type: scalar
    doc: Receipt section populated by live attestation.
    default: Audit
    tunable: false
  - name: ATTEST_CMD
    type: scalar
    doc: Judge used by the live lane; harness requests a fresh-context sub-agent.
    default: harness
    tunable: false
  - name: SCHEDULE_CMD
    type: scalar
    doc: Consumer-selected judge command used by the scheduled lane.
    default: claude -p --output-format text --model opus
    tunable: true
  - name: SCHEDULE_CRON
    type: scalar
    doc: Consumer-selected cadence; empty disables scheduled enrollment.
    default: ""
    tunable: true
  - name: JUDGE_ROUNDS
    type: scalar
    doc: Maximum live remediation rounds before escalation.
    default: 3
    tunable: true
```

`ATTEST_SECTION` and `ATTEST_CMD` are fixed because they name the live artifact
and execution contracts. `SCHEDULE_CMD` is tunable so a consumer can select a
harness available in its environment. A directive without `ATTEST_SECTION` has no
live attestation placement. `JUDGE_ROUNDS` may be tunable according to the
pack's contract. Only `tunable: true` entries accept rows from
`.governance/conf/<owner>/<pack>/<id>.conf`; environment variables are not a
configuration tier.

A judge with a `schedule` trigger must declare a non-empty command. A
non-empty `SCHEDULE_CRON` enrolls it in `workflow generate`; an empty value is
eligible but disabled. At runtime a missing command in an invalid or legacy
install is reported un-adjudicated; the environment is not a parallel
configuration tier.

## Live attestation

A `check.sh` calls `judge_attest <receipt>`. The helper reads
`ATTEST_SECTION`, resolves the declared evidence and rubric, and applies the
gate:

- `record` requires the section and a PASS/REFUTED record.
- `verdict` requires an append-only, fresh PASS adjudication round.
- `verdict-contestable` also allows a loud CONTESTED latest round.

When the harness path is pending, the helper writes a ledger row and
`attestation_remediation` tells the calling agent to spawn a fresh-context
sub-agent. Hooks never spawn agents themselves. Each pending section is handed
to its own fresh-context sub-agent.

## Scheduled re-adjudication

The scheduled runtime consumes the same `inputs`, `checks`, and `gate`, but
derives placement, command, evidence grain, and staleness from `config:`. See
[SCHEDULE_FLOW.md](SCHEDULE_FLOW.md).

## Answer grammar

Command judges receive the rendered prompt on stdin and answer on stdout:

```text
VERDICT: PASS
REASON: one line tied to evidence
FINDING: path:line — short quote — why
```

`FINDING` is used by the scheduled lane. An unreachable or failing judge is
reported as un-adjudicated; the kit never invents a verdict.

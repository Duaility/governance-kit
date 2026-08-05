# Receipt — issue #362: scheduled trigger lanes replace sweep lane and repo.conf

## Checklist

- [x] Add optional `triggers:` list to directive.yaml (author-owned eligibility; validated for hook-consistency)
- [x] Add `run.sh --scheduled` delegating to a new `schedule.sh` engine (lane-scoped labels, resume markers, digests)
- [x] Support `--evidence range|commits` (whole-interval change-set or commit-by-commit)
- [x] Enforce the outcome split: mechanical check failures fail the job; judge findings file issues and never fail the job
- [x] Add `governance schedule` routed verb (schedulelib.py plan/apply/remove + governance-schedule.template.yml)
- [x] Retire the sweep lane (sweep.sh, governance-sweep.yml, push-mode, auto-seeding) from the source trees
- [x] Retire repo.conf: batching moves to the overlay `JUDGE_GROUP=` key; judge command moves to workflow env `GOVERNANCE_JUDGE_CMD`
- [x] Rename judge cmd lane `sweep` to `schedule` and the `GOVERNANCE_SWEEP_*` env family to schedule-lane names
- [x] Update managed-tree-integrity to digest-guard generated `governance-schedule-*.yml` workflows (legacy sweep pair still exempt)
- [x] Replace SWEEP_FLOW.md with SCHEDULE_FLOW.md and update all reference docs, AGENTS.md, and the generated site pages
- [x] Adapt the test suite (test-schedule.sh, test-schedulelib.py, triggers validation) and keep scripts/test.sh green

## What changed

**Add optional `triggers:` list to directive.yaml (author-owned eligibility; validated for hook-consistency).** `kit/assets/packs/lib/packctl.py`
gains the `TRIGGER_VALUES` constants and `kit/assets/packs/lib/packvalidate.py` gains
`validate_triggers` (author-owned eligibility; validated for hook-consistency: when present with
`hook:` other than `none`, the list must contain the hook value and at most one git-hook value).
Absent `triggers:` derives `[hook]`, so no existing pack changes meaning. `schedule` in the
effective list marks the directive eligible for scheduled lanes; the consumer overrides
per repo via the overlay `TRIGGERS=` row.

**Add `run.sh --scheduled` delegating to a new `schedule.sh` engine (lane-scoped labels, resume markers, digests).**
`kit/assets/dot-governance/run.sh` recognizes `--scheduled` and delegates to
`kit/assets/dot-governance/schedule.sh` (new; derived from the deleted
`kit/assets/dot-governance/sweep.sh`). The engine takes `--lane <name>`, one or more member
tokens (bare id or owner/pack/id; unknown or ineligible members exit 2), and lane-scoped labels,
resume markers, digests: label `governance-schedule-<lane>`, resume comment
`governance-schedule:<lane>:end=<sha>`, so two lanes at different cadences never collide.
**Support `--evidence range|commits` (whole-interval change-set or commit-by-commit).** The engine takes the whole-interval change-set (mechanical members run once
with `GOVERNANCE_CHANGE_SET_BASE` at the range start) or commit-by-commit (each commit checked
in a detached worktree against its parent, judge findings prefixed with the short sha).
**Enforce the outcome split: mechanical check failures fail the job; judge findings file issues and never fail the job.** Mechanically failing members set exit 1; judge outcomes never touch the exit code. Judge resolution ladder: the directive's own
`cmd.schedule`, else the `GOVERNANCE_JUDGE_CMD` env the workflow exports, else skip honestly.

**Add `governance schedule` routed verb (schedulelib.py plan/apply/remove + governance-schedule.template.yml).** New engine
`kit/assets/packs/lib/schedulelib.py` (plan/apply/remove; member resolution and eligibility
mirror the runner; apply renders `kit/assets/governance-schedule.template.yml` — new — into a
stamped `.github/workflows/governance-schedule-<lane>.yml`, appends it to
`install_assets_seeded`, and rewrites `managed_digests`; byte-identical on re-apply), registered
on `kit/assets/packs/lib/packverb.py` via `register_schedule` (same pattern as
`register_lifecycle`).

**Retire the sweep lane (sweep.sh, governance-sweep.yml, push-mode, auto-seeding) from the source trees.** Deleted `kit/assets/dot-governance/sweep.sh` and
`kit/assets/governance-sweep.yml`. `kit/assets/packs/lib/applylib.py` drops `SWEEP_ASSETS` and
the seeding helpers (gaining the shared `append_install_assets_seeded` /
`remove_install_assets_seeded` ledger helpers); `kit/assets/packs/lib/initapply.py` and
`kit/assets/packs/lib/packapply.py` drop sweep auto-seeding — `schedule.sh` now ships
unconditionally as a kit-managed runtime file next to run.sh/lib.sh;
`kit/assets/packs/lib/digestlib.py` digests it plus every generated
`governance-schedule-*.yml`; `kit/assets/packs/lib/hooks.sh` drops the pre-push push-mode
stanza; `kit/assets/packs/lib/install.sh` comment updated.

**Retire repo.conf: batching moves to the overlay `JUDGE_GROUP=` key; judge command moves to workflow env `GOVERNANCE_JUDGE_CMD`.** `kit/assets/dot-governance/lib.sh` deletes `repo_conf_file` /
`repo_conf_get` and the repo.conf partition parsing; `_judge_group_resolve` now reads the
per-directive overlay `JUDGE_GROUP=` key (present-but-empty forces solo), falling back to the
directive's own `judge.group`; new helpers `_directive_triggers_resolve`, `_yaml_top_list`,
`_directive_overlay_file`, `_directive_overlay_get`. The committed `SWEEP_CMD=` row's job moves
to the generated workflow's `GOVERNANCE_JUDGE_CMD` env. **Rename judge cmd lane `sweep` to `schedule` and the `GOVERNANCE_SWEEP_*` env family to schedule-lane names.** Concretely: `GOVERNANCE_SCHEDULE_RANGE` replaces the old range env, plus
`GOVERNANCE_SCHEDULE_BUDGET`, `GOVERNANCE_SCHEDULE_TRUNK` (with `GOVERNANCE_SWEEP_CMD` →
`GOVERNANCE_JUDGE_CMD`); round lines record `lane=schedule`. This deliberately reverses part of
issue #355 same-day: the workflow file is now the consumer-owned home for set-level statements,
so the repo-level conf file has no remaining purpose. The stale partition pointers in
`packs/audit/directives/agent-steering-accounting/defaults.conf`,
`packs/audit/directives/receipt-per-issue/defaults.conf`, `packs/audit/pack.yaml`, and the
judge-lane prose in `packs/audit/directives/agent-steering-accounting/constitution.md`,
`packs/audit/directives/agent-steering-accounting/README.md`,
`packs/audit/directives/receipt-per-issue/constitution.md`, and
`packs/audit/directives/receipt-per-issue/check.sh` now name the overlay key and the scheduled
lane.

**Update managed-tree-integrity to digest-guard generated `governance-schedule-*.yml` workflows (legacy sweep pair still exempt).** `packs/foundation/directives/managed-tree-integrity/check.sh`
digest-guards generated `governance-schedule-*.yml` workflows via a glob-based
marker-consistency exemption (generation-time marker, like the seed-once rationale of #263),
with the legacy sweep pair still exempt on pre-retirement installs; the digest check itself
stays universal. `packs/foundation/directives/managed-tree-integrity/constitution.md` names the
new artifacts; `packs/foundation/directives/managed-tree-integrity/evals/test.sh` covers
match/tamper/marker-divergence for a schedule workflow fixture plus one legacy sweep case.

**Replace SWEEP_FLOW.md with SCHEDULE_FLOW.md and update all reference docs, AGENTS.md, and the generated site pages.** `kit/references/SCHEDULE_FLOW.md` (new) replaces the deleted
`kit/references/SWEEP_FLOW.md`; `kit/references/JUDGE.md` is rewritten for the attest+schedule
lanes and overlay batching; `kit/references/VERBS.md` gains the routed schedule verb entry;
`kit/references/PACK_AUTHORING.md` documents `triggers:`; `kit/references/DIRECTIVE_AUTHORING.md`,
`kit/references/DIRECTIVES_CATALOG.md`, `kit/references/LIB_API.md`,
`kit/references/INSTALL_SCHEMA.md`, `kit/references/INIT_FLOW.md`, and `AGENTS.md` are updated;
the generated site pages `docs/reference/authoring-directives.mdx`,
`docs/reference/authoring-packs.mdx`, `docs/reference/directive-catalog.mdx`,
`docs/reference/schemas.mdx`, `docs/reference/verbs.mdx` are regenerated
(`npm run docs:gen`, check passes) and `docs/concepts/runtime.mdx` updated by hand.

**Adapt the test suite (test-schedule.sh, test-schedulelib.py, triggers validation) and keep scripts/test.sh green.** `scripts/test-sweep.sh` renamed to `scripts/test-schedule.sh` (121 assertions incl.
eligibility exits, outcome split,
per-commit evidence, lane isolation, overlay batching); `scripts/test-schedulelib.py` (new,
17 tests); `scripts/test-packctl-triggers.py` (new; triggers validation split out to keep
`scripts/test-packctl-validate.py` under the repo-hygiene limit);
`scripts/test-packctl-subagent.py`, `scripts/test-subagent.sh`, `scripts/test-runtime.sh`,
`scripts/test-kityaml.py`, `scripts/test-init.py`, `scripts/test-packverb-apply.py` adapted to
the renames and the no-auto-seeding contract; `scripts/test.sh` wires the new layers;
`scripts/release.sh` runtime list updated; `scripts/eval-report.sh` fixed to read `kit/evals`
directly (stale pre-thin-skill path). New behavioral evals `kit/evals/schedule/evals.json` with two fixture trees, every file listed
here for coverage:
`kit/evals/schedule/files/scheduled-repo/README.md`,
`kit/evals/schedule/files/scheduled-repo/CONSTITUTION.md`,
`kit/evals/schedule/files/scheduled-repo/.governance/install.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs.lock`,
`kit/evals/schedule/files/scheduled-repo/.governance/run.sh`,
`kit/evals/schedule/files/scheduled-repo/.governance/lib.sh`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/acme/local/pack.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/acme/local/directives/naming-convention/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/acme/local/directives/naming-convention/check.sh`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/pack.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/license-headers/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/license-headers/check.sh`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/secrets-hygiene/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`,
and the same tree plus an installed lane under
`kit/evals/schedule/files/scheduled-repo-with-lane/README.md`,
`kit/evals/schedule/files/scheduled-repo-with-lane/CONSTITUTION.md`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.github/workflows/governance-schedule-nightly.yml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/install.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs.lock`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/run.sh`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/lib.sh`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/acme/local/pack.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/acme/local/directives/naming-convention/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/acme/local/directives/naming-convention/check.sh`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/pack.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/license-headers/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/license-headers/check.sh`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/secrets-hygiene/directive.yaml`,
`kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/secrets-hygiene/check.sh`.

## Out of scope

- The dogfood `.governance/` consumed tree and `.github/workflows/governance-sweep.yml` — the
  protected consumer catches up at the next release via the real `governance update` /
  `governance pack update` verbs.
- Version bumps on any axis (release-only, written by scripts/release.sh).
- A commit-path manifest for attest-lane batching (the overlay `JUDGE_GROUP=` key covers it
  per-directive; revisit only if a real repo needs set-level attest config).

## Decisions

- **The workflow file is the config.** Cadence, membership, evidence shape, and the judge env
  all live in the generated lane workflow; no lane registry, no repo-level conf. A second
  cadence is a second file; nothing coordinates lanes beyond their lane-scoped resume markers.
- **repo.conf reversal of #355, same-day.** Recorded deliberately: `judge-group`/`judge-solo`
  existed to override definitions the consumer cannot write (digest-guarded directive.yaml);
  the per-directive overlay channel already solves exactly that, and the new workflow artifact
  homes set-level statements. Stated plainly in SCHEDULE_FLOW.md's retirement section.
- **schedule.sh is kit-managed, not seed-once.** Unlike sweep.sh (seeded only when a judge
  directive installed), the engine ships unconditionally with run.sh/lib.sh and re-syncs on
  `kit update`; only the generated per-lane workflows are consumer-owned artifacts (verb-written,
  digest-guarded, marker-exempt).
- **No compatibility aliases.** V0: `cmd.sweep`, the `GOVERNANCE_SWEEP_*` envs, `--push-mode`,
  and the repo.conf grammar are deleted, not shimmed — the repo's own no-legacy-fallbacks
  directive is the stance.
- **repo-hygiene regressions fixed structurally.** packverb.py went over the 500-line limit from
  the schedule wiring — resolved by moving registration into schedulelib (`register_schedule`),
  matching the lifecycle_cli precedent; the validation tests split into
  scripts/test-packctl-triggers.py rather than waiving the limit.

## Verification

```
bash scripts/test.sh && bash .governance/run.sh
```

Full kit-internal suite green end-to-end (all layers incl. the new schedule-lane and
schedulelib layers), and the dogfood governance suite passes all 19 directives on the
working tree.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-08-05 | claude-code | 86bcefb7-a63e-4022-97b2-1a5221347a4b | - | - | - | - | - | - | unresolved |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-86bcefb7a63e-1786109631-1 | 86bcefb7-a63e-4022-97b2-1a5221347a4b | #362 | correction | classifier | Rejected the sweep-based design as vestigial; demanded a rethink toward a generated scheduled GitHub workflow | - | 55 | 2026-08-05T13:33:51Z |
| steer-86bcefb7a63e-1786112821-2 | 86bcefb7-a63e-4022-97b2-1a5221347a4b | #362 | correction | classifier | Challenged repo.conf's purpose now that the nightly/sweep lane is being retired | - | 110 | 2026-08-05T14:27:01Z |
| steer-86bcefb7a63e-1786113352-3 | 86bcefb7-a63e-4022-97b2-1a5221347a4b | #362 | correction | classifier | Questioned need for repo.conf; proposed deriving state from directive.yaml instead | - | 152 | 2026-08-05T14:35:52Z |
| steer-86bcefb7a63e-1786113605-4 | 86bcefb7-a63e-4022-97b2-1a5221347a4b | #362 | correction | classifier | Demanded rethinking repo.conf's essence against per-directive confs and the proposed design | - | 170 | 2026-08-05T14:40:05Z |
## Audit

- (1) What-changed faithfulness: PASS — every claim spot-checked against real hunks: `TRIGGER_VALUES`/`TRIGGER_HOOK_VALUES` and `validate_triggers` in `kit/assets/packs/lib/packctl.py`/`packvalidate.py`; `run.sh` gains `--scheduled` dispatch to the new 1077-line `kit/assets/dot-governance/schedule.sh` while `kit/assets/dot-governance/sweep.sh` (862 lines) and `kit/assets/governance-sweep.yml` are deleted; `schedulelib.py` defines `plan`/`apply`/`remove` plus `register_schedule`, wired into `packverb.py`; `lib.sh` replaces `repo_conf_file`/`repo_conf_get` with `_directive_overlay_get`/`JUDGE_GROUP=` and renames `GOVERNANCE_SWEEP_RANGE`→`GOVERNANCE_SCHEDULE_RANGE`; `managed-tree-integrity/check.sh` adds the `_mti_is_schedule_workflow` glob exemption alongside the retained legacy `SWEEP_ASSET_RELPATHS`; `SCHEDULE_FLOW.md` (335 lines, new) replaces `SWEEP_FLOW.md` (379 lines, deleted); `scripts/test.sh` renames layer 5b from test-sweep.sh to test-schedule.sh and adds test-packctl-triggers.py/test-schedulelib.py layers.
- (2) Checklist realized in diff: PASS — all 11 items independently verified against hunks (triggers schema, `--scheduled`/schedule.sh, `--evidence range|commits` flag parsing in schedule.sh, JUDGE_GROUP overlay + GOVERNANCE_JUDGE_CMD rename, register_schedule verb, sweep.sh/governance-sweep.yml deletion, repo.conf helper removal, managed-tree-integrity glob exemption, SCHEDULE_FLOW.md + doc updates, and the renamed/added test layers in scripts/test.sh).
- (3) Checklist mirrors issue: PASS — `gh issue view 362`'s 11 checklist lines are reproduced verbatim (only `[ ]`→`[x]`) in the receipt's `## Checklist`, same order, same wording, no additions or omissions.

## Layer boundaries

- (1) Files in their layer: PASS — the generic schedule engine (`kit/assets/dot-governance/schedule.sh`, `kit/assets/packs/lib/schedulelib.py`, `kit/assets/governance-schedule.template.yml`, `kit/references/SCHEDULE_FLOW.md`) and its shared `lib.sh`/`packctl.py`/`packvalidate.py` changes all sit under `kit/`; pack-owned content (`agent-steering-accounting`/`receipt-per-issue` `defaults.conf`/`constitution.md` prose, `managed-tree-integrity/check.sh`'s glob exemption for lane workflows, `audit/pack.yaml` floor bump) all sit under `packs/`; no kit engine logic landed under `packs/` and no pack-specific identifiers (e.g. `governance-kit/audit`, `receipt-per-issue`, `agent-steering-accounting`) appear in the generic engine/template files (`grep` for pack/directive names in `schedule.sh`, `schedulelib.py`, `governance-schedule.template.yml` returns nothing).
- (2) No inverted dependencies: PASS — no file under `kit/` references `skill/`, and the only `packs/` mentions of `kit/assets/*` paths are prose in `constitution.md` describing what the installed check delegates to, not code coupling; the arrows (skill installs kit, kit consumes packs) are unbroken by this diff.
- (3) Shared logic owned, not duplicated: PASS — the new schedule driver explicitly reuses `lib.sh`'s prompt builder/round-appender/cmd-resolver rather than re-implementing them (see `schedule.sh`'s "Locate lib.sh" comment), and the shared pack tooling addition (`schedulelib.py`) lives in the one place `ARCHITECTURE.md` names for shared pack `lib/` (`kit/assets/packs/lib/`), not copied into an individual pack.

## Steering

- (1) All steering events recorded: PASS — walked session `86bcefb7-a63e-4022-97b2-1a5221347a4b` (jsonl at `~/.claude/projects/-Users-srikanth-gitspace-governance-kit--claude-worktrees-new-session-f4b822/86bcefb7-a63e-4022-97b2-1a5221347a4b.jsonl`) for interrupts (`[Request interrupted by user`) and corrections. No interrupt markers were found anywhere in the transcript — the one substring match at line 528 is this very attestation task's own prompt text describing the directive, not a real interrupt event. Four corrections were found and recorded as rows: line 55 (13:33:51Z) "tke a step back,....the existing sweep is vestige of older implementation which will retire...now rethink from recently checked in primitieves..." — rejects the agent's just-given sweep-lane answer and redirects toward a from-scratch design; line 110 (14:27:01Z) "take a step back, nighlty lane is going to be retired....what is the purpsoe of this conf fiel?" — redirects away from the nightly-lane framing; line 152 (14:35:52Z) "why do we even need repo.conf -> the state can be deduced from directive.yamls' gight" — challenges and redirects the repo.conf approach; line 170 (14:40:05Z) "take a step rethink the essence of repo.conf, we have idividual .confs and try to think of it in terms of new changs we're proposing" — demands another rethink of repo.conf against the emerging design. All four are recorded as `correction`/`classifier` rows in `### Steering` above with `session`/`ordinal`/`timestamp` set to the transcript line and ISO timestamp of each event and `commit` set to `-` (no commit exists yet for this receipt).
- (2) No spurious rows: PASS — every other user-authored entry in the transcript is either the initial task-opening question (line 1, not a mid-task redirect), an ordinary clarifying/task message continuing the brainstorm ("okay...the idea here is...any questions?", "share your recommendations", "show me sample repo.conf", "do we have repo.conf in our repo?", "generaet a sample repo.conf for this repo", "go ahea and work on the entire plan..."), a local slash-command output (`/model`, `/compact`), or a background `<task-notification>` — none of these were recorded as rows. No tool denials were found in the transcript.

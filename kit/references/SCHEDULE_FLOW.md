# Schedule flow — consumer-defined at-rest judge lanes (issues #142, #325, #355)

Greppability is a directive's enforcement ceiling. A `check.sh` is bash + `git
grep`, exiting 0/1 — perfect for *syntactic* invariants (forbidden imports,
banned identifiers, file-shape rules), useless for the *semantic* ones about
**intent and architectural shape**: "remove the legacy fallback", "don't
bifurcate the path", "local must mirror remote". Those are the corrections a
human keeps making to agent-authored code, and they are exactly the invariants
grep cannot reach.

**Scheduled runs** answer those invariants with a model judgment that **never
touches the commit path**. A consumer defines one or more named **lanes** —
each a generated GitHub workflow, on its own cron, naming its own explicit
member directives — that invoke the ordinary runner (`run.sh --scheduled`)
over the commits accumulated since the lane's last run. Findings enter the
repo through the same door as human corrections: **issue → agent → PR**.

## Why scheduled lanes, not one sweep

A single, kit-owned cadence cannot fit every repo: a fast-moving directive
might want an hourly pass, a slow architectural rubric a nightly one, and a
noisy or expensive judge a weekly one — all in the same repo, at the same
time, without one cadence starving another of budget. Scheduling is also not
implicit: a directive being *eligible* for the lane (below) says nothing about
which lane, on what cron, actually runs it — a consumer names the members of
each lane explicitly, the same way a human decides which alerts go in which
on-call rotation. Multiple lanes coexist because their state (resume markers,
digest issues, labels) is lane-scoped from the ground up — running a
`nightly` lane and a `weekly` lane over the same directive never collides.

## The workflow *is* the config

There is no repo-level list of lanes to keep in sync with the workflows that
implement them — **the generated `.github/workflows/governance-schedule-<lane>.yml`
file is the lane's entire configuration**: its cron, its member list, its
evidence mode, its budget are all rendered into that one file by the
`governance schedule` verb. Nothing coordinates lanes with each other; adding,
changing, or removing a lane is adding, changing, or removing that one file.
Reading what runs on a schedule in this repo means reading
`.github/workflows/governance-schedule-*.yml` — there is nowhere else to look.

## The paradigm: one judgment primitive

The kit has exactly **one** semantic-judgment primitive: a rubric-framed model
judgment declared once in a directive's `judge:` block (see
[JUDGE.md](JUDGE.md) for the full schema), and
executed through a **`cmd`** — either the reserved word `harness` (a
fresh-context sub-agent the calling agent spawns) or a shell command string
piped a rendered prompt on stdin, its stdout parsed for the verdict grammar.
There is no second engine, no vendor transport, no stub judge. Attest and
schedule are two **moments** of that one judgment, not two features:

- **attest** (commit) — the live session's gate: `judge_attest`, the
  remediation loop, `gate: record` / `gate: verdict`, judged by `cmd.attest`
  (`harness` by default). Documented in
  [JUDGE.md](JUDGE.md).
- **schedule** (at rest) — the same declaration re-adjudicated off the commit
  path by `schedule.sh`, a driver that reuses the *same* `lib.sh` prompt
  builder and judges through a resolved command — the directive's own
  `cmd.schedule` (rare), else the ephemeral `GOVERNANCE_JUDGE_CMD` env the
  lane's workflow exports — there is no live session at rest for a `harness`
  judge to spawn into.

**Judges never block where they run; gates block where they read.** A
scheduled run never fails a hook or, for its judge members, the workflow job
itself. It writes: a round line into a not-yet-frozen receipt (which the
existing `gate: verdict` commit/CI gate then reads — a `REFUTED` round turns
the PR red through the *existing* gate, no new mechanism), or a finding into
the lane's digest issue (the canonical human→issue→agent→PR door) when the
receipt is already frozen on trunk or the directive has no section at all. A
directive's **mechanical** `check.sh` members are the one exception to
"judges never block": a mechanical failure is a fact, not a judgment, and
facts fail jobs — see *Outcome split* below.

**Honesty rule (same as the accounting lane, issue #355):** the resolved
judge command's first word unreachable, or the judge process failing → the
judgment is reported un-adjudicated and retried on the next run. Never a
downgraded judge, never a guessed verdict, never a keyword stub standing in
for a model.

## `triggers:` — eligibility, not membership

A directive opts *into eligibility* for the scheduled lane via an optional
`triggers:` field in `directive.yaml` — a list drawn from `pre-commit,
commit-msg, prepare-commit-msg, post-commit, pre-push, none, schedule`.
Absent `triggers:` derives `[<hook>]` (or `[]` when `hook: none`) — nothing
changes for an existing pack that has never heard of scheduling. Declaring
`schedule` in the list (alongside the directive's hook trigger, if any) makes
the directive **eligible** to be named as a lane member; it does not, by
itself, put the directive in any lane. A consumer overrides a directive's
effective triggers per repo with the overlay key `TRIGGERS=` in
`.governance/conf/<owner>/<pack>/<id>.conf` (comma-separated, e.g.
`TRIGGERS=pre-commit,schedule`) — read through the overlay tier only, with no
`defaults.conf` row required and no env tier (a single global
`GOVERNANCE_TRIGGERS` would be meaningless across directives with different
hooks).

**Eligibility ≠ membership.** A lane's workflow names its members explicitly
by directive id; naming a directive that is not eligible for `schedule`
(neither via its own `triggers:` nor an overlay override) is a configuration
error, refused loudly rather than silently skipped — both by the verb at plan
time and by the runner at run time.

Both mechanical `check.sh` directives and judge-only (`section:`-absent)
directives can be eligible and named as members — a lane is not
judge-exclusive.

## The runner: `run.sh --scheduled`

```
bash .governance/run.sh --scheduled --lane <name> [--evidence range|commits] \
    [--range A..B] [--budget N] [--dry-run] [--no-gh] <member>...
```

`run.sh` recognizes `--scheduled` and nothing more — it validates no other
flag itself and delegates whole to the engine: `exec bash
".governance/schedule.sh" run "$@"`. `run.sh` stays the one documented,
user-facing entry point; `schedule.sh` is the engine, exactly the way
`check.sh` and `lib.sh` split — there is no second entry point a consumer is
meant to invoke directly.

**Members** are positional and at least one is required: a bare `<id>`
(matches every homonym of that id across packs, the same rule `run.sh
<bare-id>` already applies) or a fully qualified `<owner>/<pack>/<id>`. A
member token matching no directive at all is a config bug and exits 2. A
matched directive whose effective triggers (overlay `TRIGGERS=`, else the
`directive.yaml` `triggers:` list, else the derived `[<hook>]`) do not include
`schedule` also exits 2, naming the directive and explaining how to make it
eligible — never a silent skip of a misconfigured member.

### Range resolution

The range a run judges resolves, in order:

1. `--range A..B`, explicit.
2. The resume marker — the end-SHA recorded in the last
   `governance-schedule-<lane>`-labeled issue's
   `<!-- governance-schedule:<lane>:end=<sha> -->` comment, read via `gh`.
   Markers and labels are **lane-scoped**, so two cadences over the same
   directive never collide or clobber each other's resume point.
3. A `--since` window (`git log --since='24 hours ago'` by default), falling
   back to the root commit on a repo with no history in that window.

End is always `HEAD`.

### Evidence: range vs commits

- **`--evidence range`** (default) — one pass over the whole resolved range.
  Mechanical members run their `check.sh` once with
  `GOVERNANCE_CHANGE_SET_BASE=<A>` exported, so a change-set-scoped directive
  measures `A..HEAD` exactly as it would at commit time; repo-state members
  run against the checkout as it sits today. Judge members adjudicate the
  range diff in one call (the `range-diff` input token,
  `GOVERNANCE_SCHEDULE_RANGE` exported — the renamed `GOVERNANCE_SWEEP_RANGE`
  the `range-diff` reader consumes).
- **`--evidence commits`** — iterate `git rev-list --reverse A..B`; for each
  commit `C` with parent `P`, mechanical members run in a `git worktree add
  --detach` checkout at `C` with `GOVERNANCE_CHANGE_SET_BASE=P` (the worktree
  is removed after), and judge members adjudicate the `P..C` diff. Findings
  are prefixed with the commit's short sha, so a per-commit lane's digest
  reads as a timeline rather than one blended diff. Budget still counts one
  unit per judge call; mechanical per-commit runs are free (no judge call, no
  budget cost).

### Outcome split — the lane's core rule

- **Mechanical `check.sh` failures are facts, and facts fail jobs.** Any
  member's mechanical check failing collects into the run's output and the
  whole run **exits non-zero** — the generated workflow job goes red, exactly
  like any other CI failure. There is nothing soft about a mechanical
  violation just because it ran on a schedule.
- **Judge `REFUTED` verdicts and findings are judgments, and judgments file
  issues.** They never fail the job — they land in the lane's digest issue,
  the same human→issue→agent→PR door the rest of the kit uses for
  discretionary corrections.
- **Un-adjudicated results** — no judge resolved a command, a run went over
  budget, an answer came back malformed — are reported in the digest as
  *not a clean bill*, and the run still exits 0 for that portion. A digest
  must never silently read as clean when work was actually skipped.

### The judge resolution ladder (scheduled)

A short, three-rung ladder, resolved **per directive**, not per driver:

1. **The directive's own `cmd.schedule`.** A rare per-directive override
   (`_judge_cmd_resolve <yaml> schedule`; `JUDGE_CMD_LANES = {attest,
   schedule}` — the lane key renamed from `sweep`, no compatibility alias).
   No bundled `governance-kit/*` directive declares one.
2. **The ephemeral `GOVERNANCE_JUDGE_CMD` env.** Exported by the lane's
   generated workflow from a gated repository variable before it runs
   `schedule.sh` — this is how a bundled pack is judged in practice, since no
   bundled directive sets `cmd.schedule`.
3. **Skip, honestly.** Neither rung resolved: the directive is skipped for
   this run with one log line naming the env as the way to supply a judge —
   not an error, not a fallback to some other command.

The old repo-level `SWEEP_CMD=` rung — a committed row in
`.governance/conf/repo.conf` — is **deleted**, not renamed; see *What was
retired and why* below. `GOVERNANCE_JUDGE_CMD` is itself a rename of
`GOVERNANCE_SWEEP_CMD`, kept as the single remaining ephemeral override.

A batched `group` (below) runs its members' shared *resolved* command exactly
once for the whole batch; every member must resolve to the same command,
whether that resolution came from rung 1 or rung 2. A group whose members
resolve to different commands is refused whole, reported un-adjudicated with
one honest line, rather than silently invoking a subset.

### Batching: the overlay `JUDGE_GROUP=` key

Batching moved off any repo-level partition file entirely. `_judge_group_resolve`
resolves, per directive:

1. The overlay row `JUDGE_GROUP=<label>` in
   `.governance/conf/<owner>/<pack>/<id>.conf` — present but with an **empty**
   value forces solo, even if the directive's own `directive.yaml` declares a
   `group` default.
2. `directive.yaml`'s own `judge.group`, when the overlay names no row at
   all for this directive.
3. Solo.

Every member of a resolved group must still resolve to the same judge
command; a mismatch is refused whole, the same as before. The old
ambiguity/double-claim machinery — a directive named by conflicting
`judge-group` lines in `repo.conf` — is deleted along with the file it
belonged to: a per-directive overlay key cannot itself be ambiguous.

### Budget

`GOVERNANCE_SCHEDULE_BUDGET` caps judge calls per run (default 20, the
renamed `GOVERNANCE_SWEEP_BUDGET`). Items over budget are reported
un-adjudicated in the digest footer, prioritized newest-first.

### Digest and receipt mechanics

Ported from the sweep engine unchanged except for lane-scoping:

- One GitHub issue per run when there are findings, labelled
  `governance-schedule-<lane>` (created idempotently), titled `Governance
  schedule[<lane>]: …`.
- The same `FINDING:` grammar, `_judge_cmd_run` contract, and dedupe markers
  (a finding whose (directive, file) pair already appears in an open issue
  for that lane is deduped, not repeated).
- The same frozen-receipt routing: a re-adjudication of a receipt already
  frozen on trunk routes to the digest instead of writing a round, since
  there is no editable artifact left to write into.
- The same round-append mechanics for attestation-backed directives, with
  `lane=schedule` recorded in the round line in place of the old `lane=sweep`.
- A footer records the range judged, counts of judged / un-adjudicated /
  deduped findings, and the end-SHA resume marker for that lane.

No `gh` on `PATH` (or `--no-gh`) degrades every `gh`-backed step rather than
failing: no resume marker (falls to the `--since` window), no dedupe, and the
digest prints to stderr instead of filing an issue. `--dry-run` runs the same
judging pass without staging any receipt round or filing anything.

## The verb: `governance schedule create|remove|list`

- **`governance schedule create <lane> --cron <expr> --members <id>...`
  [`--evidence range|commits`] [`--budget N`]** — routed to `packverb.py
  schedule-plan` (resolve members, validate eligibility, render a preview,
  detect an existing file to overwrite) then `packverb.py schedule-apply`
  (render `governance-schedule.template.yml` with the resolved values, stamp
  the `# governance-kit:managed kit-version=<v>` marker, write
  `.github/workflows/governance-schedule-<lane>.yml`, append to
  `install_assets_seeded` if new, rewrite the `managed_digests` block).
  Idempotent: identical inputs render a byte-identical file.
- **`governance schedule remove <lane>`** — deletes the lane's workflow file,
  drops its `install_assets_seeded` / `managed_digests` rows, re-digests.
- **`governance schedule list`** — enumerates the lanes currently on disk by
  reading the generated workflow files (or the ledger rows), no separate
  index to fall out of sync.

The verb is the **single writer** for every generated schedule workflow — the
same discipline every other kit-managed file follows. A hand-edit to
`governance-schedule-<lane>.yml` changes its digest and trips
`managed-tree-integrity` offline, in any repo, the same way a hand-edit to
`run.sh` or `lib.sh` does. See [VERBS.md](VERBS.md) for the routed-verb entry
and its install-state keys.

## What was retired and why

Scheduling replaces three pieces that existed before this lane, each retired
for a specific reason rather than folded in disguised as something else:

- **The sweep lane** (`.governance/sweep.sh` + the single
  `governance-sweep.yml` workflow) — a single, kit-owned cadence with no
  per-directive membership: every eligible directive swept together, on one
  schedule, with no way for a repo to run one rubric hourly and another
  weekly, or to point one lane at a stronger judge than another. Scheduling
  generalizes the same driver into named, consumer-configured lanes with
  explicit membership, their own cadence, and their own evidence mode —
  everything the sweep lane did, but no longer singular.
- **`.governance/conf/repo.conf`** (landed the same day as issue #355,
  retired the same day by this change) — the file carried exactly two kinds
  of row: `judge-group` / `judge-solo` batching partitions, and a `SWEEP_CMD=`
  judge choice. Both were repo-level statements bolted onto a per-directive
  conf mechanism that otherwise never had a repo-level file. Scheduling gives
  each of those statements the home it actually needed: a **set-level**
  statement ("these directives run on this cadence, judged by this command")
  now lives in the workflow file itself — the consumer-owned artifact that
  was always going to need one — so `repo.conf` has nothing left to say. The
  batching half re-homes to the per-directive conf overlay's `JUDGE_GROUP=`
  key, consistent with every other operator-tunable field on that ladder; the
  command half re-homes to the generated workflow's own
  `GOVERNANCE_JUDGE_CMD` export. This is a deliberate reversal of part of
  #355, made explicit rather than left as an unexplained deletion: the
  scheduling design gives set-level statements a consumer-owned artifact, and
  once that artifact exists, a second repo-level file saying the same things
  in a different grammar is redundant, not complementary.
- **Push-mode** (`--push-mode`, `GOVERNANCE_PUSH_RANGE`,
  `GOVERNANCE_SWEEP_ON_PUSH`, and the pre-push dispatcher stanza that wired
  it) — an opt-in, judge-on-push tightening that inherited whatever the
  developer's shell happened to export, which was usually nothing. A
  consumer who wants a tighter feedback loop than the default resume-window
  cadence names a shorter `--since` window or a faster cron on a dedicated
  lane instead — the same mechanism that already exists, rather than a
  second, hook-triggered path with its own range-resolution rules to keep in
  sync. `GOVERNANCE_SWEEP_TRUNK` (the frozen-on-default-branch notion
  `doc-integrity` also uses) survives, renamed `GOVERNANCE_SCHEDULE_TRUNK`.

## See also

- [JUDGE.md](JUDGE.md) — the `judge:` declaration schema, shared verbatim by
  both lanes.
- [VERBS.md](VERBS.md) — the routed `schedule` verb entry.
- [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) — the per-directive table,
  including the repo-local scheduled-only directives.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — authoring a
  scheduled-only directive (a `judge:` block with no `section:`, plus a
  rubric-quality `checks:` list).
- [LIB_API.md](LIB_API.md) — the `lib.sh` helpers `schedule.sh` reuses, and
  the `FINDING` grammar / `_judge_cmd_run` contract.
- [PACK_AUTHORING.md](PACK_AUTHORING.md) — the `triggers:` field and the
  `judge:` schema's `cmd.schedule` / `group` rows.
- [PHILOSOPHY.md](PHILOSOPHY.md) — the stance behind the lane.

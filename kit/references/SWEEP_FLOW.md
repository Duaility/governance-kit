# Sweep flow — the harness-pegged at-rest judge (issues #142, #325, #355)

Greppability is a directive's enforcement ceiling. A `check.sh` is bash + `git
grep`, exiting 0/1 — perfect for *syntactic* invariants (forbidden imports,
banned identifiers, file-shape rules), useless for the *semantic* ones about
**intent and architectural shape**: "remove the legacy fallback", "don't
bifurcate the path", "local must mirror remote". Those are the corrections a
human keeps making to agent-authored code, and they are exactly the invariants
grep cannot reach.

The **sweep** lane answers those invariants with a model judgment that **never
touches the commit path**. A driver — `.governance/sweep.sh` — runs at rest (a
scheduled workflow, or an opt-in push-time hook) and re-adjudicates the same
rubric a directive already declares for its commit-time attestation, through
a resolved sweep judge command — typically a stronger, more expensive judge
than the attest lane's default. No bundled directive fixes that command
itself; it comes from the committed `SWEEP_CMD=` row in
`.governance/conf/repo.conf`, or the ephemeral `GOVERNANCE_SWEEP_CMD` env,
unless one directive genuinely overrides it (see
[Judge resolution](#judge-resolution-per-directive-not-per-driver) below).
Findings enter the repo through the same door as human corrections:
**issue → agent → PR**.

## The paradigm: one judgment primitive

The kit has exactly **one** semantic-judgment primitive: a rubric-framed model
judgment declared once in a directive's `judge:` block (see
[JUDGE.md](JUDGE.md) for the full schema), and
executed through a **`cmd`** — either the reserved word `harness` (a
fresh-context sub-agent the calling agent spawns) or a shell command string
piped a rendered prompt on stdin, its stdout parsed for the verdict grammar.
There is no second engine, no vendor transport, no stub judge. Attest and
sweep are two **moments** of that one judgment, not two features:

- **attest** (commit) — the live session's gate: `judge_attest`, the
  remediation loop, `gate: record` / `gate: verdict`, judged by `cmd.attest`
  (`harness` by default). Documented in
  [JUDGE.md](JUDGE.md).
- **sweep** (at rest) — the same declaration re-adjudicated off the commit
  path by `sweep.sh`, a driver that reuses the *same* `lib.sh` prompt builder
  and judges through a resolved sweep command — the directive's own
  `cmd.sweep` (rare), else the ephemeral `GOVERNANCE_SWEEP_CMD` env, else the
  committed `SWEEP_CMD=` row in `.governance/conf/repo.conf` — a shell
  command string only; there is no live session at rest for a `harness`
  judge to spawn into.

**Judges never block where they run; gates block where they read.** The sweep
never fails a hook or a workflow job. It writes: a round line into a
not-yet-frozen receipt (which the existing `gate: verdict` commit/CI gate then
reads — a sweep `REFUTED` turns the PR red through the *existing* gate, no
new mechanism), or a finding into the `governance-sweep` digest issue (the
canonical human→issue→agent→PR door) when the receipt is already frozen on
trunk or the directive has no section at all.

**Honesty rule (same as the accounting lane, issue #355):** `cmd.sweep`'s
first word unreachable, or the judge process failing → the judgment is
reported un-adjudicated and retried later. Never a downgraded judge, never a
guessed verdict, never a keyword stub standing in for a model.

## Why off the commit path

A false positive on the commit path is catastrophic: one wrong block →
`--no-verify` → *every* directive (including the solid greps) is bypassed. Put
the judge on a schedule instead and that failure mode dissolves rather than
needing to be solved — a noisy verdict costs a triage, not the gate's
authority. Determinism and latency relax from hard requirements to hygiene.
This mirrors the harness-engineering split: mechanical linters enforce
structure synchronously; background tasks scan for semantic deviations on a
schedule and open targeted work items. There is no blocking path in the sweep
lane itself — a `REFUTED` sweep round only turns a commit red through a
directive that *already* opted into `gate: verdict` on the commit path;
promoting a purely-discovery directive to a gate is a separate, later decision.

## The declaration: nothing new to author

A sweep directive is not a separate contract with its own folder shape. It is
a directive that carries a `judge:` block whose sweep judge resolves to a
non-empty command — either its own `cmd.sweep` row (rare) or, the norm for
every bundled directive, the ephemeral `GOVERNANCE_SWEEP_CMD` env or the
committed `SWEEP_CMD=` row in `.governance/conf/repo.conf` — see
[JUDGE.md](JUDGE.md) for the full field set
(`inputs`, `checks`, `group`, `section`, `gate`, `cmd`).
Two shapes matter here; both are ordinary `judge:` declarations,
distinguished only by whether `section:` is present (issue #355 deleted the
separate `sink` field this used to be spelled with — `sink` duplicated what
`section` presence already said, and `sink: none` misnamed a sink that
actually files a GitHub issue):

- **`section:` absent** — a **sweep-only discovery directive**: no
  commit-lane gate, no `check.sh` required at all, no `surface:` required.
  The sweep judges the range diff (the new `range-diff` input token) against
  `checks`; findings go straight to the digest issue. This is the shape both
  repo-local dogfood directives (`no-legacy-fallbacks`, `no-path-bifurcation`)
  use — see [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md).
- **`section:` present + any `gate`** — attestation-backed: the sweep
  re-adjudicates the recorded section, through the resolved sweep command,
  for every receipt the swept range touched.

Every kit-bundled directive ships a sweep-only rubric (no `section:`)
alongside its mechanical `check.sh` — the two are not alternatives.
`check.sh` proves the artifact is internally well-formed; the `checks:`
rubric names the *intent* behind the rule that a grep structurally cannot see
(whether a waiver's reason is genuine, whether a suppression's scope is
proportionate, whether a commit subject honestly names what it did) and hands
it to the sweep lane. Bundled directives declare no `group` default (see
[JUDGE.md](JUDGE.md)), so a sweep run costs one judge call per participating
bundled directive — each reading the range with only its own rubric in
context — unless the repo has opted into batching. `group` resolves per
directive from the committed, repo-level batching partition in
`.governance/conf/repo.conf` — `judge-group <label> <member>...` /
`judge-solo <member>...` lines, `judge-solo` beating `judge-group` beating a
directive's own declared `judge.group` beating solo. A repo that would
rather pay one call for a set of directives names them in one `judge-group`
line, no pack ownership required; full field grammar, member-token matching,
and the double-membership warn-and-degrade rule are in [JUDGE.md](JUDGE.md).
Repo-local and community packs still author
standalone discovery directives the same way — a `judge:` block with no
`section:` and no `check.sh` at all — for invariants that have no mechanical
half whatsoever.

Declaring no `cmd.sweep` row does **not**, by itself, opt a directive out of
the sweep lane — the `GOVERNANCE_SWEEP_CMD` env or the committed `SWEEP_CMD=`
row in `.governance/conf/repo.conf` still supplies the judge, and this is the
default posture for every bundled directive. A directive is swept whenever
*any* rung of the resolution ladder yields a command; it is skipped for a
given run only when every rung is absent (see
[Judge resolution](#judge-resolution-per-directive-not-per-driver) below). It
still attests at commit time regardless (if it declares a `cmd.attest` or
defaults to `harness`). There is no separate authoring format, no parallel
rubric to keep in sync with `constitution.md`, and no `triage.sh` to write:
`checks:` *is* the rubric, for both lanes.

## The driver — `.governance/sweep.sh`

```
sweep.sh run   [--range A..B] [--push-mode] [--dry-run] [--no-gh]
               [--since '<git date expression>']
sweep.sh usage   # default; exit 2
```

A bash + POSIX-awk script, no python, sourcing the repo's `lib.sh` — the same
dependency posture as the rest of the commit path. `run` never fails the
caller: every error condition (no cmd, no range, nothing to judge) prints
one honest line and exits 0.

### Judge resolution: per directive, not per driver

There is no driver-level adapter to pick — the old resolution ladder (env
override, live-harness detection, `can-judge` probing) is gone. What replaces
it is a short, four-rung ladder the driver runs **per directive** — not the
old per-driver adapter selection, and there is nothing left to auto-detect.
One sentence covers the shape: within the repo layer, the file
(`.governance/conf/repo.conf`) is the committed truth and the env is the
ephemeral override; the author's `cmd.sweep` floor beats both.

1. **The directive's own `cmd.sweep`.** A rare per-directive override
   (`_judge_cmd_resolve <yaml> sweep`). No bundled `governance-kit/*`
   directive declares one — bundled directives carry no `cmd` row at all.
2. **The ephemeral `GOVERNANCE_SWEEP_CMD` env.** A one-shot override for the
   run — a CI secret, a developer's own shell.
3. **The committed `SWEEP_CMD=` row in `.governance/conf/repo.conf`.** The
   repo's own standing choice of judge — this is how a bundled pack is judged
   in practice once a repo has written the row. The scheduled sweep workflow
   also sets `GOVERNANCE_SWEEP_CMD` from a gated repository variable before
   invoking `sweep.sh run` (rung 2, above this rung); the opt-in pre-push
   hook (below) inherits whatever the developer's own shell environment has,
   which is usually unset, so the `repo.conf` row is what carries the
   command on that path.
4. **Skip, honestly.** Nothing resolved at any rung.

No rung resolving leaves the directive with no judge:

- **No `cmd.sweep`, no `GOVERNANCE_SWEEP_CMD`, and no `SWEEP_CMD=` row** —
  the directive is skipped with one log line for this run, naming both the
  env and the `repo.conf` row as the ways to supply a judge. Not an error,
  and not a fallback to some other command.
- **The first word of the resolved command missing from `PATH`**, or the
  judge process failing or answering something unparseable, leaves that
  directive un-adjudicated for this run (honest stderr line, retried on the
  next run) — never a downgraded or guessed verdict.
- A batched `group` (see below) runs its members' shared *resolved* command
  exactly once for the whole batch — every member must resolve to the same
  command, whether that resolution came from rung 1, 2, or 3.

### Range resolution

For `sweep.sh run`, the swept range resolves in order:

1. `--range A..B`, explicit.
2. `--push-mode` — the range comes from `GOVERNANCE_PUSH_RANGE`, which the
   pre-push dispatcher sets from the pushed refs (`<remote-sha>..<local-sha>`;
   an all-zero remote sha resolves to the merge-base with the remote's default
   branch, or the root commit for a brand-new branch).
3. The resume marker — the end-SHA recorded in the last `governance-sweep`
   digest issue's body (an HTML-comment marker), read via `gh`. No committed
   state file. `gh` missing or unauthenticated falls through to 4.
4. A `--since` window (`git log --since='24 hours ago'`), falling back to the
   root commit on a repo with no history in that window.

### What one run does

1. **Discover participating directives** — every `directive.yaml` under the
   installed pack tree (or the source tree, for this repo's own dogfood
   loop) carrying a `judge:` block whose sweep judge resolves to a
   non-empty shell string through the four-rung ladder above (that
   directive's own `cmd.sweep`, else `GOVERNANCE_SWEEP_CMD`, else the
   `repo.conf` `SWEEP_CMD=` row). With the bundled packs' directives
   declaring no `cmd`, this step resolves them all to whichever of the env or
   the `repo.conf` row answers, or drops them for the run when neither does.
2. **Attestation-backed directives** (`section:` present): for every
   `receipts/*.md` touched in the range, skip a receipt that already exists on
   trunk (`GOVERNANCE_SWEEP_TRUNK`, or the first resolvable of `origin/HEAD`,
   `origin/main`, `origin/master`, `main`, `master` — the same frozen-on-default-
   branch notion `doc-integrity` uses) — its re-adjudication routes to the
   digest instead of writing a round, since there is no editable artifact left
   to write into. For an editable receipt,
   the driver builds the same prompt `cmd.attest` shell judges build, runs
   `_judge_cmd_run` against that directive's resolved sweep command, and
   appends the returned round via the same round-appending and stamping
   helpers the commit path uses — without staging or committing anything; the
   next real commit picks the round up.
3. **Discovery directives** (`section:` absent): the `group` label a directive
   resolves (from `.governance/conf/repo.conf`'s `judge-group` / `judge-solo`
   partition, falling back to `directive.yaml`'s own declared default — see
   [JUDGE.md](JUDGE.md)) batches every directive resolving to that same label
   into **one** judge call against the whole range diff (the `range-diff`
   input, fenced and size-capped) — a one-member group degrades to a plain
   single-directive call, so the unbatched prompt and answer grammar are
   unchanged. A directive resolving no `group` gets its own solo call.
   Batching keys on the resolved `group` label, and every member of a group
   must **resolve** to the identical sweep command — a group whose declared
   `cmd` rows disagree is a `packctl` validation error at author time, but
   that check only sees `directive.yaml`, not `repo.conf`: a group assembled
   by a `judge-group` line (which can pull bundled directives into a group
   they shipped with no label at all) is invisible to `packctl` and can only
   be caught at runtime. If its members resolve to
   different sweep commands anyway, the driver refuses to split it: the whole
   group is reported un-adjudicated with one honest line rather than silently
   invoking a subset. A directive named by `judge-group` lines carrying
   different labels is reported ambiguous and swept solo, the same degrade the attest lane
   applies. Findings route to the digest, tagged by directive.
4. **Digest** — one GitHub issue per run when there are findings, labelled
   `governance-sweep` (created idempotently; a label-creation failure files
   the digest unlabeled with a warning rather than dropping findings). One
   section per directive: file, line, quote, why. A footer records the swept
   range, counts of judged / un-adjudicated / deduped findings, and the
   end-SHA resume marker. A finding whose (directive, file) pair already
   appears in an open `governance-sweep` issue is deduped, not repeated.
5. **Budget** — `GOVERNANCE_SWEEP_BUDGET` caps judge calls per run (default
   20; `--push-mode` defaults to 3, since that path runs inline with a human
   waiting on a push). Items over budget are reported as un-adjudicated in the
   digest footer, prioritized newest-first. A digest must never silently read
   as a clean bill.

No `gh` on `PATH` (or `--no-gh`) degrades every `gh`-backed step rather than
failing: no resume marker (falls to the `--since` window), no dedupe, and the
digest prints to stderr instead of filing an issue. `--dry-run` runs the same
judging pass without staging any receipt round or filing anything, for a
before-you-commit-config preview.

### The findings contract

`_judge_cmd_run`'s normalized output — `VERDICT: PASS|REFUTED` then zero
or more `REASON:` lines — grows one optional, repeatable line, only ever
emitted after `VERDICT`/`REASON`:

```
VERDICT: PASS|REFUTED
REASON: <one line>
FINDING: <path>:<line> — <short quote> — <why>
```

`FINDING` lines get the same normalization every line gets in
`_judge_emit_verdict`: stripped of carriage returns, printable ASCII only,
capped in length. The commit-lane caller ignores `FINDING` lines entirely —
attest never changes behavior because sweep grew a richer grammar.

## Hook wiring: opt-in push mode, never blocking

Judging costs minutes, so hooks stay fast by default: nothing changes at
commit or push time unless an operator opts in. Setting
`GOVERNANCE_SWEEP_ON_PUSH=1` makes the generated pre-push dispatcher compute
the push range from the pre-push stdin refs and run
`bash .governance/sweep.sh run --push-mode` with `GOVERNANCE_PUSH_RANGE`
exported. Its exit status is always ignored — the push itself is never
gated — and it prints what it did. `GOVERNANCE_SWEEP_CMD` on this path is
whatever the developer's own shell has — typically unset, in which case
push-mode sweeping falls through to the committed `SWEEP_CMD=` row in
`.governance/conf/repo.conf` when the repo has written one, or resolves no
judge otherwise, and every un-overridden directive is skipped with an honest
line rather than silently no-oping the whole run. The scheduled workflow
remains the standing lane where a sweep judge is reliably set (it exports
`GOVERNANCE_SWEEP_CMD`); push mode is a tightening an operator can layer on
top — via a committed `repo.conf` row, which travels with every checkout, or
by exporting the env locally — so a `REFUTED` round has a chance to land
while the receipt is still editable, rather than waiting for the next
scheduled run.

## The workflow: consumer brings the judge

`.governance/sweep.sh` and the scheduled workflow ship in the kit, but the kit
does **not** ship a judge — that would mean bundling a vendor credential or a
fake one. No bundled directive names a judge in its own `cmd.sweep`; the
judge for the whole bundled set is the single `GOVERNANCE_SWEEP_CMD` value
the workflow exports, so the workflow's job is twofold: make sure the CLI
that command invokes (and its credential) exist on the runner, and set
`GOVERNANCE_SWEEP_CMD` before `sweep.sh run` executes. The workflow
(`governance-sweep.yml`, daily cron + `workflow_dispatch` with a `range`
input) gates on a repository variable that opts the lane in (and supplies the
command string) and a matching secret carrying the credential; if either is
absent the install step prints one honest line and the run exits 0 without
judging anything — the workflow never fakes a judge. When both are present it
installs the CLI the configured command names, exports `GOVERNANCE_SWEEP_CMD`
from the gated variable, and runs `sweep.sh run`, which then resolves each
participating directive's judge through the four-rung ladder above — the
workflow itself never needs to know which directive uses which command, only
that a repo-level fallback (its own `GOVERNANCE_SWEEP_CMD` export, or a
committed `repo.conf` row) is in place for the ones that declare none. The
permission surface is `contents: read` + `issues: write` only — no
model-inference permission grant, because the workflow itself never calls an
inference API; the CLI it installs does, using the consumer's own credential.

## What was deleted and why

Issue #355 retired the entire vendor-transport engine in favor of the
harness-pegged driver above, and its later Phase 3 (the `cmd` collapse)
retired the resolution machinery that engine's replacement had grown:

- **The GitHub Models transport and its free-tier inference call** — a
  zero-secret path is not worth keeping once it means a *second* judging
  mechanism alongside the harness CLI the commit lane already has. One
  mechanism, reused twice, beats two mechanisms that must be kept
  semantically identical by hand.
- **The echo/keyword-heuristic judge and its calibration fixtures** — a
  keyword grep standing in for "the judge" undersold what this lane claims to
  do. A stub that always says the same thing about the same words is not a
  judge; deleting it removes the temptation to treat its precision/recall
  numbers as if they said anything about the real one.
- **`surface: sweep` as a directive surface value** — sweep participation is
  now entirely a property of the `judge:` block (does it declare a
  `cmd.sweep`), not a separate surface a directive opts into. A directive's
  surface is `repo-state` or `change-set`; whether it also sweeps is
  orthogonal.
- **The `triage.sh` grep-prefilter contract** — the prefilter existed because
  the old engine had no repository access of its own past a raw diff. A
  `cmd.sweep` process has git and the whole repo; it takes the range diff
  directly and needs no candidate-hunk narrowing step in front of it.
- **`engine: llm` / `model_tier:` as directive.yaml scalar fields**, and later
  the `tiers:` vocabulary and its `SUBAGENT_TIERS_ATTEST`/`_SWEEP` conf
  overrides that replaced them — all folded into `cmd.attest` / `cmd.sweep`,
  which name the judge (model, effort, everything) directly instead of
  indexing into a tier→model alias table.
- **The driver-level adapter-resolution ladder** (`GOVERNANCE_SWEEP_ADAPTER`,
  live-harness detection, the `can-judge` probe order) — each directive now
  names its own judge in `cmd.sweep`; there is nothing left for the driver to
  resolve.
- **The `SUBAGENT_EXECUTOR` / `cli:<adapter>` commit-lane knob**, its
  `SUBAGENT_MODELS_LOW`/`_MEDIUM`/`_HIGH` overrides, and the adapter `judge` /
  `can-judge` verbs those relied on — collapsed into `cmd.attest` and
  `_judge_cmd_run` in `lib.sh`. Adapters (`.governance/runtimes/*.sh`)
  now answer only the accounting verbs (`resolve` / `emit`); judging never
  goes through an adapter file.
- **`isolation: shared|isolated`** — replaced by the optional `group:` label:
  same label batches into one judge call, no label runs solo. Batching keys
  on the label (and the requirement that every member of a group shares one
  `cmd`), not on a shared/isolated boolean.

## See also

- [JUDGE.md](JUDGE.md) — the `judge:`
  declaration schema, shared verbatim by both lanes.
- [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) — the per-directive table,
  including the two repo-local sweep-only directives.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — authoring a sweep
  directive (a `judge:` block with no `section:`, plus a rubric-quality
  `checks:` list).
- [LIB_API.md](LIB_API.md) — the `lib.sh` helpers `sweep.sh` reuses, and the
  `FINDING` grammar / `_judge_cmd_run` contract.
- [PHILOSOPHY.md](PHILOSOPHY.md) — the stance behind the lane.

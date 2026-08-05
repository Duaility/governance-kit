# Judge declaration (attest + schedule)

Some directives ask a question a hook structurally cannot answer: *does this
artifact correspond to reality* — does the receipt match the diff, does the
change honor a declared architectural invariant, did the agent record every time
the operator steered it? Answering needs a **fresh-context model judgment**
against ground truth, not a string relationship a `check.sh` can re-execute.

The kit expresses every such judgment as **one declaration** — a `judge:`
block in the directive's `directive.yaml` — executed by **one mechanism** at two
lanes and two times (issues #325, #355):

| | **attest** (commit) | **schedule** (at rest) |
|---|---|---|
| does | renders a verdict on a rubric | re-renders a verdict on the same rubric |
| judge | `cmd.attest` — `harness` (a fresh-context sub-agent the calling agent spawns, the default; no bundled directive overrides it) or a shell command string | resolved through a ladder: the directive's own `cmd.schedule` (a rare override), else the ephemeral `GOVERNANCE_JUDGE_CMD` env (exported by the lane's generated workflow), else the directive is skipped honestly |
| result | verdict written into a `## Section` | a round line appended to the section (attestation-backed) or a `FINDING` filed to the lane's `governance-schedule-<lane>` digest issue (discovery, or a frozen receipt) |

The two are the same task — a rubric-framed model judgment — executed through
**one mechanism**: a `cmd` the framework pipes a rendered prompt into on
stdin, parsing the verdict grammar off stdout. There is no second engine, no
vendor transport, no stub judge — attest and schedule are two **moments** of
one `judge:` declaration, not two parallel features. This page covers the
**attest** mode (the commit lane). The **schedule** mode is in
[SCHEDULE_FLOW.md](SCHEDULE_FLOW.md); the at-rest driver reads the same
declaration unchanged and re-derives the verdict through `cmd.schedule`, off
the commit path.

First shipped for `receipt-per-issue`'s `## Audit` (issue #272); the consumers
today are `## Audit`, the repo-local `layer-boundaries` `## Layer boundaries`
(issue #277), and `agent-steering-accounting`'s `## Steering` (issue #325, which
replaced an in-hook `claude -p` classifier with a batched attestation).

## The problem it solves

A form-checked directive proves an artifact is *internally consistent* — its
`check.sh` re-executes a relationship between strings the artifact already
carries. It cannot prove the artifact *corresponds to reality*, because the
ground truth (the diff, the linked issue, the session transcript) is exactly
what a pre-commit hook does not read. `receipt-per-issue`'s checklist crosswalk
is the canonical example: it confirms each `- [x]` item is echoed in the
receipt's own prose, never that either matches the diff.

Closing that gap needs an **independent reader** of the ground truth. The
attestation is an **author-time** independent audit, recorded into the artifact
and gated for *presence*, with the truth of its verdict deferred to the
schedule lane at merge. The independence is the point: a sub-agent handed only the ground
truth — never the code-author's reasoning — is a genuinely independent auditor.
That is the author≠auditor split happening at author-time.

## The `judge:` declaration

A directive declares its judgment task once, in `directive.yaml`:

```yaml
judge:
  inputs:  [diff, receipt, issue]    # typed tokens → the handles the judge is given
  checks:
    - "'## What changed' faithfully describes the diff"
    - "each '- [x]' item is realized in the diff"
    - "the '## Checklist' mirrors the issue's checklist"
  # group: <label>                   # optional batching label; operator-tunable via conf, bundled packs declare no default (below)
  section: Audit                     # the receipt section the verdict lands in — presence of this key is what puts the directive on the attest lane
  gate:    record                    # record (default) | verdict | verdict-contestable
```

No `cmd` row: this is the norm for every bundled directive. Absent `cmd.attest`
defaults to `harness`. Absent `cmd.schedule` means the directive names no
judge of its own — the schedule driver falls back to the ephemeral
`GOVERNANCE_JUDGE_CMD` env (exported by the lane's generated workflow; see
[SCHEDULE_FLOW.md](SCHEDULE_FLOW.md#the-judge-resolution-ladder-scheduled)),
and skips the directive honestly if that doesn't answer either. `cmd` stays in
the schema as an optional per-directive override — a value of `harness` for
`attest`, or a shell command string for either lane:

```yaml
  cmd:
    attest:   harness                       # harness (default) | shell command string
    schedule: claude -p --output-format text --model opus   # shell command string only; overrides the ladder below
```

Reach for it only when one directive genuinely needs a judge different from
the rest of the repo — a shareable pack should not carry a `cmd` row (see
[PACK_AUTHORING.md](PACK_AUTHORING.md)); name the judge at the repo level
instead.

- **`inputs`** — typed tokens resolved to concrete handles by `resolve_judge_input`:
  `diff`→`git diff`, `receipt`→the receipt path, `issue`→`gh issue view #N`
  (derived from the receipt name), `transcript`→the active runtime's session
  JSONL (`CODEX_THREAD_ID` under `~/.codex/sessions/` /
  `~/.codex/archived_sessions/` for Codex, `CLAUDE_CODE_SESSION_ID` under
  `~/.claude/projects/` for Claude Code, or the explicit `*_TRANSCRIPT_PATH`
  override), `layer-map`→the doc named by
  `GOVERNANCE_LAYER_DOC`. An unknown token passes through verbatim.
- **`checks`** — the numbered rubric the judge adjudicates (the prose rubric is
  the directive's `constitution.md`).
- **`group`** — an optional, free-form label. Every directive resolving the
  same `group` label is batched into **one** judge invocation — one sub-agent
  on the attest lane, one judge call on the schedule lane — demuxed back out
  per directive by its `DIRECTIVE:`-tagged blocks. A directive resolving no
  `group` gets its own solo invocation (use this when inter-attestation
  independence — avoiding a halo effect across verdicts — matters). A group
  is one invocation running **one** command: every member of a group must
  *resolve* to the same command for the lane being batched (for `schedule`,
  after the resolution ladder above runs) — `packctl` rejects a group whose
  declared `cmd` rows disagree at validation time, and the schedule driver
  refuses to split a group whose members resolve to different commands at
  runtime, reporting the whole group un-adjudicated with one honest line
  rather than silently invoking a subset.

  **The batching label is operator-owned and lives in the per-directive conf
  overlay** (see *Author-owned vs operator-owned* below) — a single
  `JUDGE_GROUP=<label>` row in
  `.governance/conf/<owner>/<pack>/<id>.conf`, read by the bespoke
  `_judge_group_resolve` helper (not `conf_get`'s hard-fail `defaults.conf`
  tier, since batching has no author-owned default to fail against). Like
  every conf overlay, it is seeded once at install and never touched again by
  `pack update` / `governance update` / `reset`.

  - **Resolution order**, per directive:
    1. The overlay's `JUDGE_GROUP=` row — a **present but empty** value
       forces solo, even if `directive.yaml` declares a `group` default. This
       is how a consumer strips a label a community or repo-local pack
       shipped, without forking it.
    2. `directive.yaml`'s own `judge.group` — a repo-local or community
       pack's declared default — when the overlay names no row at all for
       this directive.
    3. Solo.
  - Because resolution runs per directive against its own overlay file, there
    is no cross-directive partition to go ambiguous, and no
    double-membership warn-and-degrade case left to reason about — the old
    repo-wide `judge-group` / `judge-solo` grammar (and the ambiguity it
    could produce when the same directive appeared under two labels) is gone
    along with the file it lived in.
  - A group can still end up with members that resolve to *different* judge
    commands (one directive's own `cmd.schedule` override disagreeing with
    another's); the schedule driver refuses that group whole at runtime with
    one honest un-adjudicated line rather than silently judging a subset —
    `packctl` cannot see the overlay tier at author time, so this mismatch is
    caught only at runtime, never at validation.

  **Bundled packs declare no `group`** — for the same reason they declare no
  `cmd`. Batching is not part of what a directive means; it is a trade of
  fidelity for tokens, and which side of that trade a repo wants is the
  repo's call, not a pack author's. Unlike a shipped `cmd`, though, a shipped
  `group` is not stuck: the per-directive overlay is exactly where the
  choice lives — repo-level in effect, user-owned, not digest-guarded — so a
  consumer sets, changes, or strips a label (including one a community pack
  shipped) per directive without touching the vendored tree at all. Every
  kit-bundled judgment ships adjudicated solo by default; a repo that wants
  otherwise writes an overlay row, not a fork.
- **`section`** — the `## <Section>` the verdict is written into. Its
  presence is what puts a declaration on the **attest** lane at all — there is
  no separate field for this. A declaration that carries `section:` attests
  into that receipt section at commit time (`gate:` decides whether the
  commit blocks on it), and the schedule lane re-derives the same verdict at
  rest. A declaration with no `section:` is **schedule-only**: it never
  participates on the commit path — `judge_attest` returns immediately and
  nothing is gated or registered — needs no `check.sh` and no `surface:`, and
  its findings go only to the lane's digest issue, filed as an issue rather
  than written into any receipt. Use the no-`section:` shape for a judgment
  worth making
  at merge that has no author-time artifact to sit in. (Before issue #355
  this was a separate `sink: section | none` field; `sink` duplicated what
  `section` presence already said, and `none` misnamed a sink that actually
  files an issue, so it was deleted — an unknown `sink` key is now a
  `packctl` validation error.)
- **`gate`** — what the commit path does with the recorded verdict, for a
  declaration on the attest lane (`section:` present):
  - `record` (default) — gates *presence* of a verdict token; never blocks on
    what the verdict says.
  - `verdict` — makes the verdict itself load-bearing: the commit blocks on a
    `REFUTED` or missing verdict, and a `CONTESTED` verdict does **not** ride
    through either.
  - `verdict-contestable` — the same blocking behavior as `verdict`, except a
    `CONTESTED` round is allowed to ride through, with a loud stderr warning.

  See [Adjudicated gates](#adjudicated-gates-gate-verdict). (Before issue
  #355 the contestable behavior was a separate `contest: forbid | allow`
  field layered on `gate: verdict`; folding it into `gate` leaves one axis
  that answers "what blocks" completely — `gate: verdict` is exactly
  yesterday's `gate: verdict` + `contest: forbid`, and `gate:
  verdict-contestable` is exactly yesterday's `gate: verdict` + `contest:
  allow`. An unknown `contest` key is now a `packctl` validation error.)
- **`cmd`** — an **optional per-directive override** of who judges each lane,
  a map with keys `attest` and/or `schedule`. Not the normal case: no bundled
  `governance-kit/*` directive declares it. Each value is either the reserved
  word `harness` or a full shell command string:
  - `harness` — the live session's own sub-agent mechanism (Claude Code Task,
    Codex spawn, …): the hook emits the rubric as the remediation
    instruction, the **calling agent** spawns the fresh-context sub-agent
    in-session, the gate re-reads the section. Harness-portable by
    construction — the yaml never names which harness. This is the default
    for `attest` whenever `cmd.attest` is absent — which is every bundled
    directive today.
  - a shell string — a detached CLI judge, run via `bash -c "$cmd"` with the
    rendered prompt on **stdin** and the answer read from **stdout**. No
    other channel.
  - `attest` accepts `harness` or a shell string. `schedule` accepts a shell
    string **only** — `schedule: harness` is invalid (`packctl` rejects it):
    the schedule lane runs at rest with no live session, so there is nobody
    to spawn an in-session sub-agent.
  - **Resolution differs by lane.** `attest` has no env-var ladder: absent
    `cmd.attest` is always `harness`, full stop. `schedule` resolves through
    a three-rung ladder — the directive's own `cmd.schedule` first (a rare
    per-directive override, and the only rung a fork or `directive modify`
    is needed to change), then the ephemeral `GOVERNANCE_JUDGE_CMD` env (set
    by the lane's generated workflow from a gated repository variable), then
    the directive is skipped for that run with one honest log line naming
    the env as the way to supply a judge — never a guessed or downgraded
    judge. See
    [SCHEDULE_FLOW.md](SCHEDULE_FLOW.md#the-judge-resolution-ladder-scheduled).
  - A directive that genuinely needs a fixed judge (a per-directive `cmd`
    override) edits it through the normal pack/directive override flow (fork
    or `directive modify`), the same way it would edit any other author-fixed
    field — but a shareable pack should not carry a `cmd` row at all; see
    [PACK_AUTHORING.md](PACK_AUTHORING.md).

### Author-owned vs operator-owned (issue #331)

The fields are two different kinds of thing, and the kit treats them
differently:

- **Semantic — author-fixed in `directive.yaml`** (`inputs`, `checks`,
  `section`, `gate`, `cmd`). These *are* the
  directive's substance: `checks` is the rubric the schedule lane re-derives
  the verdict against, `inputs` decides what ground truth the judge sees,
  `section` is a code contract `check.sh` greps for, and `cmd` names the judge
  itself — a consumer who could edit any of them would grade the attest and
  schedule verdicts against a different rubric or a different judge, so none
  of them are tweakable without a fork — `managed-tree-integrity` rejecting a
  hand-edit of the vendored `directive.yaml` is the system working. A repo on
  a different harness edits `cmd` through the normal pack/directive override
  flow, not a conf overlay.
- **Operational — operator-tunable, both through the per-directive conf
  overlay** (the adjudication round ceiling; the `group` batching label,
  which moved off any repo-level file as of this change — see the *batching
  partition* above). Both are pure execution-shape dials, not rubric or judge
  changes:

  A third, separate knob sits outside both of these: `GOVERNANCE_JUDGE_CMD`,
  an ephemeral env exported by a schedule lane's generated workflow (from a
  gated repository variable). It supplies the schedule judge for every
  directive in that lane that declares no `cmd.schedule` of its own — see the
  resolution ladder above and [SCHEDULE_FLOW.md](SCHEDULE_FLOW.md).

  | knob | overrides | default |
  |---|---|---|
  | `JUDGE_ROUNDS` | the adjudication round ceiling *K* (`gate: verdict` only) | `3` (floor `2` — a lower value is clamped up) |
  | overlay `JUDGE_GROUP=` | the batching label the directive resolves | the directive's own `judge.group` in `directive.yaml`, or solo if the overlay row is absent |

  Both keep the usual `conf_get`-family shape — an env override for
  `JUDGE_ROUNDS` (`GOVERNANCE_<KEY>` > user overlay row > pack
  `defaults.conf` row > the `directive.yaml` value), and the bespoke
  `_judge_group_resolve` reader for `JUDGE_GROUP` (overlay row, empty value
  forcing solo, else `directive.yaml`, else solo) — so behavior is
  **unchanged until a consumer writes an overlay row**. A directive exposing
  `JUDGE_ROUNDS` ships a `defaults.conf` carrying the row (with docs);
  `group` has no `defaults.conf` row at all, since there is no author-owned
  default to document — the overlay is the only place it is ever written.

## The remediation loop (no hook ever spawns anything)

A git hook can neither spawn a sub-agent nor judge its output. So the directive
follows the standard GDD remediation loop:

```
git commit
  → check.sh: judge_attest gates '## <Section>' (present + verdict) and,
    when pending, registers it into a shared ledger
  → after every check, the run-level orchestrator (attestation_remediation)
    emits ONE grouped instruction for all pending attestations
  → the harness agent reads it, spawns the sub-agent(s), each reads ground
    truth and writes its section
  → agent re-stages, re-commits → check.sh: section present + verdict → PASS
```

The harness must actually spawn the fresh-context auditor. The primary agent
must not self-author an attestation section from its own context; doing so
collapses the author≠auditor split this mechanism exists to enforce.

Two honest limits this pattern owns rather than hides:

- **Under `gate: record` it records; it does not adjudicate.** `check.sh`
  verifies the section *exists and is verdict-bearing*, never that the verdict is
  *true*. Trusting the verdict is the schedule lane's job. The commit-path
  guarantee is "the audit was recorded," not "the audit passed." A directive
  that needs the stronger guarantee declares
  [`gate: verdict`](#adjudicated-gates-gate-verdict) — then the commit blocks
  until the verdict itself reads PASS, and the schedule lane's job becomes
  checking whether that PASS was *earned*.
- **Harness-only authoring.** A bare human commit or a CI run has no agent to
  spawn anything, so `check.sh` simply hard-fails on the missing section —
  correct (the audit step did not run); the hook can *demand* the section, never
  *manufacture* it.

## Adjudicated gates (`gate: verdict`)

`gate: record` is the original contract: the commit path proves an audit
*happened*. `gate: verdict` (issue #355) makes the recorded verdict itself
load-bearing — **the commit is blocked until the latest adjudication round reads
PASS**, and that PASS is bound to the exact tree it was rendered against, so it
cannot be reused once the code moves under it.

It is still all bash and git on the commit path. Nothing about this lets a hook
spawn or judge anything; what changes is *what the deterministic check demands
of the artifact*.

### The adjudication log

The attested section carries an append-only log, one ASCII line per round:

```
- [round N] VERDICT lane=attest|schedule stamp=<12-hex> — <free text>
```

- `VERDICT` is one of `PASS`, `REFUTED`, `ESCALATED`, `CONTESTED`.
- `N` starts at 1 and increases strictly.
- `lane` is which moment produced the round — `attest` (commit-time) or
  `schedule` (at-rest re-adjudication; the renamed `sweep`).
- The free text after the em dash is optional and unconstrained — it is where the
  adjudicator says *why*.

Everything else in the section is free prose; the gate reads only the round
lines. The exact ERE the gate matches is
`^- \[round ([0-9]+)\] (PASS|REFUTED|ESCALATED|CONTESTED) lane=(attest|schedule) stamp=([0-9a-f]{12})( — .*)?$`.

### The stamp

`_adjudication_stamp <receipt>` prints twelve hex characters: the head of
`sha256("<tree-sans-receipt> <receipt-normalized-sha>")`, where

- **tree-sans-receipt** is `git write-tree` over a *temporary copy* of the index
  with the receipt removed from it — every other file in the pending commit; and
- **receipt-normalized-sha** is the sha256 of the receipt with every round line
  stripped out.

That gives one exact property: **appending rounds never invalidates the stamp,
while editing any other byte of the receipt — or any other file in the commit —
does.** A verdict is therefore a statement about a specific tree, not a token
that ages into a rubber stamp. In CI the index equals `HEAD`, so the same
computation reproduces the committed tree; a repo with no commits still stamps.

The adjudicator computes it from the repo rather than inventing it:

```sh
bash -c 'source .governance/lib.sh; _adjudication_stamp receipts/issue-123-x.md'
```

### What the gate checks

In order, and all deterministic:

1. **The section exists.** Missing → the same remediation loop as `record`,
   except the instruction says the verdict blocks the commit.
2. **Append-only.** Every `REFUTED` / `ESCALATED` / `CONTESTED` round present in
   the base version of the receipt must still be there **verbatim**. The base is
   `HEAD` and the change-set base (the merge-base ladder `doc-integrity` uses) —
   the same commit in the common case. Deleting *or rewording* an adverse round
   fails the commit and the violation quotes the line that went missing. An
   adverse verdict is evidence; a PASS is re-derivable.
3. **The log is well-formed** — at least one round line, numbered from 1,
   strictly increasing.
4. **The latest round is `PASS`** — or `CONTESTED` when the directive declares
   `gate: verdict-contestable`, which rides through with a loud stderr warning
   (`governance: CONTESTED verdict riding on <receipt> — schedule will
   re-adjudicate`). Under plain `gate: verdict` a `CONTESTED` round does not
   ride through. `REFUTED` and `ESCALATED` block under both.
5. **The stamp is fresh** — the latest round's stamp equals the stamp recomputed
   now. Otherwise: *stale verdict — the staged tree changed since adjudication*.

The honest limit worth naming: within a *single* pending commit, rounds that were
never committed have no base version to compare against, so the append-only guard
protects rounds from earlier commits, not rounds written and scrubbed between two
attempts at the same one. The schedule lane, which sees the merged result, is
what catches a log that was quietly pruned before it ever landed.

### The escalation ladder

Let *R* be the number of `REFUTED` rounds already logged and *K* the resolved
`JUDGE_ROUNDS` ceiling (default 3, floor 2). `attestation_remediation` renders:

| position | what the instruction says |
|---|---|
| *R* < *K*−1 | spawn an adjudicator via the directive's declared `cmd.attest` |
| *R* = *K*−1 | the **escalation round** — spawn again via the same `cmd.attest`, explicitly flagged as the escalation round |
| *R* ≥ *K* | **STALLED**: do not spawn again. Append a terminal `ESCALATED` round and surface the dispute to a human. The commit stays blocked until the underlying work changes (or `gate: verdict-contestable` lets a `CONTESTED` round through). |

The ladder exists so a genuinely disputed change escalates to a stronger model
once, then stops — rather than burning an unbounded number of adjudications, or
letting the agent grind against a rubric until something says PASS.

The instruction the harness receives spells out the round-line format, the
`_adjudication_stamp` invocation, the append-only rule, and the point that a
`PASS` recorded without actually checking the rubric against the ground truth is
exactly the failure the schedule lane re-adjudicates every one of these logs to
catch.

## Batched orchestration (issue #325)

Before #325 the harness spawned **one sub-agent per attested section** — N×
cost and latency when a commit owed several. The orchestration splits the gate
from the instruction:

- **`judge_attest <receipt>`** — the per-directive gate a migrated `check.sh`
  calls. It reads the sibling `directive.yaml`'s `judge:` block, runs the same
  presence + `PASS`/`REFUTED` check `require_attestation` does (so CI fails
  per-section, independently — unchanged), and when the section is pending
  **registers** it (section, group, resolved inputs, checks) into a shared
  ledger.
- **`attestation_remediation`** — the orchestrator, run **once** by `run.sh` and
  the generated pre-commit dispatcher after every `check.sh`. It reads the ledger
  and emits **one grouped remediation instruction** per `group` label present
  (a single sub-agent handed the *union* of that group's sections' inputs,
  asked for each verdict, demuxed by `DIRECTIVE:`-tagged blocks), plus one solo
  sub-agent per section that declares no `group`.

With no `group` resolved anywhere — the bundled default, and the outcome for
any repo that has not written an overlay row — that is one spawn per section: a
newly added receipt owing `## Audit`, `## Layer boundaries`, and `## Steering`
costs three sub-agents, each reading the diff with nothing else in its
context. A repo that labels all three into one group — via a `JUDGE_GROUP=`
row in each directive's conf overlay, see *The batching partition* above —
costs one sub-agent and one diff read instead. The
critical author≠auditor independence (the auditor is always a fresh context,
never the harness) holds either way; what batching trades is
*inter-attestation* independence — fourteen prior PASSes make the fifteenth
cheaper to wave through, and one malformed response loses the whole group
rather than one verdict. That is why the default is solo and the label is
opt-in.

## Judges: who renders the verdict (issue #355, Phase 3)

`gate: verdict` fixes *that* a verdict decides the commit. It says nothing about
**who renders it**. That is `cmd.attest` — an author-fixed field in
`directive.yaml`, not an operator conf knob (see *Author-owned vs
operator-owned* above):

| `cmd.attest` | who judges | lane |
|---|---|---|
| `harness` (default when absent) | a fresh-context sub-agent the **calling agent** spawns, driven by the grouped remediation instruction | commit |
| a shell command string | a **separate, detached process** the hook itself invokes via `bash -c "$cmd"`, prompt on stdin, answer on stdout | commit |

The `attest` lane has no env-var or conf-overlay ladder that changes who
judges — the `cmd.attest` value in `directive.yaml` (or its absence, meaning
`harness`) is the whole answer. The schedule lane is never `harness`:
`.governance/schedule.sh` always judges through a shell command string, but
that string is resolved rather than declared outright — the directive's own
`cmd.schedule` when present (rare; no bundled directive sets one), otherwise
the ephemeral `GOVERNANCE_JUDGE_CMD` env exported by the lane's generated
workflow, otherwise the directive is skipped for that run (see
[SCHEDULE_FLOW.md](SCHEDULE_FLOW.md)). Same helper, same prompt builder, same
honesty rule on both lanes — no vendor HTTP transport, no second engine.

### Why a different vendor's CLI is a real control

The harness default is one model family judging its own family's work:
independent *context*, shared *failure modes*. If the author model has a blind
spot — a class of scope creep it does not perceive as scope creep, a
rationalization pattern it finds convincing — its sibling adjudicator shares it.
Separation of duties is the standard answer, and it is only real when the two
parties do not come from the same place: a `cmd.attest` invoking a different
vendor's CLI auditing this harness's authored work breaks the shared-failure-
mode correlation in a way no amount of prompt engineering inside one vendor can.

The second property is structural. A `cmd` judge is a **process**, not a
sub-agent of the author: it never sees the author's plan, its rationalizations,
or the running conversation, because **the prompt is built by `lib.sh`** out of
the directive's declaration and ground truth read from git — the diff, the
receipt — never out of anything the agent under audit wrote into its own
context. That prompt build is the baseline mitigation on **both** shapes of
`cmd.attest`: even on `harness`, the rubric comes from `directive.yaml`, and
the ground truth is fenced as untrusted data the judge must analyze, not obey
(the same universal contract the schedule lane's system prompt carries).

Neither shape makes in-context collusion *impossible* on the harness path —
the calling agent still spawns that sub-agent. A shell-string `cmd.attest` is
what removes the calling agent from the loop entirely.

### What actually happens on a blocked commit

1. `_judge_verdict_gate` fails (no log, a `REFUTED` latest round, a stale
   stamp, …).
2. If `cmd.attest` resolves to a shell string **and** the gate is `verdict`,
   `lib.sh` builds the prompt and pipes it to `_judge_cmd_run`, which
   runs `bash -c "$cmd"` with the prompt on stdin, appends the returned round
   line to the section (with a freshly computed `stamp=`), stages the
   receipt, and **re-runs the gate once**. A `PASS` clears the commit in the
   same hook run; a `REFUTED` leaves it blocked with the round on the record.
3. Anything that goes wrong — the command's first word missing from `PATH`, a
   nonzero exit, an answer that is not a well-formed verdict — **degrades to
   the harness path**: the section is registered in the ledger with an
   executor of `cmd:<first-word>+fallback`, and the grouped instruction
   carries a one-line warning so the operator learns their side channel is
   broken instead of reading the fallback as the configured judge working. An
   operator's misconfiguration must never be able to wedge a commit the
   default configuration would allow.
4. `cmd.attest` absent or `harness` → the harness sub-agent path directly (no
   attempt at a shell judge); the ledger row records `harness`.
5. `gate: record` **never** takes the shell-judge path. A record section is an
   authored narrative, not a verdict; there is nothing for a judge to decide.

Termination: one adjudication per `judge_attest` call, and a budget of *K*
(the resolved `JUDGE_ROUNDS` ceiling) shell-judge rounds per hook run,
counted beside the attest ledger so it spans the separate `check.sh` processes
a dispatcher runs. Past the budget the shell judge refuses to spend and hands
over to the harness path — a commit attempt always terminates.

**No eval, no ship applies to `cmd` judges too.** A lane that can only be
exercised by really spawning a paid CLI is an untested lane, so the eval seam
lives in `_judge_cmd_run` itself: a stub `cmd` (a tiny script on `PATH`)
stands in for a real judge in `scripts/test-subagent.sh`, offline, in a
throwaway repo — no vendor CLI installed and no network.

One interaction to know about: a shell-string `cmd.attest` **stages the
receipt** mid-hook (that is how the round it just wrote reaches the pending
commit). A directive that computed a coordinate over the staged tree at one
hook stage and re-checked it at a later stage would see the tree move
underneath it, exactly as it does when a harness remediation loop re-stages.
The `_adjudication_stamp` above is immune to this because it excludes the
receipt from the tree it hashes, which is why staging mid-hook is safe.

## The runtime adapters: accounting only

`.governance/runtimes/<name>.sh` still ships one file per harness, kit-managed
exactly like `run.sh` and `lib.sh` (stamped with `kit-version=`, digested by
`managed-tree-integrity`, re-synced by `governance update`) — but adapters no
longer judge anything. Judging moved entirely into `cmd` + `_judge_cmd_run`
in `lib.sh` (issue #355); the adapter registry now answers only the
off-commit-path accounting verbs for `agent-token-accounting`:

- **`resolve <session-id> [<declared-path>]` / `emit`** — `resolve` reads an
  identity-pinned harness surface (a declared path, a session-id-named file
  under the harness's documented state dir, or a documented local server) and
  prints one usage line, or exits 2 when it cannot resolve; `emit` accepts the
  harness's own push payload (statusline/hook JSON) and appends a snapshot to
  the accounting sidecar. Seven adapters ship these: `claude-code`, `codex`,
  `pi`, `grok`, `cursor-agent`, `opencode`, and `manual`. See
  [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) for the accounting contract
  these verbs feed.

Before issue #355 the registry also carried `judge` and `can-judge` verbs; both
are deleted, along with the per-adapter tier→model alias tables. A directive
that wants a specific vendor's CLI as its judge now says so directly in
`cmd.attest` / `cmd.schedule` — there is no adapter indirection between the
declaration and the process that runs.

## Use a small model where cost matters

The author-time attestation is a **bounded read-and-record audit**, not the
final word on truth — the verdict's correctness is independently re-derived
by the merge-time schedule lane, typically on a stronger model. No bundled
pack fixes either model in `directive.yaml`: `cmd.attest` is absent (the
harness default is the common case, see the schema above), so the attest-lane
model is whatever the calling agent's own sub-agent mechanism uses;
`cmd.schedule` is absent too, so the schedule-lane model is whatever the
resolved `GOVERNANCE_JUDGE_CMD` env — exported by the lane's generated
workflow from a gated repository variable — names, deliberately picked
stronger than the attest default since a schedule lane fires on a cadence,
not on every commit (issue #321).
The auditor renders the verdict as literally `PASS` or `REFUTED`; the gate
matches that token case-insensitively anywhere in the section.

The model is whatever the resolved judge command names — there is no
separate tier knob. A consumer who wants every schedule re-adjudication run
on a stronger (or cheaper) model changes the `GOVERNANCE_JUDGE_CMD` value the
lane's workflow exports, not a per-directive field. A consumer who wants one
*specific* directive's
author-time verdict run on a different model overrides that directive's
`cmd.attest` string through the normal pack/directive override flow (issue
#331, see *Author-owned vs operator-owned* above) — but this is the rare
per-directive case, not how a bundled pack ships.

## The helpers (in `lib.sh`)

These sit alongside the rest of the `lib.sh` surface catalogued in the
[helper API reference](LIB_API.md) (with the kit version each landed in):

- **`extract_md_section <file> <heading>`** — print the body of the
  `## <heading>` section (case-insensitive), stopping at the next `## `.
- **`attestation_prompt <section> <inputs> <check-1> [...]`** — the canonical
  single-section authoring instruction (still emitted by `require_attestation`).
- **`require_attestation <file> <section> <why> <inputs> <check-1> [...]`** — the
  original per-directive gate: presence + a verdict token, with a self-contained
  authoring instruction in its violation. Unchanged; still the fallback when a
  directive can't declare a `judge:` block.
- **`judge_attest <receipt>`** (issue #325) — the declaration-driven gate.
  Reads the sibling `directive.yaml`'s `judge:` block, runs the gate the
  block declares (`record`, `verdict`, or `verdict-contestable`), and
  registers a pending section for the orchestrator. Returns 0 immediately
  when the declaration has no `section:` — a schedule-only declaration the
  commit lane ignores.
- **`attestation_remediation [<ledger>]`** (issue #325) — the orchestrator that
  emits the single grouped remediation instruction, including the escalation
  ladder for adjudicated sections; invoked once by `run.sh` / the pre-commit
  dispatcher.
- **`resolve_judge_input <token> <receipt>`** (issue #325) — map a typed input
  token to its concrete handle phrase.
- **`_adjudication_stamp <receipt>`** (issue #355) — the freshness binding
  described above. Private to the kit, but deliberately callable standalone so a
  fresh-context adjudicator can compute the stamp it must record.
- **`_judge_cmd_resolve <yaml> <lane>`** (issue #355) — print the `cmd`
  string declared for `lane` (`attest` or `schedule`) out of the directive's
  flattened `judge:` yaml, or nothing (return `1`) when the row is absent.
- **`_judge_cmd_run <cmd>`** (issue #355) — run one judge round: prompt on
  stdin, normalized verdict on stdout. Checks the command's first word is on
  `PATH` (return `2`, no guessing, if not), strips harness session identity
  from the environment before exec'ing (`CLAUDECODE`, `CLAUDE_CODE_*`,
  `CODEX_*`, `CURSOR_*`, `PI_*`, `OPENCODE*`) so a shell-string judge is a
  genuinely fresh context and never bills the audit to the session under
  audit, wraps the call in `timeout`/`gtimeout` when available
  (`AGENT_JUDGE_TIMEOUT`, default 120s), runs `bash -c "$cmd"`, and pipes the
  output through `_judge_emit_verdict`. Returns `2` on a missing binary, a
  nonzero exit, or an unparseable answer.
- **`_judge_emit_verdict`** (issue #355) — the awk grammar filter every
  judge's raw output is piped through: CR-strip, printable-ASCII only, length
  cap, passes only `VERDICT:`/`REASON:`/`FINDING:`/`DIRECTIVE:` lines (a
  `DIRECTIVE:` line re-arms the verdict matcher, for the batched-`group`
  demux). One implementation, no longer duplicated per adapter.
- **`_judge_cli_prompt`** (issue #355) — the prompt build described under
  *Judges*, out of the declaration and git ground truth, never out of
  anything the agent under audit wrote into its own context.

All of these are **pure bash + awk + git** as of issue #355 — the commit path
runs no python at all. That matters for a tool whose whole promise is that it
still works on a machine with nothing installed: the declaration reader
(`_judge_yaml`, `_judge_tier`) and the remediation formatter used to shell
out to stdlib python, and no longer do.

## Wiring a directive onto it

Declare the task in `directive.yaml` (the `judge:` block above), then in a
change-set-scoped block of `check.sh` (only newly added artifacts owe the
attestation, exactly as `receipt-per-issue` scopes its `## Decisions` rule):

```sh
if declare -F judge_attest >/dev/null 2>&1; then
    judge_attest "$f"
else
    # Fallback on an older runtime lib.sh that predates the declaration-driven gate.
    require_attestation "$f" "Audit" "<why>" "<inputs>" "<check-1>" "<check-2>"
fi
```

## Versioning note

Because the helpers live in kit-owned `lib.sh`, a pack whose directive uses them
must declare a `min_governance_kit` floor at the kit version that **ships** them
— the first-shipped tag, not the in-development source-line marker. `require_attestation`
first shipped in `kit/v0.10.0`; `judge_attest` / `attestation_remediation`
ship in the kit release that carries issue #325. A directive that declares
`gate: verdict` or `gate: verdict-contestable`, omits `section:` for a
schedule-only declaration, or leans on `_adjudication_stamp` floors at the
release carrying issue #355 — an older `lib.sh` ignores the new keys and
gates on presence alone, which is a silent downgrade, not an error. See
[LIB_API.md](LIB_API.md#version-floor-obligation) and [VERSIONING.md](VERSIONING.md).

## See also

- [SCHEDULE_FLOW.md](SCHEDULE_FLOW.md) — the **schedule** mode: the off-path
  LLM-judge lane that re-derives recorded verdicts through `cmd.schedule` and
  files a digest.
- [LIB_API.md](LIB_API.md) — the full `lib.sh` helper surface, with signatures
  and landed-in versions.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — patterns for writing checks.
- [PHILOSOPHY.md](PHILOSOPHY.md) — receipts over transcripts.

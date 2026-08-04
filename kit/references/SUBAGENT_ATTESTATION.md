# Sub-agent judgment (attest + sweep)

Some directives ask a question a hook structurally cannot answer: *does this
artifact correspond to reality* — does the receipt match the diff, does the
change honor a declared architectural invariant, did the agent record every time
the operator steered it? Answering needs a **fresh-context model judgment**
against ground truth, not a string relationship a `check.sh` can re-execute.

The kit expresses every such judgment as **one declaration** — a `subagent:`
block in the directive's `directive.yaml` — executed by **one mechanism** at two
tiers and two times (issue #325):

| | **attest** (commit) | **sweep** (merge / scheduled) |
|---|---|---|
| does | a fresh-context sub-agent renders a verdict on a rubric | a pluggable judge renders a verdict on the same rubric |
| tier | **low** (cheap, *record*) | **high** (expensive, *verify*) |
| executor | harness-spawned sub-agent | a judge backend (github-models today) |
| result | verdict written into a `## Section` | structured `{pass, violations}` → digest issue |

The two are the same task — a tiered, rubric-framed model judgment — so they are
two **consumer modes** of one `subagent:` declaration, not two parallel features.
This page covers the **attest** mode (the commit lane). The **sweep** mode is in
[SWEEP_FLOW.md](SWEEP_FLOW.md); it re-derives the recorded verdict at the high
tier and files a digest. Wiring the sweep engine to read `subagent:` directly is
the immediate follow-up to #325 — the schema is designed so it consumes the same
declaration unchanged.

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
and gated for *presence*, with the truth of its verdict deferred to the sweep
lane at merge. The independence is the point: a sub-agent handed only the ground
truth — never the code-author's reasoning — is a genuinely independent auditor.
That is the author≠auditor split happening at author-time.

## The `subagent:` declaration

A directive declares its judgment task once, in `directive.yaml`:

```yaml
subagent:
  inputs:  [diff, receipt, issue]    # typed tokens → the handles the judge is given
  checks:
    - "'## What changed' faithfully describes the diff"
    - "each '- [x]' item is realized in the diff"
    - "the '## Checklist' mirrors the issue's checklist"
  isolation: shared                  # shared (default) | isolated
  section: Audit                     # the receipt section the verdict lands in
  gate:    record                    # record (default) | verdict
  sink:    section                   # section (default) | none
  contest: forbid                    # forbid (default) | allow
  tiers:   { attest: low, sweep: high }
```

- **`inputs`** — typed tokens resolved to concrete handles by `resolve_subagent_input`:
  `diff`→`git diff`, `receipt`→the receipt path, `issue`→`gh issue view #N`
  (derived from the receipt name), `transcript`→the active runtime's session
  JSONL (`CODEX_THREAD_ID` under `~/.codex/sessions/` /
  `~/.codex/archived_sessions/` for Codex, `CLAUDE_CODE_SESSION_ID` under
  `~/.claude/projects/` for Claude Code, or the explicit `*_TRANSCRIPT_PATH`
  override), `layer-map`→the doc named by
  `GOVERNANCE_LAYER_DOC`. An unknown token passes through verbatim.
- **`checks`** — the numbered rubric the judge adjudicates (the prose rubric is
  the directive's `constitution.md`).
- **`isolation`** — `shared` (default) lets the commit-time orchestrator batch
  this section with other `shared` sections into one sub-agent; `isolated` forces
  its own sub-agent (use when inter-attestation independence — avoiding a halo
  effect across verdicts — matters).
- **`section`** — the `## <Section>` the verdict is written into.
- **`gate`** — what the commit path does with the recorded verdict:
  `record` (default) gates *presence* of a verdict token; `verdict` makes the
  verdict itself load-bearing. See [Adjudicated gates](#adjudicated-gates-gate-verdict).
- **`sink`** — where the verdict lands: `section` (default), or `none` for a
  **sweep-only** declaration. With `sink: none` the commit lane (`subagent_attest`)
  returns immediately and nothing is gated or registered; the sweep engine still
  reads the same block and adjudicates it off the commit path. Use it for a
  judgment worth making at merge that has no author-time artifact to sit in.
- **`contest`** — whether an adjudicator may hand back a `CONTESTED` verdict and
  still let the commit through: `forbid` (default) or `allow`. Only meaningful
  under `gate: verdict`.
- **`tiers`** — the capability tier each mode runs at: `attest` low, `sweep` high.

### Author-owned vs operator-owned (issue #331)

The fields are two different kinds of thing, and the kit treats them
differently:

- **Semantic — author-fixed in `directive.yaml`** (`inputs`, `checks`,
  `section`, `gate`, `sink`, `contest`). These *are* the directive's substance:
  `checks` is the rubric the
  sweep lane re-derives the verdict against, `inputs` decides what ground truth
  the judge sees, and `section` is a code contract `check.sh` greps for. A
  consumer who could edit them would grade the attest and sweep verdicts against
  different rubrics, so they must not be tweakable without a fork —
  `managed-tree-integrity` rejecting a hand-edit of the vendored `directive.yaml`
  is the system working.
- **Operational — operator-tunable through the conf overlay** (`isolation`,
  `tiers`, and the adjudication round ceiling). These are pure cost / batching
  dials. A consumer tunes them per-repo
  via the pack's [`defaults.conf` + `.governance/conf/...` overlay](PACK_AUTHORING.md)
  mechanism — four knobs, resolved with `conf_get`:

  | knob | overrides | default |
  |---|---|---|
  | `SUBAGENT_ISOLATION` | `isolation` | `shared` |
  | `SUBAGENT_TIERS_ATTEST` | `tiers.attest` | `low` |
  | `SUBAGENT_TIERS_SWEEP` | `tiers.sweep` | `high` |
  | `SUBAGENT_ROUNDS` | the adjudication round ceiling *K* (`gate: verdict` only) | `3` (floor `2` — a lower value is clamped up) |

  Resolution precedence is the usual `conf_get` ladder — env `GOVERNANCE_<KEY>` >
  user overlay row > pack `defaults.conf` row > the `directive.yaml` value — so
  behavior is **unchanged until a consumer writes an overlay row**. The commit
  lane (`subagent_attest` → `attestation_remediation`) renders the resolved
  attest tier into the grouped instruction; the sweep engine
  (`resolve_model_tier`) resolves `SUBAGENT_TIERS_SWEEP` the same way. A directive
  exposing these knobs ships a `defaults.conf` carrying the three rows (with
  docs); the overlay wins when a consumer writes one.

## The remediation loop (no hook ever spawns anything)

A git hook can neither spawn a sub-agent nor judge its output. So the directive
follows the standard GDD remediation loop:

```
git commit
  → check.sh: subagent_attest gates '## <Section>' (present + verdict) and,
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
  *true*. Trusting the verdict is the sweep lane's job. The commit-path guarantee
  is "the audit was recorded," not "the audit passed." A directive that needs the
  stronger guarantee declares
  [`gate: verdict`](#adjudicated-gates-gate-verdict) — then the commit blocks
  until the verdict itself reads PASS, and the sweep lane's job becomes checking
  whether that PASS was *earned*.
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
- [round N] VERDICT tier=<low|medium|high> stamp=<12-hex> — <free text>
```

- `VERDICT` is one of `PASS`, `REFUTED`, `ESCALATED`, `CONTESTED`.
- `N` starts at 1 and increases strictly.
- `tier` is the tier the adjudicator actually ran at.
- The free text after the em dash is optional and unconstrained — it is where the
  adjudicator says *why*.

Everything else in the section is free prose; the gate reads only the round
lines. The exact ERE the gate matches is
`^- \[round ([0-9]+)\] (PASS|REFUTED|ESCALATED|CONTESTED) tier=([a-z]+) stamp=([0-9a-f]{12})( — .*)?$`.

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
   `contest: allow`, which rides through with a loud stderr warning
   (`governance: CONTESTED verdict riding on <receipt> — sweep will
   re-adjudicate`). `REFUTED` and `ESCALATED` block.
5. **The stamp is fresh** — the latest round's stamp equals the stamp recomputed
   now. Otherwise: *stale verdict — the staged tree changed since adjudication*.

The honest limit worth naming: within a *single* pending commit, rounds that were
never committed have no base version to compare against, so the append-only guard
protects rounds from earlier commits, not rounds written and scrubbed between two
attempts at the same one. The sweep lane, which sees the merged result, is what
catches a log that was quietly pruned before it ever landed.

### The escalation ladder

Let *R* be the number of `REFUTED` rounds already logged and *K* the resolved
`SUBAGENT_ROUNDS` ceiling (default 3, floor 2). `attestation_remediation` renders:

| position | what the instruction says |
|---|---|
| *R* < *K*−1 | spawn an adjudicator at the directive's resolved attest tier |
| *R* = *K*−1 | the **escalation round** — spawn at the `high` tier, explicitly |
| *R* ≥ *K* | **STALLED**: do not spawn again. Append a terminal `ESCALATED` round and surface the dispute to a human. The commit stays blocked until the underlying work changes (or `contest: allow` lets a `CONTESTED` round through). |

The ladder exists so a genuinely disputed change escalates to a stronger model
once, then stops — rather than burning an unbounded number of adjudications, or
letting the agent grind against a rubric until something says PASS.

The instruction the harness receives spells out the round-line format, the
`_adjudication_stamp` invocation, the append-only rule, and the point that a
`PASS` recorded without actually checking the rubric against the ground truth is
exactly the failure the sweep lane re-adjudicates every one of these logs to
catch.

## Batched orchestration (issue #325)

Before #325 the harness spawned **one sub-agent per attested section** — N×
cost and latency when a commit owed several. The orchestration splits the gate
from the instruction:

- **`subagent_attest <receipt>`** — the per-directive gate a migrated `check.sh`
  calls. It reads the sibling `directive.yaml`'s `subagent:` block, runs the same
  presence + `PASS`/`REFUTED` check `require_attestation` does (so CI fails
  per-section, independently — unchanged), and when the section is pending
  **registers** it (section, isolation, resolved inputs, checks) into a shared
  ledger.
- **`attestation_remediation`** — the orchestrator, run **once** by `run.sh` and
  the generated pre-commit dispatcher after every `check.sh`. It reads the ledger
  and emits **one grouped remediation instruction**: a single sub-agent for all
  `isolation: shared` sections (handed the *union* of their inputs, asked for
  each verdict), plus one isolated sub-agent per `isolation: isolated` section.

Worst case (all isolated) = one spawn per section, as before. Best case (all
shared, the default) = **one spawn per commit** — a newly added receipt that owes
`## Audit`, `## Layer boundaries`, and `## Steering` is filled by one sub-agent.
The critical author≠auditor independence (the auditor is always a fresh context,
never the harness) is preserved in every case; only *inter-attestation*
independence is traded by batching, which a directive opts out of with
`isolation: isolated`.

## Executors: who renders the verdict (issue #355, Phase 3)

`gate: verdict` fixes *that* a verdict decides the commit. It says nothing about
**who renders it**. That is the `SUBAGENT_EXECUTOR` knob — operator-owned, same
conf ladder as every other one (env `GOVERNANCE_SUBAGENT_EXECUTOR` > user
overlay > pack `defaults.conf` > `harness`):

| executor | who judges | lane |
|---|---|---|
| `harness` (default) | a fresh-context sub-agent the **calling agent** spawns, driven by the grouped remediation instruction | commit |
| `cli:<adapter>` | a **separate command-line agent**, invoked by the hook itself through `.governance/runtimes/<adapter>.sh judge` | commit |
| `api:<provider>` | the sweep engine's HTTP judge | merge/scheduled — [SWEEP_FLOW.md](SWEEP_FLOW.md), not a commit-path value |

The commit path never makes a network call, so `api:` is not a
`SUBAGENT_EXECUTOR` value; it is what the sweep lane already does on the other
side of the merge.

### Why a different vendor's CLI is a real control

The default executor is one model family judging its own family's work:
independent *context*, shared *failure modes*. If the author model has a blind
spot — a class of scope creep it does not perceive as scope creep, a
rationalization pattern it finds convincing — its sibling adjudicator shares it.
Separation of duties is the standard answer, and it is only real when the two
parties do not come from the same place: `cli:codex` auditing Claude-authored
work (or the reverse) breaks the shared-failure-mode correlation in a way no
amount of prompt engineering inside one vendor can.

The second property is structural. A `cli:` judge is a **process**, not a
sub-agent of the author: it never sees the author's plan, its rationalizations,
or the running conversation, because **the prompt is built by `lib.sh`** out of
the directive's declaration and ground truth read from git — the diff, the
receipt — never out of anything the agent under audit wrote into its own
context. That prompt build is the baseline mitigation on **both** executors: even
on `harness`, the rubric comes from `directive.yaml`, and the ground truth is
fenced as untrusted data the judge must analyze, not obey (the same universal
contract the sweep lane's system prompt carries).

Neither executor makes in-context collusion *impossible* on the harness path —
the calling agent still spawns that sub-agent. `cli:` is what removes the
calling agent from the loop entirely.

### Configuration

| knob | default | effect |
|---|---|---|
| `SUBAGENT_EXECUTOR` | `harness` | `harness` or `cli:<adapter>`; an unrecognized value degrades to `harness` |
| `SUBAGENT_MODELS_LOW` / `_MEDIUM` / `_HIGH` | unset | the model a `cli:` executor runs that tier at; unset means the adapter's own default |

The adapters carry their per-tier defaults, not the kit — pinning someone else's
model catalog in kit code is a guarantee that goes stale. `claude-code.sh` maps
low/medium/high to the `haiku`/`sonnet`/`opus` CLI aliases; `codex.sh` leaves the
model unset so the Codex CLI's own configuration applies.

### What actually happens on a blocked commit

1. `_subagent_verdict_gate` fails (no log, a `REFUTED` latest round, a stale
   stamp, …).
2. If the resolved executor is `cli:<adapter>` **and** the gate is `verdict`,
   `lib.sh` builds the prompt, pipes it to `<adapter> judge <tier> <model>`,
   appends the returned round line to the section (with a freshly computed
   `stamp=`), stages the receipt, and **re-runs the gate once**. A `PASS` clears
   the commit in the same hook run; a `REFUTED` leaves it blocked with the round
   on the record.
3. Anything that goes wrong — no adapter file, no CLI on `PATH`, a transport
   error, an answer that is not a well-formed verdict — **degrades to the harness
   path**: the section is registered in the ledger with an executor of
   `cli:<adapter>+fallback`, and the grouped instruction carries a one-line
   warning so the operator learns their side channel is broken instead of
   reading the fallback as the executor working. An operator's misconfiguration
   must never be able to wedge a commit the default configuration would allow.
4. `gate: record` **never** takes this path. A record section is an authored
   narrative, not a verdict; there is nothing for a judge to decide.

Termination: one adjudication per `subagent_attest` call, and a budget of *K*
(the resolved `SUBAGENT_ROUNDS` ceiling) cli rounds per hook run, counted beside
the attest ledger so it spans the separate `check.sh` processes a dispatcher
runs. Past the budget the executor refuses to spend and hands over to the
harness path — a commit attempt always terminates.

### The adapter registry

One file per harness at `.governance/runtimes/<name>.sh`, kit-managed exactly
like `run.sh` and `lib.sh` (stamped with `kit-version=`, digested by
`managed-tree-integrity`, re-synced by `governance update`). "Which harness am I
talking to" is one fact about the repo, not a per-directive one, so the registry
is shared — but not every adapter implements every verb:

- **`judge [<tier>] [<model>]`** — read a fully-built prompt on stdin, run the
  CLI non-interactively, print `VERDICT: PASS|REFUTED` then zero or more
  `REASON:` lines. Exit 2 on a missing CLI, a transport failure, or an
  unparseable answer. Before exec'ing anything, an adapter strips the git
  plumbing (`GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`) and the harness session
  ids (`CLAUDE_CODE_SESSION_ID`, `CLAUDECODE`, `CODEX_THREAD_ID`, …) — a judge
  that inherits the author's session is not an independent judge, and it would
  bill the audit to the session under audit. Three adapters ship `judge`:
  `claude-code`, `codex`, and `manual`.
- **`resolve <session-id> [<declared-path>]` / `emit`** — off-commit-path
  session measurement for `agent-token-accounting` (issue #355): `resolve`
  reads an identity-pinned harness surface (a declared path, a session-id-named
  file under the harness's documented state dir, or a documented local server)
  and prints one usage line, or exits 2 when it cannot resolve; `emit` accepts
  the harness's own push payload (statusline/hook JSON) and appends a snapshot
  to the accounting sidecar. Seven adapters ship these:
  `claude-code`, `codex`, `pi`, `grok`, `cursor-agent`, `opencode`, and
  `manual`. See [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) for the
  accounting contract these verbs feed.

**No eval, no ship applies to executors too.** An executor lane that can only be
exercised by really spawning a paid CLI is an untested lane, so `manual` is a
first-class adapter and the kit's eval seam: `AGENT_JUDGE_VERDICT` /
`AGENT_JUDGE_REASON` supply the verdict, `AGENT_JUDGE_PROMPT_SINK` captures the
prompt the caller actually built, and an unset verdict reproduces exactly how a
missing vendor CLI presents. Every executor assertion in `scripts/test-subagent.sh`
runs through it, offline, in a throwaway repo.

One interaction to know about: a `cli:` executor **stages the receipt** mid-hook
(that is how the round it just wrote reaches the pending commit). A directive
that computed a coordinate over the staged tree at one hook stage and re-checked
it at a later stage would see the tree move underneath it, exactly as it does
when a harness remediation loop re-stages. The `_adjudication_stamp` above is
immune to this because it excludes the receipt from the tree it hashes, which is
why the executor is opt-in.

## Model tier: use a small model

The author-time attestation is a **bounded read-and-record audit**, not the
final word on truth — the verdict's correctness is independently re-derived by
the merge-time sweep lane at the high tier. So the attest pass runs on a
**small, low-cost model** (the *low* capability tier — e.g. Claude Haiku or a
comparable GPT-mini-class model). In Codex, that means spawning the attest
sub-agent with a mini-class model, not the primary session's larger model. This is a
deliberate cost optimization (issue #321): the audit fires on every newly added
attested artifact, and a cheap model can read the diff, compare it to the
artifact, and record a verdict. The grouped instruction names a **capability
tier** and, for current Codex runtimes, includes a mini-class hint so the
harness does not accidentally inherit the primary model. The auditor renders
the verdict as literally `PASS` or `REFUTED`; the gate matches that token
case-insensitively anywhere in the section.

The tier is the default, not a hard floor: a consumer who wants this directive's
author-time verdict run on a stronger model raises `SUBAGENT_TIERS_ATTEST` in the
conf overlay (issue #331, see *Author-owned vs operator-owned* above), and the
grouped instruction names the raised tier instead.

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
  directive can't declare a `subagent:` block.
- **`subagent_attest <receipt>`** (issue #325) — the declaration-driven gate.
  Reads the sibling `directive.yaml`'s `subagent:` block, runs the gate the
  block declares (`record` or `verdict`), and registers a pending section for the
  orchestrator. Returns 0 immediately on `sink: none`.
- **`attestation_remediation [<ledger>]`** (issue #325) — the orchestrator that
  emits the single grouped remediation instruction, including the escalation
  ladder for adjudicated sections; invoked once by `run.sh` / the pre-commit
  dispatcher.
- **`resolve_subagent_input <token> <receipt>`** (issue #325) — map a typed input
  token to its concrete handle phrase.
- **`_adjudication_stamp <receipt>`** (issue #355) — the freshness binding
  described above. Private to the kit, but deliberately callable standalone so a
  fresh-context adjudicator can compute the stamp it must record.
- **`_subagent_executor_resolve <id> <defaults>`** (issue #355) — the resolved
  executor (`harness` | `cli:<adapter>`), degrading to `harness` on anything
  unrecognized.
- **`_subagent_model_resolve <id> <defaults> <tier>`** (issue #355) — the
  `SUBAGENT_MODELS_<TIER>` override for a `cli:` executor, empty when the adapter
  should pick.
- **`_subagent_adapter <name>`** (issue #355) — path to
  `.governance/runtimes/<name>.sh`, honoring `GOVERNANCE_RUNTIMES_DIR`.
- **`_subagent_cli_prompt` / `_subagent_cli_adjudicate`** (issue #355) — the
  prompt build and the one-round adjudication described under *Executors*.

All of these are **pure bash + awk + git** as of issue #355 — the commit path
runs no python at all. That matters for a tool whose whole promise is that it
still works on a machine with nothing installed: the declaration reader
(`_subagent_yaml`, `_subagent_tier`) and the remediation formatter used to shell
out to stdlib python, and no longer do.

## Wiring a directive onto it

Declare the task in `directive.yaml` (the `subagent:` block above), then in a
change-set-scoped block of `check.sh` (only newly added artifacts owe the
attestation, exactly as `receipt-per-issue` scopes its `## Decisions` rule):

```sh
if declare -F subagent_attest >/dev/null 2>&1; then
    subagent_attest "$f"
else
    # Fallback on an older runtime lib.sh that predates the declaration-driven gate.
    require_attestation "$f" "Audit" "<why>" "<inputs>" "<check-1>" "<check-2>"
fi
```

## Versioning note

Because the helpers live in kit-owned `lib.sh`, a pack whose directive uses them
must declare a `min_governance_kit` floor at the kit version that **ships** them
— the first-shipped tag, not the in-development source-line marker. `require_attestation`
first shipped in `kit/v0.10.0`; `subagent_attest` / `attestation_remediation`
ship in the kit release that carries issue #325. A directive that declares
`gate: verdict`, `sink`, `contest`, or leans on `_adjudication_stamp` floors at
the release carrying issue #355 — an older `lib.sh` ignores the new keys and
gates on presence alone, which is a silent downgrade, not an error. See
[LIB_API.md](LIB_API.md#version-floor-obligation) and [VERSIONING.md](VERSIONING.md).

## See also

- [SWEEP_FLOW.md](SWEEP_FLOW.md) — the **sweep** mode: the off-path LLM-judge
  lane that re-derives recorded verdicts at the high tier and files a digest.
- [LIB_API.md](LIB_API.md) — the full `lib.sh` helper surface, with signatures
  and landed-in versions.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — patterns for writing checks.
- [PHILOSOPHY.md](PHILOSOPHY.md) — receipts over transcripts.

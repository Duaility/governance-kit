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
  tiers:   { attest: low, sweep: high }
```

- **`inputs`** — typed tokens resolved to concrete handles by `resolve_subagent_input`:
  `diff`→`git diff`, `receipt`→the receipt path, `issue`→`gh issue view #N`
  (derived from the receipt name), `transcript`→the session JSONL named
  `$CLAUDE_CODE_SESSION_ID.jsonl`, `layer-map`→the doc named by
  `GOVERNANCE_LAYER_DOC`. An unknown token passes through verbatim.
- **`checks`** — the numbered rubric the judge adjudicates (the prose rubric is
  the directive's `constitution.md`).
- **`isolation`** — `shared` (default) lets the commit-time orchestrator batch
  this section with other `shared` sections into one sub-agent; `isolated` forces
  its own sub-agent (use when inter-attestation independence — avoiding a halo
  effect across verdicts — matters).
- **`section`** — the `## <Section>` the verdict is written into.
- **`tiers`** — the capability tier each mode runs at: `attest` low, `sweep` high.

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

Two honest limits this pattern owns rather than hides:

- **It records; it does not adjudicate.** `check.sh` verifies the section
  *exists and is verdict-bearing*, never that the verdict is *true*. Trusting the
  verdict is the sweep lane's job. The commit-path guarantee is "the audit was
  recorded," not "the audit passed."
- **Harness-only authoring.** A bare human commit or a CI run has no agent to
  spawn anything, so `check.sh` simply hard-fails on the missing section —
  correct (the audit step did not run); the hook can *demand* the section, never
  *manufacture* it.

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

## Model tier: use a small model

The author-time attestation is a **bounded read-and-record audit**, not the
final word on truth — the verdict's correctness is independently re-derived by
the merge-time sweep lane at the high tier. So the attest pass runs on a
**small, low-cost model** (the *low* capability tier — e.g. Claude Haiku or a
comparable GPT-mini-class model). This is a deliberate cost optimization (issue
#321): the audit fires on every newly added attested artifact, and a cheap model
can read the diff, compare it to the artifact, and record a verdict. The grouped
instruction names a **capability tier**, not a pinned model id, and asks the
auditor to render the verdict as literally `PASS` or `REFUTED`; the gate matches
that token case-insensitively anywhere in the section.

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
  Reads the sibling `directive.yaml`'s `subagent:` block, runs the presence +
  verdict gate, and registers a pending section for the orchestrator.
- **`attestation_remediation [<ledger>]`** (issue #325) — the orchestrator that
  emits the single grouped remediation instruction; invoked once by `run.sh` /
  the pre-commit dispatcher.
- **`resolve_subagent_input <token> <receipt>`** (issue #325) — map a typed input
  token to its concrete handle phrase.

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
ship in the kit release that carries issue #325. See
[LIB_API.md](LIB_API.md#version-floor-obligation) and [VERSIONING.md](VERSIONING.md).

## See also

- [SWEEP_FLOW.md](SWEEP_FLOW.md) — the **sweep** mode: the off-path LLM-judge
  lane that re-derives recorded verdicts at the high tier and files a digest.
- [LIB_API.md](LIB_API.md) — the full `lib.sh` helper surface, with signatures
  and landed-in versions.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — patterns for writing checks.
- [PHILOSOPHY.md](PHILOSOPHY.md) — receipts over transcripts.

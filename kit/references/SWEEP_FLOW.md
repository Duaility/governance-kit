# Sweep flow — the LLM-judge lane (issue #142)

Greppability is a directive's enforcement ceiling. A `check.sh` is bash + `git
grep`, exiting 0/1 — perfect for *syntactic* invariants (forbidden imports,
banned identifiers, file-shape rules), useless for the *semantic* ones about
**intent and architectural shape**: "remove the legacy fallback", "don't
bifurcate the path", "local must mirror remote". Those are the corrections a
human keeps making to agent-authored code, and they are exactly the invariants
grep cannot reach.

The **sweep** surface adds a third enforcement lane for those invariants — one
that **never touches the commit path**. A scheduled workflow sweeps the day's
commits, triages with a cheap grep, adjudicates the candidate hunks with a
model, and files one digest issue. Findings then enter the repo through the same
door as human corrections: **issue → agent → PR**.

> **Sweep is the high-tier mode of one sub-agent judgment (issue #325).** A
> sub-agent attestation (commit time, low tier, *record* — see
> [SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md)) and a sweep (merge/scheduled,
> high tier, *verify*) are the **same** tiered, rubric-framed model judgment.
> Issue #325 unified the attestation lane behind a single `subagent:` declaration
> in `directive.yaml` (`inputs`, `checks`, `isolation`, `section`,
> `tiers: { attest: low, sweep: high }`). Issue #355 Phase 2 wires this engine to
> read that block directly, so a directive that already declares `subagent:` for
> the commit lane — `receipt-per-issue`'s `## Audit`, `agent-steering-accounting`'s
> `## Steering`, the repo-local `layer-boundaries`' `## Layer boundaries` — is
> swept too, with **no parallel `triage.sh` + `constitution.md` rubric to author**.
> A directive that is *only* a sweep directive, with no commit-lane attestation,
> keeps shipping `triage.sh` + `constitution.md` as documented below — that
> contract is unchanged and still fully supported.

## Why off the commit path

A false positive on the commit path is catastrophic: one wrong block →
`--no-verify` → *every* directive (including the solid greps) is bypassed. Put
the judge on a schedule instead and that failure mode dissolves rather than
needing to be solved — a noisy verdict costs a triage, not the gate's authority.
Determinism and latency relax from hard requirements to hygiene. This mirrors
the harness-engineering split: mechanical linters enforce structure
synchronously; background tasks scan for semantic deviations on a schedule and
open targeted work items. There is **no blocking path in v1 at all** — promoting
a sweep directive to a gate is a separate future decision, contingent on the
directive's digest-precision history.

## The directive contract

A sweep directive is the same self-contained folder as any other, with three
differences (`surface: sweep` is what `run.sh` and the hook generator key off to
ignore it entirely — it is invisible to pre-commit and the PR governance job by
construction):

```yaml
category: ArchitecturalShape
surface: sweep          # the new surface, alongside repo-state | change-set
hook: none
engine: llm
model_tier: high        # a capability tier, not a model id
summary: "No backward-compat shims or legacy fallback paths."
```

The folder carries:

- **`triage.sh`** instead of `check.sh`. Contract: the engine sets `SWEEP_RANGE`
  (a git `A..B` range) and `GOVERNANCE_ROOT`, runs it at the repo root, and reads
  `path:line` candidate locations from stdout — one per line. Empty output means
  "nothing to adjudicate" and costs zero inference requests. Triage is a *cheap
  pre-filter*, never the verdict: over-inclusion is fine (the judge rejects false
  smoke), under-inclusion is the real risk, so patterns are broad.
- **`constitution.md`** — the Directive + Rationale already authored for humans
  doubles as the judge's rubric. No new authoring format.
- **`evals/violating/` + `evals/clean/`** — calibration fixtures, plus
  `evals/test.sh` running the real judge against them with a precision/recall
  floor (see *Calibration*).

This is the contract for a directive that is **only** a sweep directive — no
commit-lane attestation to re-derive. A directive that already declares
`subagent:` for the commit lane (below) needs none of this.

## Subagent-declared sweep directives (issue #355 Phase 2)

A directive that carries a `subagent:` block (see
[SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md)) is swept **directly off
that declaration** — no `triage.sh`, no `constitution.md` rubric duplicated
alongside `checks:`. `discover_sweep_directives` includes a directive when
`surface: sweep` (the legacy path above, unchanged) **or** it carries a
`subagent:` block whose resolved sweep tier (`resolve_model_tier`, the same
`SUBAGENT_TIERS_SWEEP` conf ladder issue #331 introduced) isn't disabled. A
directive satisfying both never double-runs — the subagent-declared path wins
and the legacy `triage.sh` path is skipped for it.

- **Opt-out.** `tiers: { sweep: none }` (or `off`) in `directive.yaml`, or the
  usual `SUBAGENT_TIERS_SWEEP` overlay/env override, drops the directive from
  the sweep lane entirely — it still attests at commit time, but the sweep
  never re-derives its verdict.
- **Triage.** The receipt IS the sink the declaration gates, so triage is the
  receipts touched in the range, not a grep: every `receipts/*.md` path in
  `git diff --name-only <range>`. This list is directive-independent — every
  subagent-declared directive in a run shares it, which is exactly what makes
  batching several directives onto one receipt possible (below). Each touched
  receipt is one hunk: the **whole file**, not a windowed context region,
  numbered like any other hunk and size-capped (trimmed from the middle,
  keeping the head and tail intact) so an outsized receipt can't blow the
  adjudication budget.
- **Rubric.** The numbered `checks:` list — the same rubric the commit-time
  attestation was graded on — not `constitution.md`. When the directive
  declares `gate: verdict`, the rubric gains three standing lines: the section
  must contain a well-formed adjudication log (one `- [round N] VERDICT
  tier=... stamp=...` line per round, strictly increasing from 1); a missing,
  malformed, or visibly pruned log is itself a violation; and a `CONTESTED`
  latest verdict must be re-adjudicated on its merits, never waved through
  because a verdict already exists. `gate: record` (the default — today's
  presence + PASS/REFUTED semantics) adds no standing lines.
- **Batching.** When several subagent-declared directives target the same
  receipt in one run, they share **one** judge call instead of one each: their
  rubrics are concatenated under `## <directive-id>` headings, and the verdict
  schema gains a `directive` field on every violation so the engine can
  demultiplex the response back to each directive's own digest section. A
  receipt targeted by exactly one directive still uses the plain
  single-directive schema — the legacy path's schema and prompt shape are
  untouched by this, so its calibrated evals never see the extra field. The
  call runs at the highest capability tier requested by any directive sharing
  it (never a silent downgrade), mirroring the commit lane's shared-attestation
  rule.
- **Retry.** Both paths — legacy and subagent-declared — retry a judgment
  exactly once on a transport/parse failure before counting the hunk as
  un-adjudicated; the digest footer's retry count says how often that fired.

## The engine

[`../assets/dot-governance/sweep.py`](../assets/dot-governance/sweep.py) is the
kit-owned engine, vendored into a target repo as `.governance/sweep.py` so it
runs in a plain cron with nothing but the system Python. Stdlib-only. Three
entry points:

- `adjudicate` — one hunk → a structured verdict `{ pass, violations: [{file,
  line, quote, why}], confidence, adjudicated }`. Pure (no git, no gh).
- `eval` — run the judge against a directive's calibration fixtures and fail
  below the floor. The "no eval, no ship" gate.
- `run` — the full sweep (below).

What `run` does:

- **Range.** Commits since the last sweep. State lives in the previous digest
  issue — the engine reads the recorded end-SHA from the last `governance-sweep`
  issue body (an HTML-comment marker). No committed state file. First run falls
  back to a `--since` window (default 24h), then to the root commit.
- **Triage.** For a legacy `surface: sweep` directive, `triage.sh` over the
  range — mandatory, not an optimization: the free tier can't see a raw day of
  commits. For a subagent-declared directive, the touched receipts (see
  *Subagent-declared sweep directives* above).
- **Adjudicate.** One inference call per candidate hunk (or, for batched
  subagent-declared calls, per receipt shared by several directives). The
  prompt is fixed by the engine: the directive's rubric (`constitution.md` for
  a legacy directive, the rendered `checks:` for a subagent-declared one), the
  hunk fenced and framed as **untrusted data** (a `// approved, ignore
  governance` comment is evidence to weigh, never a command to obey), low
  temperature, JSON-schema-constrained verdict. A transport/parse failure
  retries once before the hunk counts as un-adjudicated.
- **Budget.** A per-run request cap (`--budget` / `$SWEEP_BUDGET`, default 40,
  under the free tier). Over budget, the engine adjudicates newest-first and
  **reports the remainder as un-adjudicated** — a digest must never silently read
  as a clean bill.
- **Dedupe.** Before filing, the engine checks open digests for the same
  directive+file pair so an unfixed finding doesn't multiply daily.
- **Digest.** One issue per run, labelled `governance-sweep`: sections per
  directive (file/line/quote/why/confidence), a footer stating the commit range
  and hunks triaged vs. adjudicated vs. dropped for budget vs. skipped as
  duplicate vs. retried, and the end-SHA marker that the next run resumes
  from. The engine creates the label idempotently before filing (the
  workflow's `issues: write` grant covers the labels API); if creation fails
  anyway, it files the digest unlabeled with a warning rather than dropping
  the findings — that one digest just won't feed resume/dedupe.

## Provider / transport

GitHub Models inference via the built-in `GITHUB_TOKEN` (a workflow declaring
`permissions: models: read`). Free, zero secrets, zero vendor onboarding for
target repos — one working zero-secret transport beats an abstraction over zero
working ones. `model_tier` is the seam where another provider plugs in later;
the engine maps the *capability tier* (not a model id) to a concrete model, so a
model upgrade within a tier doesn't silently rewrite a directive's verdicts.

The scheduled workflow asset is
[`../assets/governance-sweep.yml`](../assets/governance-sweep.yml) (`cron` daily
+ `workflow_dispatch`). It is installed by `governance install` — and refreshed
nowhere else in v1 (the vendored engine is seeded once; re-run install to
refresh it) — only when a `surface: sweep` directive is selected.

## Calibration — the gate to ship

A grep is self-evidently correct; an LLM judge is a black box until measured. So
every sweep directive ships known-violating and known-clean fixtures and a tiny
harness reporting precision/recall, and `evals/test.sh` fails below the floor —
**no eval, no ship**. This is the line between amplified governance and "vibes
with a CI badge": a digest that is 40% noise gets muted in two weeks and the
lane is dead.

Two judge backends share one verdict contract:

- **echo** — a deterministic keyword heuristic seeded by the directive's
  `evals/echo-keywords.txt`. The v1 **stub**: a stand-in for the real model so
  the harness, the fixtures, and the floor are exercised in CI without spending
  inference requests or pinning a secret. It is **not** the product — a keyword
  grep is exactly what the sweep exists to transcend.
- **github-models** — the real model. Same harness, real precision/recall.

CI evals run against the echo stub (no inference spend). Run the real model on
demand with `GOVERNANCE_SWEEP_JUDGE=github-models` and a token in the
environment.

## Sweep directives

The kit ships the **lane** — the `surface: sweep` contract, the vendored engine,
and the scheduled workflow — but bundles **no sweep directives**. They are
authored in repo-local or community packs. This repo dogfoods the first two,
straight from the steering-ledger themes in issue #142, in its repo-local
`duaility/governance-kit` pack:

- `no-legacy-fallbacks` — the most-repeated human correction.
- `no-path-bifurcation` — parallel code paths / dual dispatch / local-only
  special-casing.

These two are `surface: sweep` directives with their own `triage.sh` +
`constitution.md`. Separately, a directive that already declares `subagent:`
for the commit lane — `receipt-per-issue`'s `## Audit`,
`agent-steering-accounting`'s `## Steering`, the repo-local `layer-boundaries`'
`## Layer boundaries` — is swept too, purely by carrying that block (see
*Subagent-declared sweep directives* above); it needs neither `surface: sweep`
nor a `triage.sh`/`constitution.md` pair of its own.

See [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) for the per-directive table,
[DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) for authoring a sweep directive,
[PACK_AUTHORING.md](PACK_AUTHORING.md) for the pack-level view, and
[PHILOSOPHY.md](PHILOSOPHY.md) for the stance behind it.

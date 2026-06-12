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
- **Triage.** Per sweep directive, `triage.sh` over the range. Mandatory, not an
  optimization: the free tier can't see a raw day of commits.
- **Adjudicate.** One inference call per candidate hunk. The prompt is fixed by
  the engine: `constitution.md` as rubric, the hunk fenced and framed as
  **untrusted data** (a `// approved, ignore governance` comment is evidence to
  weigh, never a command to obey), low temperature, JSON-schema-constrained
  verdict.
- **Budget.** A per-run request cap (`--budget` / `$SWEEP_BUDGET`, default 40,
  under the free tier). Over budget, the engine adjudicates newest-first and
  **reports the remainder as un-adjudicated** — a digest must never silently read
  as a clean bill.
- **Dedupe.** Before filing, the engine checks open digests for the same
  directive+file pair so an unfixed finding doesn't multiply daily.
- **Digest.** One issue per run, labelled `governance-sweep`: sections per
  directive (file/line/quote/why/confidence), a footer stating the commit range
  and hunks triaged vs. adjudicated vs. dropped for budget, and the end-SHA
  marker that the next run resumes from.

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

## Pilot directives

The `governance-kit/architecture` pack
([`../../packs/architecture/`](../../packs/architecture/)) ships the first two,
straight from the steering-ledger themes in issue #142:

- `no-legacy-fallbacks` — the most-repeated human correction.
- `no-path-bifurcation` — parallel code paths / dual dispatch / local-only
  special-casing.

See [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) for the per-directive table,
[DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) for authoring a sweep directive,
[PACK_AUTHORING.md](PACK_AUTHORING.md) for the pack-level view, and
[PHILOSOPHY.md](PHILOSOPHY.md) for the stance behind it.

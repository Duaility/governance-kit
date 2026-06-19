# Issue #338 — match docs-site tone to the README's problem-first voice

The published docs site opened several narrative pages in a product register
or with dry "This page covers…" meta-introductions, while the README frames
each section developer-to-developer — felt problem first, then the solution.
This change brings the site's narrative entry points up to that voice without
rewriting the reference-grade page bodies.

## Checklist

- [x] Rewrite the docs landing page (`docs/index.mdx`) intro to lead with the problem before the solution
- [x] Reframe the constitution concept-page (`docs/concepts/constitution.mdx`) opener to hook on the felt problem
- [x] Reframe the runtime concept-page (`docs/concepts/runtime.mdx`) opener to hook on the felt problem
- [x] Reframe the packs concept-page (`docs/concepts/packs.mdx`) opener to hook on the trust problem

## What changed

- **Rewrite the docs landing page (`docs/index.mdx`) intro to lead with the problem before the solution** —
  the first prose paragraph previously opened on the solution ("Coding agents
  author most of the changes now… Your repository's rules live in a versioned
  `CONSTITUTION.md`"). It now opens on the felt failure — agents finishing work
  that is "locally fine and globally wrong", the repo drifting, the correction
  re-taught — then splits into a second paragraph that introduces Governance Kit
  as the fix, preserving the existing install/runtime sentence verbatim.
- **Reframe the constitution concept-page (`docs/concepts/constitution.mdx`) opener to hook on the felt problem** —
  replaced the bare "`CONSTITUTION.md` is the declarative description… This page
  covers…" opener with a hook on the durable-home problem (the correction you
  keep re-teaching needs somewhere the rule and its test can't drift apart),
  then retains the "This page covers…" sentence as the second clause.
- **Reframe the runtime concept-page (`docs/concepts/runtime.mdx`) opener to hook on the felt problem** —
  replaced the bare "This page traces what actually happens…" opener with a hook
  on trusting the gate (worth knowing what runs in that gap before you trust it
  to gate your work), keeping the same scope sentence.
- **Reframe the packs concept-page (`docs/concepts/packs.mdx`) opener to hook on the trust problem** —
  replaced "Directives ship in **packs**… This page covers…" with a hook on the
  trust question (a pack is code someone else wrote that gets to block your
  commits), then folds the pack definition and vendoring into the same paragraph.

## Out of scope

- Task pages — `docs/guide/quickstart.mdx`, `docs/guide/installation.mdx`,
  `docs/guide/configuration.mdx` — open with direct task instructions, which is
  the right register; not touched.
- Pages already in the target voice — `introduction.mdx`, `audit-chain.mdx`,
  `limitations.mdx`, `troubleshooting.mdx`, `mental-models.mdx` — left as-is.
- Generated `docs/reference/*.mdx` — rendered from `kit/references/*` by the docs
  generator and must not be hand-edited; not touched.

## Decisions

- Edited only the **opening** of each affected page, not the bodies. The concept
  pages' bodies are reference-grade technical prose; rewriting them in a chattier
  voice would cost precision for no tone gain. The user's ask was about the
  framing/voice of how each page leads, which the openers carry.
- Did not force a problem-first hook onto the task pages. A manufactured problem
  statement ahead of install steps slows the reader; "same tone" there means the
  same plain developer-to-developer register, which they already have.

## Verification

The four affected intros now lead with the problem, and no generated reference
page was touched (so `docs:gen:check` is unaffected):

```sh
grep -q "locally fine and globally wrong" docs/index.mdx
grep -q "needs somewhere durable to live" docs/concepts/constitution.mdx
grep -q "what runs in that gap before you trust it" docs/concepts/runtime.mdx
grep -q "code someone else wrote that gets to block your commits" docs/concepts/packs.mdx
test -z "$(git diff --name-only origin/main -- docs/reference)"   # no generated pages changed
bash .governance/run.sh                                            # full directive suite green
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-fd491296-123-1781839400-1 | claude-code | fd491296-123f-4e48-aba3-db24dabad873 | #338 | claude-opus-4-8 | 76002 | 494077 | 4598381 | 86996 | 657075 | 7.9421 | 76002 | 494077 | 4598381 | 86996 | docs: match docs-site tone to the README's problem-first voice (#338) |
| claude-code-fd491296-123-1781839610-1 | claude-code | fd491296-123f-4e48-aba3-db24dabad873 | #338 | claude-opus-4-8 | 6615 | 33426 | 1115070 | 11463 | 51504 | 1.0861 | 82617 | 527503 | 5713451 | 98459 | docs: match docs-site tone to the README's problem-first voice (#338) |
| claude-code-fd491296-123-1781839757-1 | claude-code | fd491296-123f-4e48-aba3-db24dabad873 | #338 | claude-opus-4-8 | 280 | 21228 | 1472365 | 9862 | 31370 | 1.1168 | 82897 | 548731 | 7185816 | 108321 | docs: match docs-site tone to the README's problem-first voice (#338) |

### Steering

_No steering rows — see the `## Steering` verdict below._

## Steering

Verdict from a fresh-context sub-agent that read the session transcript
(`fd491296-123f-4e48-aba3-db24dabad873.jsonl`) and this receipt, applying the
`agent-steering-accounting` definition (a steering event is an interrupt, or a
user message that redirects/corrects the agent mid-task; ordinary new task
requests, questions, and tool-permission denials are **not** steering).

**Verdict: PASS.**

- **Check 1 — every steering event is recorded as a row: PASS.** No
  human-steering events were found. The transcript's user turns are: (a) the
  initial tone-rewrite task, (b) "now follow the same tone across all pages" (a
  scope expansion / new request), and (c) the create-PR command. None is an
  interrupt (no `Request interrupted by user` marker) and none redirects or
  corrects the agent mid-task — each is a new task or directive. Zero steering
  rows appended.
- **Check 2 — no non-steering message recorded: PASS.** No rows were added to
  `### Steering`, so no ordinary task message or directive was mistakenly logged
  as a steering event.

## Layer boundaries

The change set touches only `docs/` (published site narrative, hand-authored) and `receipts/` (receipt record). These lie outside the three-layer architecture (skill/ → kit/ → packs/) entirely; they are documentation and record artifacts, not code that moves between layers.

**Verdict: PASS.**
- **Check 1 (file placement in correct layer)**: PASS — All four modified `.mdx` files are under `docs/concepts/` and `docs/index.mdx`, which is the published narrative surface, not kit engine logic or pack directives. The new receipt is at `receipts/`, the designated record folder. No file sits in the wrong layer.
- **Check 2 (no wrong-way dependencies)**: PASS — Documentation pages cannot depend on code; they describe it. No skill code is placed in kit/, no kit logic in packs/, no upward edges. The four narrative rewrites have no code dependencies at all.
- **Check 3 (shared logic in the right layer, not duplicated)**: PASS — This change introduces no new shared logic. It is a prose rewrite of four page openers. No duplication across layers is introduced.

## Audit

The staged diff rewrites the opening prose of four documentation pages and adds a receipt file with full `## Checklist`, `## What changed`, `## Out of scope`, `## Decisions`, `## Verification`, and `## Accounting` sections.

**Verdict: PASS.**
- **Check 1 (`## What changed` faithful to the diff)**: PASS — The receipt's `## What changed` section accurately describes all four file edits: `docs/index.mdx` (split into problem-then-solution paragraphs), `docs/concepts/constitution.mdx` (replaced bare opener with felt-problem hook), `docs/concepts/runtime.mdx` (hooked on trusting the gate), `docs/concepts/packs.mdx` (hooked on the trust question). No omissions or misrepresentations.
- **Check 2 (checklist items realized in the diff)**: PASS — All four checkboxes marked `[x]` in the receipt's `## Checklist` correspond to real line changes: index intro paragraph split ✓, constitution opener reframed ✓, runtime opener reframed ✓, packs opener reframed ✓.
- **Check 3 (receipt checklist mirrors issue #338)**: PASS — The receipt's four checklist items match the issue's four checklist items exactly (word-for-word in order): Rewrite landing page, reframe constitution, reframe runtime, reframe packs.

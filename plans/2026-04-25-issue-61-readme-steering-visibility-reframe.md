# Plan: README reframe around steering + visibility, promote ledgers

Tracks issue #61.

## Context

After issue #59 landed the macro/loop diagrams and the dev-facing pitch, two structural problems remained in the README. The Why section framed governance-driven development around steering only ("less typing, more steering") — accurate as far as it went, but misses the second half of the pitch: once agents ship most of the diffs, **visibility** matters as much as steering. governance-kit already delivers it (`CONSTITUTION.md` evolution log, `COSTS.md`, `STEERING.md`), but the section that names this — "Transparency" — was buried at line 154, below Verbs and Core pack.

Two reader-friction issues compounded:

1. **The pitch was buried.** Transparency *is* the pitch. A reader landing cold saw "Anatomy of a directive" → "Verbs" → "Core pack" before they ever saw the visibility story.
2. **The macro diagram was wrong.** It showed the human only as the constitution's author, with no edge to the agent and no STEERING.md node. The user flagged this directly: "human role is not just authoring constitution, coding agents create PR which needs human review and human inputs are being stored in STEERING.md".

## Changes

1. **Why section reframed** around two problems — **Steering** (durable rules in `CONSTITUTION.md` + per-turn capture in `STEERING.md`) and **Visibility** (three append-only ledgers, all git-native, read instead of diffs). Drops the "two jobs at once" bullet list; the closing line preserves the original punch ("agents do the work; the constitution sets the bounds; the directives keep both sides honest") and extends it for the new framing.
2. **Macro mermaid diagram redrawn.** `H` now has two thick edges — `amends` (to `CONSTITUTION.md`) and `reviews, steers` (to `Agent`). All three ledgers (`CONSTITUTION.md`, `STEERING.md`, `COSTS.md`) are first-class nodes. `Agent -.-> STEERING & COSTS` captures logging. `C & S & Co -.-> H` collapses the read-back into one edge.
3. **"Transparency" promoted to "Visibility"** and moved to right after the Why. Same content, sharper section title, and the per-ledger bullets now lead with the artifact name (`Directive provenance` (`CONSTITUTION.md`), `Token cost` (`COSTS.md`), `Human steering` (`STEERING.md`)) rather than the abstract noun.
4. **"How it ships" consolidates** the former Anatomy + Verbs + Core pack sections into one heading, demoted below the pitch. Reader sees the pitch land before the implementation detail starts.
5. **Quickstart sharpened.** New trailing line: "The agent reads the id + rationale and self-corrects on the next attempt." — connects the failing-commit demo to the steerable thesis.
6. **"Why not pre-commit / husky / lefthook"** tightened. Same content, fewer words.

Out of scope:

- The two mermaid diagrams (macro + inner loop). Macro was redrawn for this PR; inner loop is unchanged.
- Adding a new diagram for the "three ledgers" — the Visibility section's prose carries that on its own; an extra diagram would be redundant after the macro picture already lists all three nodes.

## Validation

- `bash .governance/run.sh` passes (no directive regressions).
- Macro diagram renders cleanly on GitHub — `A -.->|"logs"| S & Co` and `C & S & Co -.->|...| H` are mermaid's multi-target shorthand and need a render check before merge.
- Cold-read: a developer reaching the README sees the steering + visibility framing within the first screen of Why, the three ledgers immediately after, and no implementation detail before they've been sold.

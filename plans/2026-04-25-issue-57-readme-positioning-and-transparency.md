# Plan: README positioning sharpening + Transparency section

Tracks issue #57.

## Context

The README opens with a philosophy statement ("Frontier models do the work. You set the direction.") and walks the reader through three paragraphs of theory before any concrete payoff. For an engineer running agents heavily — the actual target audience — the steering-signal pain is visceral and the README never names it. Two angles in particular are missing from the cold-read:

1. **Audience positioning.** Nothing tells a non-agent-heavy reader they're in the wrong place, and nothing tells an agent-heavy reader they're in the right one. spec-kit is the natural sibling for the "spec-drive a feature, agent implements" workflow; governance-kit is the layer above — for the rules that must hold across every commit, forever.
2. **Transparency is unsurfaced.** The `agent-governance` pack ships token accounting (`COSTS.md` + trailers) and steering accounting (`STEERING.md` + trailers). For the agent-heavy reader these are top-tier value props — "every commit has a price tag, and you can see which ran on autopilot vs needed your hand" — and the README mentions neither.

## Changes

1. **Spec-kit callout** — `> [!NOTE]` block immediately after the npx-skills paragraph and before the first `---`. One sentence naming the audience, one pointing readers building for spec-driven workflows to spec-kit, one stating what governance-kit is the layer above.
2. **Transparency section** — new H2 placed before Core Philosophy, with three bullets (directive provenance / token accounting / steering accounting) and a one-line note that the latter two ship in the `agent-governance` pack while provenance is core.

Both edits are README-only. No directive, test, hook, or pack file changes.

## Out of scope

- Reordering "What is governance-driven development?" to lead with the agent feedback loop.
- Pulling "Agents are authors, not bypass routes" + "Rationale is alignment data" up from Core Philosophy into the lede.
- Defining the Evolution Log inline (currently a dangling reference).
- Reworking the "Why not just pre-commit / husky / lefthook?" FAQ to position against spec-kit instead.

These were discussed during scoping and deferred to a follow-up so this change stays small and reversible.

## Validation

- `bash tests/governance/run.sh` passes (no directive regressions).
- `npx skills` still resolves the README's install snippet to a working install path.
- The two new sections render correctly on GitHub (`[!NOTE]` callout, anchor link `#community-packs`).
- Manual cold-read: an agent-heavy engineer reaching the README sees the audience signal in the first screen and the transparency claim before the philosophy section.

# Plan: README positioning sharpening + Transparency section

Tracks issue #57.

## Context

The README opens with a philosophy statement ("Frontier models do the work. You set the direction.") and walks the reader through three paragraphs of theory before any concrete payoff. For an engineer running agents heavily — the actual target audience — the steering-signal pain is visceral and the README never names it. Two angles in particular are missing from the cold-read:

1. **Audience positioning.** Nothing tells a non-agent-heavy reader they're in the wrong place, and nothing tells an agent-heavy reader they're in the right one. spec-kit is the natural sibling for the "spec-drive a feature, agent implements" workflow; governance-kit is the layer above — for the rules that must hold across every commit, forever.
2. **Transparency is unsurfaced.** The `agent-governance` pack ships token accounting (`COSTS.md` + trailers) and steering accounting (`STEERING.md` + trailers). For the agent-heavy reader these are top-tier value props — "every commit has a price tag, and you can see which ran on autopilot vs needed your hand" — and the README mentions neither.

## Changes

Round 1 (already landed):

1. **Spec-kit callout** — `> [!NOTE]` block immediately after the npx-skills paragraph and before the first `---`. One sentence naming the audience, one pointing readers building for spec-driven workflows to spec-kit, one stating what governance-kit is the layer above.
2. **Transparency section** — new H2 placed before Core Philosophy, with three bullets (directive provenance / token accounting / steering accounting) and a one-line note that the latter two ship in the `agent-governance` pack while provenance is core.

Round 2 (this revision):

3. **Rewrite "What is governance-driven development?"** to lead with concrete pain (`CLAUDE.md` drift, agent forgets, hooks-without-why, scattered steering signal) before the reframe. The reframe defines the **atomic triple** as a one-liner — directive folder + `CONSTITUTION.md` subsection + Evolution Log entry — and inlines a definition of the Evolution Log so it stops being a dangling reference.
4. **Add an agent-feedback-loop diagram** — a fenced four-step block showing how rationale-as-alignment-data closes the loop: agent reads `CONSTITUTION.md`, writes code, hook fails with directive id + rationale, agent self-corrects on principle.
5. **Pull "Rationale is alignment data" + "Agents are authors, not bypass routes"** out of the Core Philosophy bullet list and into the new GDD section as flowing prose. The remaining Core Philosophy section is removed — its other two bullets ("Agents execute. Humans steer." / "Direction evolves atomically.") are already covered by the lede tagline and the new atomic-triple paragraph respectively.
6. **Tie the Evolution Log into Transparency.** The existing "Directive provenance" bullet now names the Evolution Log explicitly as the human-readable amendment record that complements `git blame`.

Out of scope for this PR (deferred again):

- Reworking the "Why not just pre-commit / husky / lefthook?" FAQ to position against spec-kit instead — the spec-kit callout up top now handles the more important neighbor framing, so the FAQ can stay as-is.

## Validation

- `bash tests/governance/run.sh` passes (no directive regressions).
- `npx skills` still resolves the README's install snippet to a working install path.
- The two new sections render correctly on GitHub (`[!NOTE]` callout, anchor link `#community-packs`).
- Manual cold-read: an agent-heavy engineer reaching the README sees the audience signal in the first screen and the transparency claim before the philosophy section.

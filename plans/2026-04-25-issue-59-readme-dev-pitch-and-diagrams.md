# Plan: README dev-facing pitch tightening + macro/loop diagrams

Tracks issue #59.

## Context

Issue #57's README pass landed the audience positioning (spec-kit callout) and the Transparency section, but the body of the "Why governance-driven development?" section still leaned on internal jargon — "atomic triple", "alignment data" — and walked the reader through file-drift mechanics before the macro stakes. For a developer reading cold, the actual pitch (agents now do the engineering work; humans need a way to steer at scale; a constitution made of directives is that way) was buried under structural detail.

Two reader frictions in particular:

1. **"Atomic triple" reads as loaded.** It names a real invariant the kit enforces, but the term carries no intuition for a first-time dev reader and the prose around it focused on mechanism (test + rationale + log entry land in one commit) rather than payoff (you can reason about your system from the directives without reviewing every diff).
2. **No visual.** The original section had an ASCII feedback-loop diagram which got cut in an earlier tightening pass; nothing took its place, so the section is wall-of-prose for a reader who wants the picture before the argument.

## Changes

1. **Lede tightened.** `governance-kit codifies your repo's directives, guidelines, and principles as the steering signal AI coding agents actually read…` → `governance-kit turns your repo's rules into a versioned constitution — read by every agent, enforced on every commit.` Halves the length and stops competing with the section heading below it.
2. **"Why governance-driven development?" rewritten.** Opens with the macro shift (agents do the work, humans steer; steering doesn't scale through code review threads or another `CLAUDE.md` bullet), names the artifact (constitution composed of directives), then explains the dual role: operating instructions for the agent, shape lens for the human. Closing line names why this works now (frontier-model agents read rationale and generalize). Drops the "atomic triple", "alignment data", and file-drift framing — the mechanics live in Anatomy of a directive and in the Verbs IMPORTANT block instead.
3. **Macro mermaid diagram in the Why section.** `Human → CONSTITUTION.md → Agent → Repo`, with dotted feedback arrows from the constitution to both the repo (`checks every commit`) and the human (`read directives, not diffs`). Drives home the dual-audience point visually.
4. **Loop mermaid diagram in Anatomy of a directive.** `Reads directive + rationale → writes code → check on commit → pass / fail re-emits id + rationale`. Closes the section by showing the rationale-driven self-correction loop the prose has been describing.
5. **Anatomy section trimmed.** Cut the "stale doc as ground truth" aside and the "all four files move together; the kit enforces it" bit — the latter is now redundant with the IMPORTANT block under Verbs.
6. **Atomic-triple language replaced everywhere else.** IMPORTANT block under Verbs and Transparency / Directive provenance now use `keep the check, the rationale, and the history in lockstep` and `CLI verbs require the check, the rationale, and the log entry to land together` respectively.
7. **Minor copy tightening** through Quickstart, Install, Community packs (token + steering accounting wording), Transparency (light edits), and Why-not-pre-commit.

Out of scope:

- The mermaid diagrams render natively on GitHub but not in plain markdown viewers (npm registry, some IDE previews). Acceptable trade-off for the primary surface; revisit if README appears prominently on a non-rendering surface.
- "governance-driven development" as a category name stays — the concept is the user-owned framing for the kit, even if the term is slightly consultanty in dev contexts.

## Validation

- `bash .governance/run.sh` passes (no directive regressions).
- Mermaid diagrams render correctly on GitHub (verified by reading the rendered PR preview).
- Cold-read: a developer reaching the README sees the macro pitch (humans steer, agents do) and a picture of the loop within the first screen of the Why section, with no internal jargon to parse.

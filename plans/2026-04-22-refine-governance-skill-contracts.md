# 2026-04-22 - Refine governance skill contracts

Retrospective plan for the follow-up work that tightened the three governance skills after the initial PR was already in flight. This was originally missed during execution and is being captured now so the repo history still records why the change took this shape.

## Goal

Strengthen the governance skill layer so it is less model-dependent and less likely to misfire, while keeping the three skills clearly separated by responsibility.

The work includes:

- tighter trigger boundaries for `governance-bootstrap`, `governance-amend`, and `governance-gardener`
- more mechanical execution contracts and required final-output shapes
- a preset-based bootstrap flow
- a shared governance vocabulary and a canonical watched-scope model
- expanded eval expectations for routing failures, output contracts, and gardener mode handling
- explicit intent-mapping guidance so custom and amended rules are derived from the bad merge they must block, not from the easiest proxy to script
- eval coverage for `plan-captured`-style companion-artifact rules so shallow repo-state implementations fail the contract

## Steps

1. Review the three `SKILL.md` files and supporting references for ambiguity, overlap, and heuristic behavior that was not clearly labeled.
2. Patch the skill contracts to add negative-trigger examples, decision tables, stronger output requirements, and explicit assumption reporting.
3. Add shared reference material for cross-skill terminology and gardener watched-scope resolution.
4. Update eval expectations so the repo encodes the intended routing behavior instead of relying on prose alone.
5. Tighten bootstrap and amend authoring flow so rule intent, policy surface, and enforcement surface must be named explicitly before implementation.
6. Add a regression-focused eval that rejects repo-exists proxies for per-change obligations such as `plan-captured`.
7. Run lightweight verification: JSON sanity for eval files and `bash tests/governance/run.sh`.

## Notes

- This is a retrospective capture. The change work started before this plan file was written.
- The follow-up amendment to `plan-captured` should make this kind of miss mechanically catchable in the future instead of depending on memory.
- This plan also covers the next tightening pass: making bootstrap/amend encode the spirit of a rule directly into the workflow so future amendments do not stop at a cursory interpretation.

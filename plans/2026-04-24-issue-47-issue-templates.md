<!-- last-verified: 2026-04-24 -->
# Plan — issue-47: Add GitHub issue templates

Closes [#47](https://github.com/Duaility/governance-kit/issues/47).

## Goal

Commits in this repo follow Conventional Commits, but there is no
analogous convention for filing GitHub issues. The workflow that
drives most issues here is *brainstorm with an agent → agent fleshes
out details → agent opens the issue*, and the quality of that handoff
directly determines whether the implementing agent (often a different
session) can ground itself without re-deriving context.

Add issue templates that force a consistent shape for that handoff,
with title prefixes that mirror Conventional Commit types so an issue
→ PR → commit line up visually.

## Scope

- `.github/ISSUE_TEMPLATE/proposal.yml` — the primary template for
  the brainstorm-to-implementation flow. Sections: Context, Proposal,
  Acceptance criteria, Out of scope, Open questions. Title prefixed
  `proposal:`.
- `.github/ISSUE_TEMPLATE/bug.yml` — standard defect form. Sections:
  What happened, Expected, Repro, Environment, Notes. Title prefixed
  `bug:`.
- `.github/ISSUE_TEMPLATE/config.yml` — keep blank issues enabled,
  point open-ended questions to Discussions.

## Non-goals

- A `chore` template — can be added later if the need surfaces.
- Any change to the PR template, commit conventions, or governance
  rules.
- Wiring issue-title format into a governance rule.

## Validation

- `bash tests/governance/run.sh` passes.
- After merge, the GitHub new-issue picker shows both `proposal` and
  `bug` templates.

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
- `.github/ISSUE_TEMPLATE/config.yml` — disable blank issues and point
  open-ended questions to Discussions.
- `issue-templates` governance rule — require the tracked GitHub issue
  forms and config so the handoff standard stays enforced after this PR.
- `duaility/agent-governance` pack assets — ship the templates under
  the rule's `install-assets/` tree so newly bootstrapped repos start
  green.
- Rule scope: check only the load-bearing invariant (required field
  IDs exist and `required: true` flag count). Leave cosmetic surface
  (form `name`, `title` placeholder, `labels`, human-readable section
  labels) free for downstream consumers to customize — the `id` is
  the structured identifier that keeps the handoff meaningful.
- Bump `duaility/agent-governance` from `0.1` → `0.2` — adding
  `issue-templates` to the `standard` preset is a breaking change
  for existing pack consumers.

## Non-goals

- A `chore` template — can be added later if the need surfaces.
- Any change to the PR template or commit conventions.

## Validation

- `bash .governance/run.sh` passes.
- `bash .governance/run.sh issue-templates` passes.
- `bash scripts/test-packs.sh` passes.
- After merge, the GitHub new-issue picker shows both `proposal` and
  `bug` templates.

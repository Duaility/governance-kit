# Dogfood `agent-token-accounting`

## Goal

Install the newly-shipped `agent-token-accounting` rule in `governance-kit` itself, so this repo eats its own dog food: future agent-authored commits in this repo will carry token trailers and append to `COSTS.md`.

## Context

The feature PR ([#14](https://github.com/Duaility/governance-kit/pull/14)) shipped the rule as a bootstrap asset (opt-in for downstream repos). The ask is to also adopt it in this repo. The cardinal rule says amendments to `CONSTITUTION.md` must land in the same commit as the enforcing test — so this is an atomic change.

## Steps

1. Copy `governance-bootstrap/assets/tests-bash/rules/agent-token-accounting.sh` to `tests/governance/rules/agent-token-accounting.sh` (executable).
2. Copy `governance-bootstrap/assets/githooks/prepare-commit-msg` to `.githooks/prepare-commit-msg` (executable). The hook is a silent no-op until a runtime wrapper exports `AGENT_*` — it cannot break human commits.
3. Copy `governance-bootstrap/assets/COSTS.template.md` to `COSTS.md` at the repo root — the durable ledger starts empty.
4. Amend `CONSTITUTION.md`: add an `agent-token-accounting` Invariants subsection (Rule / Rationale / Enforced by / Exceptions) and append an Evolution Log entry dated today.
5. Run `bash tests/governance/run.sh` to confirm: the new rule passes on a repo with no historical agent-authored commits, and no pre-existing rule regresses.

## What this does *not* do

- Does **not** update `hooks-configured` to also require `prepare-commit-msg`. That rule is a separate piece of surface — expanding it would block every repo that doesn't want token accounting. `prepare-commit-msg` stays optional.
- Does **not** wire Claude Code or Codex to populate `AGENT_*` env vars yet. That's runtime-integration work for a follow-up. Until then, this repo's agent commits will not carry trailers, and that's fine — the rule only fires when an `Agent:` trailer is actually present.

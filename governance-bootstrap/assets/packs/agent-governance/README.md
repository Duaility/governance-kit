# agent-governance pack

Rules for repos operating under **agent-driven development** — where every
change to the tree is produced through an agent runtime (Codex, Claude
Code, Cursor, ...). Promoted from this repo's own `tests/governance/`
suite so any repo can opt into the same discipline.

## Rules

| Rule | Category | Surface | Hook |
|---|---|---|---|
| `plan-per-issue` | AgentDiscipline | repo-state | pre-commit |
| `commit-issue-plan-match` | AgentDiscipline | change-set | commit-msg |
| `issues-tracked` | AgentDiscipline | repo-state | pre-commit |
| `agent-token-accounting` | AgentDiscipline | change-set | commit-msg |

The four rules form a chain — issues are tracked, every issue has exactly
one plan, every commit matches its plan, every commit carries its cost.
Breaking any link makes the chain non-auditable, so the `standard` preset
bundles all four.

## Installation note — agent-token-accounting

Installing `agent-token-accounting` into a target repo requires the full
accounting stack:

- `scripts/governance/lib/{ledger,trailers,rates}.py`
- `scripts/governance/agent-accounting.sh`
- `scripts/governance/runtimes/*.sh`
- a `prepare-commit-msg` hook that reads the handoff file the pre-commit
  stage writes

See [`governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md`](../../references/AGENT_TOKEN_ACCOUNTING.md)
for the wiring. Landing just the rule script and the constitution snippet
— without the stack that produces the trailers and ledger rows — will
block every commit and is not a useful state.

Shipping this stack end-to-end as part of the pack installer is a scoped
follow-up. Today, bootstrap only copies the rule script + snippet; the
user is directed to `AGENT_TOKEN_ACCOUNTING.md` for the infrastructure.

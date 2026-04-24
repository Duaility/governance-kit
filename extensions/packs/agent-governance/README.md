# agent-governance pack

Scoped id: **`duaility/agent-governance`**.

Directives for repos operating under **agent-driven development** — where every
change to the tree is produced through an agent runtime (Codex, Claude
Code, Cursor, ...). Promoted from this repo's own `tests/governance/`
suite so any repo can opt into the same discipline.

> **Monorepo note.** This pack lives under `extensions/packs/` as a
> community-shaped pack that ships alongside the kit (see issue #31). It
> is authored, validated, and installed through the same flow as a
> pack hosted in its own repo — the only difference is that the catalog
> entry at [`extensions/catalog.community.json`](../../catalog.community.json)
> points at `Duaility/governance-kit` with `source.path:
> extensions/packs/agent-governance` instead of a standalone repo.

## Directives

| Directive | Category | Surface | Hook |
|---|---|---|---|
| `plan-per-issue` | AgentDiscipline | repo-state | pre-commit |
| `commit-issue-plan-match` | AgentDiscipline | change-set | commit-msg |
| `issue-templates` | AgentDiscipline | repo-state | pre-commit |
| `issues-tracked` | AgentDiscipline | repo-state | pre-commit |
| `agent-token-accounting` | AgentDiscipline | change-set | commit-msg |

The directives form a chain — issue creation uses a durable template, issues
are tracked, every issue has exactly one plan, every commit matches its
plan, every commit carries its cost. Breaking any link makes the chain
non-auditable, so the `standard` preset bundles the full chain.

## Installation note — agent-token-accounting

The directive is self-contained. Everything it needs ships inside the directive
folder:

- `directives/agent-token-accounting/check.sh` — validator (commit-msg + CI)
- `directives/agent-token-accounting/lib/{ledger,trailers,rates}.py` — ledger + trailer logic
- `directives/agent-token-accounting/hooks/pre-commit.sh` — writes the ledger row, stages it, hands off via an env file
- `directives/agent-token-accounting/hooks/prepare-commit-msg.sh` — stamps trailers from the handoff
- `directives/agent-token-accounting/runtimes/{claude-code,codex}.sh` — per-runtime transcript readers

Bootstrap copies the whole folder into `tests/governance/directives/agent-token-accounting/`
and the hook generator wires the two `hooks/*.sh` helpers into the
dispatchers automatically — no separate infrastructure step. A companion
`COSTS.md` must exist (templated from `governance/assets/COSTS.template.md`);
the `check.sh` treats it as the ledger of record.

See [`governance/references/AGENT_TOKEN_ACCOUNTING.md`](../../../governance/references/AGENT_TOKEN_ACCOUNTING.md)
for the detailed wiring and runtime-specific behavior.

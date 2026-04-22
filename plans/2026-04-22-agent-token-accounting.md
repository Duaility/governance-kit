# Agent Token Accounting Rule

## Goal

Ship an opt-in governance rule `agent-token-accounting` that gives repositories a durable, auditable ledger of token consumption for agent-authored commits — generic across runtimes (Codex, Claude Code, or anything else). Tracks [governance-kit#13](https://github.com/Duaility/governance-kit/issues/13).

## Background — design decisions

The issue called out a set of failure modes (PR-level too late, SHA-keyed breaks on squash, transcripts ephemeral, self-referential SHA problem) and proposed a layered model: commit trailers at branch time, `COSTS.md` as the durable post-squash ledger, governance rule enforces consistency.

Open questions from the issue, resolved:

1. **Default vs opt-in in bootstrap?** Opt-in. Most repos don't need token accounting; shipping in the default menu would add noise. Lives in `references/RULES_CATALOG.md` under "Also available".
2. **Require a squash-merge trailer on the base-branch commit?** No. `COSTS.md` is the durable source of truth; a squash trailer requires PR-platform tooling we don't control.
3. **Issue format?** Reuse the existing `(#123)` convention from `conventional-commits`. One canonical form across the kit.
4. **Scope — Codex only, or multi-runtime?** Multi-runtime. The `Agent:` trailer is a free-form string (`codex`, `claude-code`, `cursor`, etc.). The `prepare-commit-msg` hook reads generic env vars (`AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_TOKEN_INPUT`, `AGENT_TOKEN_OUTPUT`) that any runtime wrapper can export; a reference doc shows wiring patterns for Codex and Claude Code.
5. **`Cost-Key` shape?** `<agent>-<session-short>-<unix-epoch>` — stable, human-readable, collision-safe in practice.

## Steps

1. Add the rule script at `governance-bootstrap/assets/tests-bash/rules/agent-token-accounting.sh`. Two checks:
   - If `COSTS.md` exists: every ledger row is well-formed, `Token-Total = Input + Output`, `Cost-Key` is unique within the file.
   - For each commit in `base..HEAD` whose message contains an `Agent:` trailer: require the full trailer set, enforce the math, and require exactly one matching `Cost-Key` row in `COSTS.md`.
2. Add a tracked-hook asset `governance-bootstrap/assets/githooks/prepare-commit-msg` that stamps the trailers and appends a ledger row when `AGENT_NAME` is set in the environment. Fails closed with a clear message if required token env vars are missing.
3. Add a starter ledger template at `governance-bootstrap/assets/COSTS.template.md` — pre-formatted with the append-only header, table, and a `governance: allow-plan-captured`-style waiver banner so bootstrap can drop it in without triggering other rules.
4. Add wiring documentation at `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md` — explains the trailer schema, the env-var contract, and gives concrete wrapper examples for Codex (`CODEX_THREAD_ID` → `AGENT_*`) and Claude Code (`CLAUDE_SESSION_ID` → `AGENT_*`).
5. Update `governance-bootstrap/references/RULES_CATALOG.md` to list `agent-token-accounting` under "Also available" with a pointer to the reference doc.
6. Leave the live repo's own `tests/governance/rules/` and `CONSTITUTION.md` untouched — the rule is opt-in and the live repo has no historical agent-authored commits to validate. Future adoption goes through `governance-amend`.

## Tradeoff accepted

The `prepare-commit-msg` hook depends on the runtime wrapper correctly populating env vars. If the wrapper breaks, commits land without trailers and the rule fires on the next agent commit in CI — loud, not silent. A wrapper that fabricates numbers would pass the math check; that's a trust boundary the mechanical rule intentionally doesn't try to defend.

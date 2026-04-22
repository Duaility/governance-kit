# Claude Code commit wrapper

## Goal

Give `agent-token-accounting` a real data source for Claude Code sessions, since Claude Code does not currently export session id or token counts as environment variables. Introduces `scripts/claude-code-commit.sh`, a thin wrapper that reads the session transcript at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, computes per-commit token delta, populates the `AGENT_*` contract, and execs `git commit`.

## Context

The `prepare-commit-msg` hook shipped in [#14](https://github.com/Duaility/governance-kit/pull/14) is a silent no-op when `AGENT_NAME` is unset. For the Claude Code case this meant the rule was defined but never actually fired. Claude Code's Bash tool exposes `CLAUDECODE=1` and a few harness env vars, but no session id and no running token tally. The transcripts on disk carry both — so the wrapper extracts from there.

## Design

- **Transcript discovery**: encode the current git-toplevel (or `$PWD`) by replacing `/` and `.` with `-`, look under `~/.claude/projects/<encoded>/`, pick the most recently modified `*.jsonl`. Override with `CLAUDE_TRANSCRIPT_PATH` env var.
- **Token math**: `input = sum(input_tokens + cache_creation_input_tokens + cache_read_input_tokens)` across all `assistant` entries that match `sessionId`; `output = sum(output_tokens)`. This counts all billed input tokens regardless of cache state.
- **Per-commit delta, not cumulative**: subtract the sum of existing `COSTS.md` rows whose `session` column matches the current session id. First commit in a session gets the full tally; subsequent commits get only the new tokens. This preserves the invariant that summing the ledger column for a session equals that session's total spend.
- **Claude Code is the name**: exports `AGENT_NAME=claude-code` by default. User can override.
- **Commit-msg belt-and-suspenders**: wire the existing `commit-msg` hook to also invoke the rule when installed, so typos in agent-authored trailers are caught before the commit lands (instead of on the next commit's pre-commit or in CI).

## Steps

1. Create `scripts/claude-code-commit.sh` — executable wrapper.
2. Update `.githooks/commit-msg` (live) and `governance-bootstrap/assets/githooks/commit-msg` (asset) to also run `agent-token-accounting.sh` in commit-msg mode when installed.
3. Expand `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md` to point the Claude Code section at the concrete wrapper instead of the placeholder example.
4. Run the suite to confirm no regressions.

## Non-goals

- No modification to Claude Code itself. If Claude Code later exports `CLAUDE_SESSION_ID` natively, the wrapper becomes strictly simpler but the `AGENT_*` contract stays the same.
- No automatic invocation. The user (or an agent operating the Bash tool) has to call `scripts/claude-code-commit.sh` instead of `git commit`. Making this automatic requires either an alias in the user's shell rc or a Claude Code settings hook — out of scope here.

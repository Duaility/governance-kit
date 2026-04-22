# Agent Token Accounting

Opt-in governance rule that gives the repo a durable, auditable ledger of
token consumption for **agent-authored commits** — across any runtime (Codex,
Claude Code, Cursor, or something homegrown).

## Why it's layered this way

Naive anchors all break:

- **PR-level accounting is too late** — the first commit exists before the PR.
- **Commit-SHA keyed accounting breaks under squash merge** — branch SHAs disappear on merge.
- **Session transcripts are ephemeral** — they live on one contributor's laptop.
- **A ledger row keyed by the commit's own SHA is self-referential** — adding the row changes the SHA.

The layered model that works:

1. **Commit trailers** provide branch-time provenance that reviewers can read.
2. **`COSTS.md`** is the durable, append-only ledger that survives squash merges.
3. **`Cost-Key`** is a stable join key that appears in both — neither depends on the commit SHA.
4. **The governance rule** cross-checks the two and fails loudly on drift.

## Trailer schema

Every agent-authored commit carries these seven trailers:

```
Agent: codex
Issue: #123
Session: 01HXYZ...thread-id
Token-Input: 1200
Token-Output: 450
Token-Total: 1650
Cost-Key: codex-01HXYZabcdef-1713800000
```

- `Agent` is a free-form identifier — whatever name you want to report in the ledger.
- `Issue` must match `#123` (the same anchor `conventional-commits` enforces in the subject).
- `Session` is whatever stable id your runtime uses to group usage events.
- `Token-Total` **must equal** `Token-Input + Token-Output`.
- `Cost-Key` must be unique within `COSTS.md`. Convention: `<agent>-<session-short>-<epoch>`.

## Installing

Inside the bootstrapped repo:

```sh
cp <governance-kit>/governance-bootstrap/assets/tests-bash/rules/agent-token-accounting.sh tests/governance/rules/
cp <governance-kit>/governance-bootstrap/assets/githooks/prepare-commit-msg .githooks/
cp <governance-kit>/governance-bootstrap/assets/COSTS.template.md COSTS.md
chmod +x tests/governance/rules/agent-token-accounting.sh .githooks/prepare-commit-msg
```

Then add an `agent-token-accounting` Invariants subsection to `CONSTITUTION.md`
via the `governance-amend` skill (the rule and the constitutional entry must
land in one commit — that's the cardinal rule).

## Wiring runtimes

The `prepare-commit-msg` hook is **runtime-agnostic**. It reads four generic
environment variables and writes the trailers + ledger row. Each runtime's
wrapper is responsible for populating those variables before invoking
`git commit`.

| Env var | Required | Meaning |
|---|---|---|
| `AGENT_NAME` | yes | Free-form runtime id written into the `Agent:` trailer. Leave unset for human commits — the hook is a silent no-op. |
| `AGENT_SESSION_ID` | yes | The runtime's session / thread id. |
| `AGENT_TOKEN_INPUT` | yes | Input tokens consumed for the work that produced this commit. |
| `AGENT_TOKEN_OUTPUT` | yes | Output tokens. |
| `AGENT_ISSUE` | optional | `#123`. Parsed from the commit subject if omitted. |
| `AGENT_COST_KEY` | optional | Override the auto-generated `<agent>-<session-short>-<epoch>`. |

### Codex wrapper example

```sh
#!/usr/bin/env bash
# Wrap `git commit` for Codex sessions. Reads usage from the local session
# transcript and exports the AGENT_* contract.
set -euo pipefail

SESSION_FILE="$HOME/.codex/sessions/${CODEX_THREAD_ID}.jsonl"
if [[ -f "$SESSION_FILE" ]]; then
    # Sum token usage across events in this thread. Replace with whatever
    # query matches your Codex version's JSONL schema.
    AGENT_TOKEN_INPUT=$(jq -s '[.[] | .usage.input_tokens // 0] | add' "$SESSION_FILE")
    AGENT_TOKEN_OUTPUT=$(jq -s '[.[] | .usage.output_tokens // 0] | add' "$SESSION_FILE")
else
    AGENT_TOKEN_INPUT=0
    AGENT_TOKEN_OUTPUT=0
fi

export AGENT_NAME=codex
export AGENT_SESSION_ID="$CODEX_THREAD_ID"
export AGENT_TOKEN_INPUT AGENT_TOKEN_OUTPUT

exec git commit "$@"
```

### Claude Code wrapper

Claude Code does **not** currently export a session id or token tallies as
environment variables — the Bash tool sees `CLAUDECODE=1` and a few harness
vars but nothing usage-related. The session transcript on disk carries both,
so `governance-kit` ships a ready-to-use wrapper that reads from it:

```sh
scripts/claude-code-commit.sh -m "feat: add foo (#13)"
```

The wrapper (see `scripts/claude-code-commit.sh` in this repo):

1. Finds the session JSONL under `~/.claude/projects/<encoded-cwd>/` where the
   encoding replaces every `/` and `.` in the absolute path with `-`. Override
   with `CLAUDE_TRANSCRIPT_PATH` if needed.
2. Sums every `assistant` entry's `.message.usage` fields, matched by
   `sessionId`:
   - `input = input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
   - `output = output_tokens`
3. Subtracts the sum of existing `COSTS.md` rows whose `session` column equals
   this session id, so each commit's ledger row is a **delta** and
   `sum(rows for session) = session total spend`.
4. Exports `AGENT_NAME=claude-code`, `AGENT_SESSION_ID`, `AGENT_TOKEN_INPUT`,
   `AGENT_TOKEN_OUTPUT`, and `exec`s `git commit`. The `prepare-commit-msg`
   hook then stamps the trailers and appends the ledger row.

If Claude Code later exports `CLAUDE_SESSION_ID` and/or a running usage
accumulator natively, the wrapper simplifies but the `AGENT_*` contract
downstream stays identical.

### Other runtimes

Any runtime (Cursor, Aider, a homegrown agent) follows the same pattern —
populate the four `AGENT_*` vars and invoke `git commit`. If the runtime
writes a transcript, adapt the Claude Code wrapper to its schema.

## What gets enforced where

| Layer | What it checks |
|---|---|
| `prepare-commit-msg` hook | When `AGENT_NAME` is set, stamps all seven trailers and appends a row to `COSTS.md`. Fails closed if required env vars are missing or non-integer. |
| `agent-token-accounting` rule (`run.sh` / CI) | Walks `base..HEAD`. For each commit with an `Agent:` trailer: requires the full trailer set, checks `Total = Input + Output`, requires exactly one matching `Cost-Key` row in `COSTS.md`, and verifies the row's numbers agree with the trailers. Independently validates `COSTS.md` row shape and `Cost-Key` uniqueness so the ledger stays clean even after branch commits are squashed away. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass the math check. That's a trust boundary — the rule makes tampering *visible* (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit. The durable anchor is `COSTS.md`, not the merge commit's metadata; keeping the rule to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling.
- **No cost computation.** This rule tracks tokens, not dollars. Price lookups are out of scope — add a downstream report that joins `COSTS.md` to your billing sheet if you need that.

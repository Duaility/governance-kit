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
mkdir -p scripts
cp <governance-kit>/governance-bootstrap/assets/scripts/governance-commit.sh scripts/
cp <governance-kit>/governance-bootstrap/assets/scripts/claude-code-commit.sh scripts/   # if you use Claude Code
cp <governance-kit>/governance-bootstrap/assets/scripts/codex-commit.sh        scripts/   # if you use Codex
chmod +x tests/governance/rules/agent-token-accounting.sh .githooks/prepare-commit-msg scripts/*.sh
```

Then add an `agent-token-accounting` Invariants subsection to `CONSTITUTION.md`
via the `governance-amend` skill (the rule and the constitutional entry must
land in one commit — that's the cardinal rule).

### Worktrees

If you commit from a git worktree, `core.hooksPath` is shared with the main
repository by default, which means `prepare-commit-msg` fires from the main
checkout's `.githooks/` and can silently miss updates on branches. Pin the
worktree to its own hook directory:

```sh
git config --worktree core.hooksPath .githooks
```

The `hooks-configured` rule accepts both forms; the worktree-local override
just ensures the hooks you are editing in the worktree are the ones that
actually run.

## Wiring runtimes

The commit pipeline splits into three layers:

1. **Per-runtime wrapper** (e.g. `scripts/claude-code-commit.sh`,
   `scripts/codex-commit.sh`) — the only layer that knows about a specific
   runtime. It locates the session transcript, sums cumulative tokens, and
   exports four env vars: `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`,
   `AGENT_CUM_OUTPUT`. Then it `exec`s the shared helper.
2. **Shared helper** (`scripts/governance-commit.sh`) — runtime-agnostic. It
   subtracts prev ledger rows (per-commit delta), parses the issue anchor
   from `-m`, computes the `Cost-Key`, appends the `COSTS.md` row, `git add`s
   it, exports the `AGENT_*` trailer contract, and `exec`s `git commit`.
3. **`prepare-commit-msg` hook** — runtime-agnostic. Reads the exported
   `AGENT_*` env vars and stamps the trailers onto the commit message. Does
   not touch `COSTS.md`.

The ledger append has to happen **before** `git commit` starts. Files
modified or staged during `prepare-commit-msg` land in the *next* commit's
index, not the tree git has already snapshotted for this commit — a CI
failure of the form "Cost-Key X should have exactly 1 row in COSTS.md, found
0" is the tell. The shared helper gets this right once, for every runtime.

### Env-var contract

| Layer | Vars in | Vars out |
|---|---|---|
| Runtime wrapper → helper | (reads transcripts / runtime state) | `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`, `AGENT_CUM_OUTPUT` |
| Helper → hook | `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`, `AGENT_CUM_OUTPUT`, optionally `AGENT_ISSUE` / `AGENT_COST_KEY` | `AGENT_NAME`, `AGENT_SESSION_ID`, `AGENT_TOKEN_INPUT` (delta), `AGENT_TOKEN_OUTPUT` (delta), `AGENT_COST_KEY`, `AGENT_ISSUE` |
| Hook | All "helper → hook" outputs | Stamps trailers onto the commit message |

### Claude Code

Usage:

```sh
scripts/claude-code-commit.sh -m "feat: add foo (#13)"
```

Claude Code does **not** currently export a session id or token tallies as
environment variables — the Bash tool sees `CLAUDECODE=1` and a few harness
vars but nothing usage-related. The wrapper reads them from the on-disk
session transcript:

1. Finds the session JSONL under `~/.claude/projects/<encoded-cwd>/` where the
   encoding replaces every `/` and `.` in the absolute path with `-`. Override
   with `CLAUDE_TRANSCRIPT_PATH` if needed.
2. Sums every `assistant` entry's `.message.usage` fields (input counts
   regular + cache-creation + cache-read so the number matches billed usage
   regardless of cache state).
3. Hands off cumulative totals to `governance-commit.sh`.

### Codex

Usage:

```sh
scripts/codex-commit.sh -m "feat: add foo (#13)"
```

The wrapper reads Codex's on-disk session transcript under
`~/.codex/sessions/`:

1. Locates the transcript via `CODEX_THREAD_ID` if set, otherwise falls back
   to the most recently modified `*.jsonl` in the sessions dir. Override with
   `CODEX_TRANSCRIPT_PATH`.
2. Derives the session id from `CODEX_THREAD_ID` or from the transcript
   filename.
3. Sums tokens across the common shapes — top-level `usage`,
   `message.usage`, `response.usage` — handling both `input_tokens` /
   `output_tokens` and `prompt_tokens` / `completion_tokens` keys, since
   Codex's transcript schema varies by version.
4. Hands off cumulative totals to `governance-commit.sh`.

### Other runtimes

Any runtime (Cursor, Aider, a homegrown agent) needs only a ~40-line
wrapper that locates its transcript, sums tokens, and exports the four
`AGENT_NAME` / `AGENT_SESSION_ID` / `AGENT_CUM_INPUT` / `AGENT_CUM_OUTPUT`
env vars. Use `scripts/codex-commit.sh` as a template — everything after the
token sum is delegated to `governance-commit.sh`, which is already correct.

## What gets enforced where

| Layer | What it checks |
|---|---|
| Runtime wrapper | Transcript discovery + token sum for one specific runtime. |
| `governance-commit.sh` (shared) | Per-commit delta, issue parsing, cost-key generation, ledger append + stage — **all before** `exec git commit`. |
| `prepare-commit-msg` hook | When `AGENT_NAME` is set, stamps all seven trailers from env vars. Fails closed if required env vars are missing or non-integer. Does not touch `COSTS.md`. |
| `agent-token-accounting` rule (`run.sh` / CI) | Walks `base..HEAD`. For each commit with an `Agent:` trailer: requires the full trailer set, checks `Total = Input + Output`, requires exactly one matching `Cost-Key` row in `COSTS.md`, and verifies the row's numbers agree with the trailers. Independently validates `COSTS.md` row shape and `Cost-Key` uniqueness so the ledger stays clean even after branch commits are squashed away. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass the math check. That's a trust boundary — the rule makes tampering *visible* (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit. The durable anchor is `COSTS.md`, not the merge commit's metadata; keeping the rule to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling.
- **No cost computation.** This rule tracks tokens, not dollars. Price lookups are out of scope — add a downstream report that joins `COSTS.md` to your billing sheet if you need that.

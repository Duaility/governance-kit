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
cp    <governance-kit>/governance-bootstrap/assets/tests-bash/rules/agent-token-accounting.sh tests/governance/rules/
cp    <governance-kit>/governance-bootstrap/assets/githooks/pre-commit         .githooks/
cp    <governance-kit>/governance-bootstrap/assets/githooks/prepare-commit-msg .githooks/
cp    <governance-kit>/governance-bootstrap/assets/COSTS.template.md           COSTS.md
cp -r <governance-kit>/governance-bootstrap/assets/scripts/governance          scripts/
chmod +x tests/governance/rules/agent-token-accounting.sh \
         .githooks/pre-commit .githooks/prepare-commit-msg \
         scripts/governance/agent-accounting.sh \
         scripts/governance/runtimes/*.sh
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

## How a commit flows

`git commit` is the only entry point. There is no wrapper script to remember
or teach — if the commit is agent-authored, the pre-commit hook detects the
runtime, reads the transcript, appends the ledger row, and hands off to
`prepare-commit-msg` to stamp the matching trailers. Human commits flow
through untouched.

```
git commit -m "feat: x (#13)"
      │
      ▼
pre-commit ──► scripts/governance/agent-accounting.sh
      │          1. Detect runtime from env (CLAUDECODE / CODEX_THREAD_ID / AGENT_NAME)
      │          2. Read parent argv (/proc/$PPID/cmdline or `ps`) to recover
      │             the -m subject and parse the (#N) issue anchor
      │          3. Dispatch to scripts/governance/runtimes/<runtime>.sh —
      │             returns `<session_id> <cum_input> <cum_output>`
      │          4. Subtract prior rows for this session → per-commit delta
      │          5. Compute Cost-Key, append COSTS.md row, `git add` it
      │          6. Write .git/governance-pending.env
      │
      ▼
(governance tests run — agent-token-accounting sees the new row in-tree)
      │
      ▼
prepare-commit-msg ──► sources .git/governance-pending.env, stamps the
                       seven trailers onto the commit message, deletes
                       the handoff file
      │
      ▼
git snapshots the tree (COSTS.md row is already staged) → commit
```

The ordering is load-bearing. `git add` during **pre-commit** lands in the
tree git is about to snapshot; `git add` during **prepare-commit-msg** lands
in the *next* commit's index. A CI failure of the form `Cost-Key X should
have exactly 1 row in COSTS.md, found 0` means something tried to stage
`COSTS.md` too late in the pipeline.

### Runtime detection

`agent-accounting.sh` picks the runtime from environment, in order:

| Signal | Runtime |
|---|---|
| `AGENT_NAME` set (any value) | `manual` — caller supplies `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`, `AGENT_CUM_OUTPUT` |
| `CLAUDECODE=1` | `claude-code` — reads `~/.claude/projects/<encoded-cwd>/*.jsonl` |
| `CODEX_THREAD_ID` set | `codex` — reads `~/.codex/sessions/*.jsonl` |
| none of the above | no-op (human commit) |

The issue anchor is parsed from the parent git's `-m` / `--message` argv, or
can be supplied explicitly via `AGENT_ISSUE='#13'` (useful for editor-mode
commits where argv has no `-m`).

### Claude Code

No setup beyond installing the hooks. `CLAUDECODE=1` is already exported to
every Bash tool invocation, so `git commit -m "feat: x (#13)"` from an
agent session Just Works.

The reader at `scripts/governance/runtimes/claude-code.sh`:

1. Finds the session JSONL under `~/.claude/projects/<encoded-cwd>/`, where
   the encoding replaces every `/` and `.` in the absolute path with `-`.
   Override with `CLAUDE_TRANSCRIPT_PATH` if needed.
2. Reads `sessionId` from the first entry that has one.
3. Sums every `assistant` entry's `.message.usage` fields — `input_tokens`,
   `cache_creation_input_tokens`, and `cache_read_input_tokens` all count as
   input so the number matches billed usage regardless of cache state.
4. Prints `<session_id> <cum_input> <cum_output>` for `agent-accounting.sh`.

### Codex

Same story — `CODEX_THREAD_ID` is already set in Codex sessions, so no
wrapper is needed. The reader at `scripts/governance/runtimes/codex.sh`:

1. Locates the transcript at `~/.codex/sessions/${CODEX_THREAD_ID}.jsonl`,
   falling back to the most recently modified `*.jsonl` in the sessions dir.
   Override with `CODEX_TRANSCRIPT_PATH`.
2. Derives the session id from `CODEX_THREAD_ID` or from the transcript
   filename.
3. Sums tokens across the common shapes — top-level `usage`, `message.usage`,
   `response.usage` — handling both `input_tokens` / `output_tokens` and
   `prompt_tokens` / `completion_tokens` key pairs, since Codex's transcript
   schema varies by version.

### Other runtimes

Drop a reader at `scripts/governance/runtimes/<name>.sh` whose only job is
to print `<session_id> <cum_input> <cum_output>` on stdout (non-zero exit if
it can't find a transcript), and add a branch to the runtime-detection
block in `agent-accounting.sh`. `runtimes/codex.sh` is a ~60-line template.

Until you do that, `AGENT_NAME=<name> AGENT_SESSION_ID=... AGENT_CUM_INPUT=...
AGENT_CUM_OUTPUT=... git commit` (the `manual` path) works as an escape
hatch.

## What gets enforced where

| Layer | What it checks |
|---|---|
| `scripts/governance/runtimes/<runtime>.sh` | Transcript discovery + token sum for one specific runtime. |
| `scripts/governance/agent-accounting.sh` (pre-commit) | Runtime detection, issue parsing from parent argv, per-commit delta, cost-key generation, ledger append + `git add` — **all before** git snapshots the tree. Writes `.git/governance-pending.env` for the message hook. |
| `prepare-commit-msg` hook | Sources the handoff env file and stamps all seven trailers. Idempotent on amends (skips if an `Agent:` trailer is already present). Silent no-op if no handoff file exists (human commit, or `--no-verify`). Does not touch `COSTS.md`. |
| `agent-token-accounting` rule (`run.sh` / CI) | Walks `base..HEAD`. For each commit with an `Agent:` trailer: requires the full trailer set, checks `Total = Input + Output`, requires exactly one matching `Cost-Key` row in `COSTS.md`, and verifies the row's numbers agree with the trailers. Independently validates `COSTS.md` row shape and `Cost-Key` uniqueness so the ledger stays clean even after branch commits are squashed away. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass the math check. That's a trust boundary — the rule makes tampering *visible* (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit. The durable anchor is `COSTS.md`, not the merge commit's metadata; keeping the rule to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling.
- **No cost computation.** This rule tracks tokens, not dollars. Price lookups are out of scope — add a downstream report that joins `COSTS.md` to your billing sheet if you need that.

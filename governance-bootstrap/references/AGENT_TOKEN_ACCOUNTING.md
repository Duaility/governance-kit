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
- `Token-Input` counts **new-work input tokens** — `input + cache_create`. It
  deliberately excludes `cache_read`, which is the same bytes re-read each
  turn rather than new effort.
- `Token-Total` **must equal** `Token-Input + Token-Output`.
- `Cost-Key` must be unique within `COSTS.md`. Convention: `<agent>-<session-short>-<epoch>`.

## Ledger schema

`COSTS.md` is the durable record and is lossless by design — cache traffic
is tracked in its own columns so billing and cache-hit-rate analyses are
recoverable later:

```
| cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |
```

- `input` — truly new input tokens
- `cache-create` — tokens written to the prompt cache (billed at ~1.25×)
- `cache-read` — tokens read from the prompt cache (billed at ~0.10×)
- `output` — model output tokens
- `total = input + cache-create + cache-read + output` (self-checking invariant)

Runtimes that don't report cache traffic (Codex today) emit `0` in the
cache columns — the row invariant still holds.

Legacy 8-column rows from before the cache split (no `cache-create` /
`cache-read` columns) are accepted by the parser with both cache fields
defaulted to `0`, so an in-place migration is a one-time textual insertion.

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

The `scripts/governance/` tree includes `lib/ledger.py` and `lib/trailers.py`
— both are stdlib-only Python 3, no `pip install` required. The only
runtime dependency is `python3` on `$PATH`.

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
      │          3. Dispatch to scripts/governance/runtimes/<runtime>.sh — returns
      │             `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output>`
      │          4. Subtract prior rows for this session (via lib/ledger.py
      │             `sum-by-session`) → per-commit delta for all four token fields
      │          5. Compute Cost-Key, append COSTS.md row (lib/ledger.py
      │             `append-row`), `git add` it
      │          6. Write handoff env file at
      │             `$(git rev-parse --git-path governance-pending.env)`
      │
      ▼
(governance tests run — agent-token-accounting sees the new row in-tree)
      │
      ▼
prepare-commit-msg ──► sources the handoff env file (same
                       `git rev-parse --git-path` call), stamps the
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

The handoff file path is resolved via `git rev-parse --git-path
governance-pending.env` on both ends — that's deliberate. In a worktree
`.git` is a pointer file, not a directory; hardcoding `$ROOT/.git/…`
breaks silently. The same call works in both the main checkout and any
worktree.

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
3. Sums every `assistant` entry's `.message.usage` fields into four
   separate cumulative counters — `input_tokens`,
   `cache_creation_input_tokens`, `cache_read_input_tokens`, and
   `output_tokens`. Keeping them separate lets the ledger stay lossless:
   billing dollars and cache-hit-rate analyses can be reconstructed later.
4. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output>`
   for `agent-accounting.sh`.

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
   schema varies by version. Also picks up `cache_creation_input_tokens` /
   `cache_read_input_tokens` when present; zeroes the cache columns when
   the runtime doesn't expose them.
4. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output>`.

### Other runtimes

Drop a reader at `scripts/governance/runtimes/<name>.sh` whose only job is
to print `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output>`
on stdout (non-zero exit if it can't find a transcript), and add a branch
to the runtime-detection block in `agent-accounting.sh`. Emit `0` for the
two cache fields if the runtime doesn't expose them. `runtimes/codex.sh`
is a ~60-line template.

Until you do that, `AGENT_NAME=<name> AGENT_SESSION_ID=... AGENT_CUM_INPUT=...
AGENT_CUM_OUTPUT=... git commit` (the `manual` path) works as an escape
hatch. `AGENT_CUM_CACHE_CREATE` and `AGENT_CUM_CACHE_READ` are optional
and default to `0`.

## What gets enforced where

| Layer | What it checks |
|---|---|
| `scripts/governance/runtimes/<runtime>.sh` | Transcript discovery + 4-field token sum for one specific runtime. |
| `scripts/governance/lib/ledger.py` | Stdlib-only Python library that owns the ledger: `LedgerRow` dataclass, `parse`, `sum_by_session`, `append_row`, `validate`, `find_by_cost_key`. Handles both the 10-column schema and the legacy 8-column shape. Keeping the schema-sensitive parsing in named-field Python (not `awk -F'\|'`) eliminates the whole class of column-index bugs we ate once already. |
| `scripts/governance/lib/trailers.py` | Parses commit trailers and cross-checks them against a ledger row — `Token-Input == input + cache_create`, `Token-Output == output`, `Token-Total == Token-Input + Token-Output`. |
| `scripts/governance/agent-accounting.sh` (pre-commit) | Bash glue: runtime detection, issue parsing from parent argv, cost-key generation, handoff env-file write. Shells out to `lib/ledger.py` for `sum-by-session` (per-commit delta) and `append-row` (ledger write + `git add`) — **all before** git snapshots the tree. |
| `prepare-commit-msg` hook | Sources the handoff env file (resolved via `git rev-parse --git-path governance-pending.env` so worktrees work) and stamps all seven trailers. Idempotent on amends (skips if an `Agent:` trailer is already present). Silent no-op if no handoff file exists (human commit, or `--no-verify`). Does not touch `COSTS.md`. |
| `agent-token-accounting` rule (`run.sh` / CI) | Walks `base..HEAD`. Calls `lib/ledger.py validate` for repo-wide shape checks; for each commit with an `Agent:` trailer calls `lib/trailers.py validate` to require the full trailer set, check `Total = Input + Output`, require exactly one matching `Cost-Key` row in `COSTS.md`, and verify the row's numbers agree with the trailers. Runs independently of `COSTS.md` presence so the ledger stays clean even after branch commits are squashed away. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass the math check. That's a trust boundary — the rule makes tampering *visible* (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit. The durable anchor is `COSTS.md`, not the merge commit's metadata; keeping the rule to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling.
- **No cost computation.** This rule tracks tokens, not dollars. Price lookups are out of scope — add a downstream report that joins `COSTS.md` to your billing sheet if you need that.

# Agent Token Accounting

Opt-in governance directive that gives the repo a durable, auditable ledger of
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
4. **The governance directive** cross-checks the two and fails loudly on drift.

## Trailer schema

Every agent-authored commit carries these eight required trailers:

```
Agent: codex
Issue: #123
Session: 01HXYZ...thread-id
Token-Input: 1200
Token-Output: 450
Token-Total: 1650
Cost-Key: codex-01HXYZabcdef-1713800000
Cost-USD: 2.7932
```

- `Agent` is a free-form identifier — whatever name you want to report in the ledger.
- `Issue` must match `#123` (the same anchor `conventional-commits` enforces in the subject).
- `Session` is whatever stable id your runtime uses to group usage events.
- `Token-Input` counts **new-work input tokens** — `input + cache_create`. It
  deliberately excludes `cache_read`, which is the same bytes re-read each
  turn rather than new effort.
- `Token-Total` **must equal** `Token-Input + Token-Output`.
- `Cost-Key` must be unique within `COSTS.md`. Convention: `<agent>-<session-short>-<epoch>`.
- `Cost-USD` is required on every new commit. Stamped automatically from
  `lib/rates.py` using the runtime-reported model; the directive cross-checks
  it against the ledger row's `cost-usd` cell — same `rates.lookup` call,
  same token counts, so any divergence means someone hand-edited one side.
  Surfacing it as a trailer makes the per-commit dollar figure visible in
  `git log` without having to join against `COSTS.md`, and it survives
  squash merges alongside `Cost-Key`. A truly-unpriced model (no entry in
  `RATES` and no family-prefix match) blocks the commit at the pre-commit
  hook — the operator either adds a pricing row to `lib/rates.py` or uses
  `SKIP_GOVERNANCE=1` for a genuine hot-fix.

## Ledger schema

`COSTS.md` is the durable record and is lossless by design — cache traffic
is tracked in its own columns and the model-priced dollar cost lives next
to the token counts so billing and cache-hit-rate analyses are recoverable
without re-deriving rates after the fact:

```
| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
```

- `model` — runtime-reported model id (e.g. `claude-sonnet-4-5`); empty for
  runtimes that don't surface it and for legacy rows.
- `input` — truly new input tokens.
- `cache-create` — tokens written to the prompt cache (billed at ~1.25× base).
- `cache-read` — tokens read from the prompt cache (billed at ~0.10× base) —
  **tracked but excluded from `new-work`**.
- `output` — model output tokens.
- `new-work = input + cache-create + output` (self-checking directive).
- `cost-usd` — the true dollar cost for this row, computed from `model` via
  the directive's `lib/rates.py` and **all four** token columns
  (`cache-read` included — that's the only place cache rent appears).
  Required on every new v3 row; the column is the only single-number
  headline that's comparable across commits with different cache mixes.
  Legacy v1/v2 rows and v3 rows predating the cost-mandate (empty
  `model` cell) are grandfathered to empty `cost-usd`.

  `lib/rates.py` keeps **family-prefix fallbacks** (`claude-opus`,
  `claude-sonnet`, `claude-haiku`, `gpt-5`) seeded from the current
  rate card alongside version-specific keys. When a new minor release
  lands between directive updates (e.g. `gpt-5.5`), longest-prefix lookup
  picks the family row so `cost-usd` stays populated. When even the
  family key misses, the pre-commit hook prints a red `✗ model 'X'
  is not priced` error to stderr and blocks the commit — either add
  a pricing row to `lib/rates.py` or use `SKIP_GOVERNANCE=1` to get
  past a one-off.

Why both `new-work` and `cost-usd`:

- `new-work` is the reviewer-facing token number — stable, denominator-free,
  and matches `Token-Total` in the commit trailer exactly. It's what a
  reviewer skims to ask "how much effort did this commit take".
- `cost-usd` is what an accountant reads. Raw token sums across columns
  with a 50× price ratio (output vs cache-read) aren't meaningful on their
  own; the dollar column is.

`cache-read` is deliberately excluded from `new-work` — those are the same
bytes re-read each turn, not new work. Including it would make `new-work`
dominated by cache hit-rate rather than the size of the change. Keeping
`new-work == Token-Total` in the trailer means ledger headline and
reviewer-facing headline can't drift.

Runtimes that don't report cache traffic (Codex today) emit `0` in the
cache columns — the row directive still holds.

Legacy rows are accepted by the parser:

- **v2** (10 cols, pre-2026-04-23): `cost-key agent session issue input
  cache-create cache-read output total note`. The old `total` semantic
  (= `input + cache_create + output`) already matches v3's `new-work`, so
  migration is a textual column insertion: add empty `model` after `issue`,
  rename `total` → `new-work`, add empty `cost-usd` before `note`.
- **v1** (8 cols, pre-cache-split): `cost-key agent session issue input
  output total note`. Cache fields default to `0`; `model`/`cost-usd` empty.

Both legacy shapes are validated under the same `new-work` directive.

## Installing

The directive ships as a self-contained folder under the `agent-governance` pack.
The `governance-bootstrap` skill copies it wholesale and the hook generator
wires its `hooks/pre-commit.sh` and `hooks/prepare-commit-msg.sh` into the
dispatchers automatically. Manual install is:

```sh
cp -r <governance-kit>/extensions/packs/agent-governance/directives/agent-token-accounting \
      tests/governance/directives/
cp    <governance-kit>/governance/assets/COSTS.template.md COSTS.md
chmod +x tests/governance/directives/agent-token-accounting/check.sh \
         tests/governance/directives/agent-token-accounting/hooks/*.sh \
         tests/governance/directives/agent-token-accounting/runtimes/*.sh
```

Everything the directive needs — the `lib/` Python (ledger, trailers, rates),
the hook-side-effect scripts under `hooks/`, and the per-runtime transcript
readers under `runtimes/` — lives inside the directive folder. Stdlib-only
Python 3, no `pip install` required. The only runtime dependency is
`python3` on `$PATH`.

Then add an `agent-token-accounting` Directives subsection to `CONSTITUTION.md`
via the `governance-amend` skill (the directive and the constitutional entry must
land in one commit — that's the cardinal directive).

### Worktrees

If you commit from a git worktree, `core.hooksPath` is shared with the main
repository by default, which means `prepare-commit-msg` fires from the main
checkout's `.githooks/` and can silently miss updates on branches. Pin the
worktree to its own hook directory:

```sh
git config --worktree core.hooksPath .githooks
```

The `required-docs` directive's `hooks` sub-check accepts both forms; the
worktree-local override just ensures the hooks you are editing in the
worktree are the ones that actually run.

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
pre-commit ──► tests/governance/directives/agent-token-accounting/hooks/pre-commit.sh
      │          1. Detect runtime from env (CLAUDECODE / CODEX_THREAD_ID / AGENT_NAME)
      │          2. Read parent argv (/proc/$PPID/cmdline or `ps`) to recover
      │             the -m subject and parse the (#N) issue anchor
      │          3. Dispatch to runtimes/<runtime>.sh (sibling of the helper)
      │             — returns `<session_id> <cum_input> <cum_cache_create>
      │             <cum_cache_read> <cum_output> <model>`
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

`hooks/pre-commit.sh` picks the runtime from environment, in order:

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

The reader at `runtimes/claude-code.sh` inside the directive folder:

1. Finds the session JSONL under `~/.claude/projects/<encoded-cwd>/`, where
   the encoding replaces every `/` and `.` in the absolute path with `-`.
   Override with `CLAUDE_TRANSCRIPT_PATH` if needed.
2. Reads `sessionId` from the first entry that has one.
3. Sums every `assistant` entry's `.message.usage` fields into four
   separate cumulative counters — `input_tokens`,
   `cache_creation_input_tokens`, `cache_read_input_tokens`, and
   `output_tokens`. Keeping them separate lets the ledger stay lossless:
   billing dollars and cache-hit-rate analyses can be reconstructed later.
4. Tracks `.message.model` on every assistant entry; the latest non-empty,
   non-`<synthetic>` value wins so mid-session `/model` switches propagate
   forward. If nothing is seen, emits the literal string `unknown`, which
   `rates.py` can't price — the pre-commit hook will block with a clear
   error. Fix the transcript reader, or export `AGENT_MODEL` manually.
5. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model>`
   for `agent-accounting.sh`.

### Codex

Same story — `CODEX_THREAD_ID` is already set in Codex sessions, so no
wrapper is needed. The reader at `runtimes/codex.sh` inside the directive folder:

1. Locates the transcript by searching recursively under
   `~/.codex/sessions/` and `~/.codex/archived_sessions/` for a filename
   containing `CODEX_THREAD_ID`, falling back to the most recently modified
   `*.jsonl` under the sessions dir. Override with `CODEX_TRANSCRIPT_PATH`.
2. Derives the session id from `CODEX_THREAD_ID`, `session_meta.payload.id`,
   or finally the transcript filename.
3. Reads Codex Desktop's cumulative
   `event_msg.payload.info.total_token_usage` records when present. For
   OpenAI cached input, `cached_input_tokens` is a subset of `input_tokens`,
   so the reader emits `input = input_tokens - cached_input_tokens`,
   `cache_read = cached_input_tokens`, and `cache_create = 0`.
4. Falls back to summing common API shapes — top-level `usage`,
   `message.usage`, `response.usage` — handling both `input_tokens` /
   `output_tokens` and `prompt_tokens` / `completion_tokens` key pairs.
   It also understands `input_tokens_details.cached_tokens` and
   `prompt_tokens_details.cached_tokens`.
5. Tracks `model` from `payload.model`, `collaboration_mode.settings.model`,
   and the older top-level / nested model fields. Defaults to `unknown` if
   none of the transcript entries carry it; the pre-commit hook then blocks
   the commit since `unknown` can't be priced. Export `AGENT_MODEL`
   explicitly to override.
6. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model>`.

### Other runtimes

Drop a reader at `runtimes/<name>.sh` inside the directive folder — its only
job is to print
`<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model>`
on stdout (non-zero exit if it can't find a transcript), and add a branch
to the runtime-detection block in `hooks/pre-commit.sh`. Emit `0` for the
two cache fields if the runtime doesn't expose them; emit the literal
`unknown` for `model` if the transcript doesn't surface one.
`runtimes/codex.sh` is a ~60-line template.

Until you do that, `AGENT_NAME=<name> AGENT_SESSION_ID=... AGENT_CUM_INPUT=...
AGENT_CUM_OUTPUT=... git commit` (the `manual` path) works as an escape
hatch. `AGENT_CUM_CACHE_CREATE`, `AGENT_CUM_CACHE_READ`, and `AGENT_MODEL`
are optional — cache fields default to `0`, model defaults to `unknown`.

## What gets enforced where

All paths below are rooted at the installed directive folder
`tests/governance/directives/agent-token-accounting/`.

| Layer | What it checks |
|---|---|
| `runtimes/<runtime>.sh` | Transcript discovery + 4-field token sum + model extraction for one specific runtime. Prints 6 space-separated values. |
| `lib/rates.py` | Model → per-MTok USD rate table (base / cache-create / cache-read / output) + `compute_cost_usd(model, i, cc, cr, o)`. Tolerant model lookup: lowercase, strip date suffix, longest-prefix match with family fallbacks (`claude-opus`, `claude-sonnet`, `claude-haiku`, `gpt-5`). Unknown model → `None` → `rates cost` exits 3 → pre-commit blocks the commit (Cost-USD is mandatory). |
| `lib/ledger.py` | Stdlib-only Python library that owns the ledger: `LedgerRow` dataclass, `parse`, `sum_by_session`, `append_row` (recomputes `new_work`, looks up `cost_usd` from `rates.py`), `validate`, `find_by_cost_key`. Handles the v3 12-column schema and both legacy shapes (v2: 10 cols, v1: 8 cols). Keeping the schema-sensitive parsing in named-field Python (not `awk -F'\|'`) eliminates the whole class of column-index bugs we ate once already. |
| `lib/trailers.py` | Parses commit trailers and cross-checks them against a ledger row — `Token-Input == input + cache_create`, `Token-Output == output`, `Token-Total == Token-Input + Token-Output`, and `Token-Total == row.new_work` (so the trailer headline and the ledger headline can't drift). |
| `hooks/pre-commit.sh` | Bash glue: runtime detection, issue parsing from parent argv, cost-key generation, handoff env-file write. Shells out to `lib/ledger.py` for `sum-by-session` (per-commit delta) and `append-row` (ledger write + `git add`) — **all before** git snapshots the tree. Wired into `.githooks/pre-commit` by the generator. |
| `hooks/prepare-commit-msg.sh` | Sources the handoff env file (resolved via `git rev-parse --git-path governance-pending.env` so worktrees work) and stamps all eight trailers. Idempotent on amends (skips if an `Agent:` trailer is already present). Silent no-op if no handoff file exists (human commit, or `--no-verify`). Does not touch `COSTS.md`. |
| `check.sh` (commit-msg + CI) | Walks `base..HEAD`. Calls `lib/ledger.py validate` for repo-wide shape checks; for each commit with an `Agent:` trailer calls `lib/trailers.py validate` to require the full trailer set, check `Total = Input + Output`, require exactly one matching `Cost-Key` row in `COSTS.md`, and verify the row's numbers agree with the trailers. Runs independently of `COSTS.md` presence so the ledger stays clean even after branch commits are squashed away. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass the math check. That's a trust boundary — the directive makes tampering *visible* (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit. The durable anchor is `COSTS.md`, not the merge commit's metadata; keeping the directive to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling.
- **No invoice reconciliation.** `cost-usd` uses the rate table in the
  directive's `lib/rates.py` — that's the best we can do from a commit hook
  without network access. Rates drift, custom enterprise pricing exists,
  and Anthropic's invoice includes promotional credits and per-workspace
  overrides we can't see. Treat `cost-usd` as a commit-time estimate
  for prioritization; reconcile against the real invoice monthly.
- **No 1-hour cache pricing.** The rate table assumes the 5-minute TTL
  (Claude Code's default). If a runtime starts reporting 1h cache writes
  separately, `rates.py` will need a second cache-create column.

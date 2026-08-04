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

The model that works:

1. **The per-issue receipt** `receipts/issue-<N>.md` is the single durable record. Cost rows land under its `## Accounting` → `### Costs` sub-table, resolved from the commit's `(#N)` anchor. Homing rows in the receipt — instead of one central `COSTS.md` — keeps the record conflict-free (only the PR branch that owns the issue writes its receipt) and bounded (the file grows with one issue, not the whole repo's history), and it is naturally sealed once the receipt merges (frozen on the trunk by `doc-integrity`).
2. **Absolute cumulative coordinates** (`cum-*`) make a row claim a *position* on a monotonic counter, not a quantity.
3. **A frozen staged-tree endpoint** under `.git/governance-token-endpoints/<tree>.endpoint` records the exact cumulative coordinate the pre-commit writer sampled after it stages the receipt row.
4. **The governance directive** reconciles the staged receipt row against that frozen endpoint at commit time and fails loudly when the endpoint is missing or the row does not match it.

The previously-central `COSTS.md` is now sealed legacy history (a `doc-integrity` frozen-file) — it stops receiving writes; existing rows stay put, no migration. New rows go to receipts.

> **No commit trailers (issue #293).** Earlier versions stamped the cost onto
> the commit message as trailers (`Agent`/`Issue`/`Session`/`Token-*`/`Cost-Key`/
> `Cost-USD`) and cross-checked the stamped copy against the receipt row. The
> trailer was a denormalised projection of the row, kept honest by a
> bidirectional cross-check whose only consumer was the cross-check itself —
> plus a Mode-B HEAD-fallback to re-validate it after a server-side squash
> discarded the source commits. The receipt is already the ledger; completeness
> is now proven by freezing the pre-commit writer's sampled endpoint and
> verifying the staged row against it (endpoint reconciliation, below), rather
> than by stamping and re-verifying a copy. The cost is real but
> narrow: per-commit attribution for a `--no-verify` commit (no transcript in CI
> to reconcile against) is no longer recoverable — but the absolute coordinates
> preserve session-*total* fidelity, so a missing intermediate commit's tokens
> roll into the next accounted row and double-counting stays detectable.

## Endpoint reconciliation

The trailer-free completeness check. At commit time, with an agent runtime
detected, `check.sh` recomputes the staged tree id with `git write-tree`, reads
the frozen endpoint at `.git/governance-token-endpoints/<tree>.endpoint`, and
asserts that the staged receipt row named by the endpoint's `cost_key` carries
the same session and cumulative coordinate:

```
staged receipt row == frozen endpoint   →  pass
missing endpoint                         →  fail (pre-commit accounting did not run)
row mismatch                             →  fail (the staged row is not the sampled coordinate)
```

Because the pre-commit hook writes this commit's row (and advances the
per-session checkpoint) before the commit-msg check runs, a clean commit
reconciles by construction. If the live transcript advances between pre-commit
and commit-msg, the already-written row still passes because the endpoint is the
frozen coordinate for this commit attempt; the later movement belongs to a later
row. A commit that skipped the hook (`--no-verify`, `SKIP_GOVERNANCE=1`) has no
matching endpoint and fails here. The check is **commit-time only** — running it
off the commit path (e.g. a mid-session `run.sh`) would false-fail because no
staged-tree endpoint is expected there; in Mode B (CI) only the repo-wide
receipt-shape check runs.

## Row schema

Cost rows live in the commit's per-issue receipt — `receipts/issue-<N>.md`,
under the `## Accounting` → `### Costs` sub-table. v5 is 17 columns — the v4
schema plus a `source` column, and a redefined `cost-usd` (issue #355).
The record is lossless by design — cache traffic is tracked in its own columns,
and the dollar figure sits next to the token counts *when the harness reported
one*, so billing and cache-hit-rate analyses are recoverable after the fact
without anybody re-deriving a rate card:

```
| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |
```

- `model` — runtime-reported model id (e.g. `claude-sonnet-4-5`); empty for
  runtimes that don't surface it and for legacy rows.
- `input` — truly new input tokens.
- `cache-create` — tokens written to the prompt cache (billed at ~1.25× base).
- `cache-read` — tokens read from the prompt cache (billed at ~0.10× base) —
  **tracked but excluded from `new-work`**.
- `output` — model output tokens.
- `new-work = input + cache-create + output` (self-checking directive).
- `cum-input` / `cum-cache-create` / `cum-cache-read` / `cum-output` (v4, issue
  #229) — the session's **cumulative** counter for each column at this commit,
  written blind from the transcript. These are the row's absolute transcript
  coordinates and the accounting source of truth: a row claims a *position* on a
  monotonic counter, not a *quantity*, so the delta columns above are derived
  claims that the validator can prove (`delta == cum(n) − cum(n−1)`) once a
  session's consecutive rows are co-visible. Each `cum-*` is ≥ its own delta.
  The latest row's `cum-*` is also the coordinate the pre-commit hook freezes
  into the staged-tree endpoint for commit-time reconciliation.
- `cost-usd` (v5, issue #355) — **the dollar figure the harness itself
  reported, copied verbatim, or EMPTY when it reported none.** The kit does not
  price. Up to v4 this cell was computed from a hand-maintained per-model rate
  card shipped in `defaults.conf`; every number in it was a guess about someone
  else's billing, it went stale whenever a vendor moved a price, it was wrong
  for negotiated rates, and a model with no row *blocked the commit*. Rendered
  to four decimals, that guess read like a measurement. Now the runtime adapter
  reports what the harness reports and the cell stays blank otherwise — a blank
  cost is the honest record of "this harness does not tell us". Nothing about
  pricing can block a commit any more, because nothing here prices.
- `source` (v5) — the runtime adapter that produced the row (`claude-code`,
  `codex`, `manual`). It is what makes a mixed-harness ledger readable: a blank
  `cost-usd` next to `codex` means "that harness reports no dollars", not
  "somebody forgot".

`new-work` is the reviewer-facing token number — stable and denominator-free,
the figure a reviewer skims to ask "how much effort did this commit take".
`cache-read` is deliberately excluded from `new-work` — those are the same bytes
re-read each turn, not new work; including it would make `new-work` dominated by
cache hit-rate rather than the size of the change. If you want spend estimates
across a mixed fleet, compute them in your reporting layer over the token
columns, where they are visibly estimates.

Runtimes that don't report cache traffic (Codex today) emit `0` in the
cache columns — the row directive still holds.

Legacy rows are accepted by the parser, dispatched on cell count:

- **v4** (16 cols, pre-#355): the v5 row without `source`, and with a
  kit-computed `cost-usd`. Still validated to the v4 rules — including the old
  "a row that names a model carries a price" rule, so no historical receipt
  needs backfilling.
- **v3** (12 cols, pre-#229): the v4 row without the four `cum-*` columns.
  Validated to the v3 rules and **excluded from cumulative reconciliation /
  monotonicity** (those apply to v4 + v5 rows), so no historical receipt needs
  backfilling.
- **v2** (10 cols) / **v1** (8 cols) predate the cache split and are historical
  only; the current validator reports any row that is not 12, 16, or 17 cells.

All parsed shapes are validated under the same `new-work` directive; only v4 and
v5 rows carry the cumulative columns, and only v5 rows carry `source`.

## Installing

The directive ships as a self-contained folder under the `governance-kit/audit` pack.
The `governance-bootstrap` skill copies it wholesale and the hook generator
wires its `hooks/pre-commit.sh` (the row writer) into `.githooks/pre-commit` and
`check.sh` into `.githooks/commit-msg` automatically. Manual install is:

```sh
cp -r <governance-kit>/packs/audit/directives/agent-token-accounting \
      .governance/packs/governance-kit/audit/directives/
chmod +x .governance/packs/governance-kit/audit/directives/agent-token-accounting/check.sh \
         .governance/packs/governance-kit/audit/directives/agent-token-accounting/hooks/*.sh \
         .governance/packs/governance-kit/audit/directives/agent-token-accounting/runtimes/*.sh
```

There is no ledger file to seed at install — rows live in per-issue receipts,
and the pre-commit hook creates the receipt (an accounting-only stub with just
a `## Accounting` section) on demand the first time a commit for that issue
needs one. The directive ships no `COSTS.md` install-asset.

Everything the directive needs lives inside the directive folder: the `lib/`
bash libraries (`receipt.sh` markdown plumbing, `costs.sh` row schema + append,
`validate.sh` receipt validation, `endpoint.sh` frozen endpoint + session
checkpoint, `runtime.sh` detection), the `hooks/pre-commit.sh` writer, and the
per-harness adapters under `runtimes/`. **The commit path is bash + POSIX awk
only** (issue #355) — a consumer needs nothing but `bash` and `git` to commit.
The single python file, `lib/report.py`, is a stdlib-only cross-issue reporter a
human runs by hand; no hook, check, or adapter calls it, and the directive works
end to end on a machine with no python at all.

Then add an `agent-token-accounting` Directives subsection to `CONSTITUTION.md`
via the `governance` skill's `directive` verbs (the directive and the
constitutional entry must land in one commit — that's the cardinal directive).

### Worktrees

If you commit from a git worktree, `core.hooksPath` is shared with the main
repository by default, which means `pre-commit` fires from the main checkout's
`.githooks/` and can silently miss updates on branches. Pin the worktree to its
own hook directory:

```sh
git config --worktree core.hooksPath .githooks
```

The `required-docs` directive's `hooks` sub-check accepts both forms; the
worktree-local override just ensures the hooks you are editing in the
worktree are the ones that actually run.

## How a commit flows

`git commit` is the only entry point. There is no wrapper script to remember
or teach — if the commit is agent-authored, the pre-commit hook detects the
runtime, reads the transcript, resolves the issue from the `(#N)` anchor, and
appends the cost row to that issue's receipt (creating an accounting-only stub
if the receipt doesn't exist yet). The commit-msg check then reconciles the
receipt against the transcript. Human commits flow through untouched.

```
git commit -m "feat: x (#13)"
      │
      ▼
pre-commit ──► .governance/packs/<owner>/<repo>/directives/agent-token-accounting/hooks/pre-commit.sh
      │          1. Detect runtime + ask its adapter for the session's own
      │             reported usage via lib/runtime.sh (CLAUDECODE /
      │             CODEX_THREAD_ID / AGENT_NAME → `runtimes/<runtime>.sh cost`,
      │             which returns `<session_id> <cum_input> <cum_cache_create>
      │             <cum_cache_read> <cum_output> <model> <cost_usd>`)
      │          2. Read the parent git argv (/proc/$PPID/cmdline on Linux,
      │             `ps -ww -o args=` on macOS/BSD) to recover the -m subject
      │             and parse the (#N) issue anchor
      │          3. Read the session's prior cumulative from the git-dir
      │             checkpoint (`checkpoint_get`, file
      │             `governance-token-checkpoints/<session>`) and subtract from
      │             the reported total → per-commit delta. NOT scanned from the
      │             receipts (issue #229): the delta never depends on which
      │             sibling receipts are visible.
      │          4. Compute Cost-Key, append the row (delta columns, the four
      │             absolute `cum-*` coordinates, the harness's own cost figure
      │             or an empty cell, and the `source` adapter id) to
      │             `receipts/issue-<N>.md` under `## Accounting` → `### Costs`
      │             (`costs_append_row`, creating the stub receipt if absent),
      │             `git add` the receipt, compute the staged tree id with
      │             `git write-tree`, write
      │             `.git/governance-token-endpoints/<tree>.endpoint` with the
      │             sampled coordinate and cost-key, then advance the checkpoint
      │             (`checkpoint_set`) to this commit's cumulative
      │
      ▼
git snapshots the tree (the receipt row is already staged)
      │
      ▼
commit-msg ──► check.sh: endpoint reconciliation. Detects the active runtime,
               recomputes the staged tree id, reads the frozen endpoint, and
               asserts the staged receipt row named by the endpoint's cost-key
               has the same session + cum-* coordinate. Missing endpoint or
               mismatch → fail. Also runs validate-dir for repo-wide
               receipt-shape integrity.
      │
      ▼
commit lands
```

The ordering is load-bearing. `git add` during **pre-commit** lands in the
tree git is about to snapshot; from any post-snapshot hook it would land in the
*next* commit's index. A CI failure of the form `token ledger ... records
cumulative ... but the transcript is at ...` means the pre-commit row write was
skipped or failed.

The checkpoint and endpoint paths are resolved via `git rev-parse --git-path`
(`governance-token-checkpoints/<session>` and
`governance-token-endpoints/<tree>.endpoint`, both flat `key=value` files since
issue #355) — that's deliberate. In a worktree
`.git` is a pointer file, not a directory; hardcoding `$ROOT/.git/…` breaks
silently.

### Runtime detection

`lib/runtime.sh` picks the runtime from environment, in order:

| Signal | Runtime |
|---|---|
| `AGENT_NAME` set (any value) | `manual` — caller supplies `AGENT_SESSION_ID`, `AGENT_CUM_INPUT`, `AGENT_CUM_OUTPUT` (plus optional `AGENT_CUM_CACHE_*`, `AGENT_MODEL`, `AGENT_COST_USD`) |
| `CLAUDECODE=1` | `claude-code` — reads `~/.claude/projects/<encoded-cwd>/*.jsonl` |
| `CODEX_THREAD_ID` or `CODEX_TRANSCRIPT_PATH` set | `codex` — reads `~/.codex/sessions/*.jsonl` |
| none of the above | no agent runtime — the writer no-ops and the check passes |

The issue anchor is parsed from the parent git's `-m` / `--message` argv, or
can be supplied explicitly via `AGENT_ISSUE='#13'` (useful for editor-mode
commits where argv has no `-m`).

### Claude Code

No setup beyond installing the hooks. `CLAUDECODE=1` is already exported to
every Bash tool invocation, so `git commit -m "feat: x (#13)"` from an
agent session Just Works.

The adapter at `runtimes/claude-code.sh` inside the directive folder answers the
`cost` verb (`runtimes/claude-code.sh cost`; a bare invocation means the same
thing) and:

1. Finds the session JSONL under `~/.claude/projects/<encoded-cwd>/`, where
   the encoding replaces every `/` and `.` in the absolute path with `-`.
   Override with `CLAUDE_TRANSCRIPT_PATH` if needed.
2. Reads `sessionId` from the first entry that has one.
3. Sums every `assistant` entry's `.message.usage` fields into four
   separate cumulative counters — `input_tokens`,
   `cache_creation_input_tokens`, `cache_read_input_tokens`, and
   `output_tokens`. Keeping them separate lets the ledger stay lossless.
4. Tracks the model on every assistant entry; the latest non-empty,
   non-`<synthetic>` value wins so mid-session `/model` switches propagate
   forward. If nothing is seen, emits `unknown` — a label on the row, nothing
   more; it cannot block a commit, because nothing prices it.
5. Sums the transcript's own `costUSD` values when it carries them, and emits
   the literal `-` when it does not.
6. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>`.

The extraction is POSIX awk with conservative, key-anchored substring lookups
(issue #355) — a malformed JSONL line simply contributes nothing rather than
aborting the read. Exit 2 means "the runtime is here but its transcript is
unreadable".

### Codex

Same story — `CODEX_THREAD_ID` is already set in Codex sessions, so no
wrapper is needed. The adapter at `runtimes/codex.sh` answers the same `cost`
verb and:

1. Locates the transcript from `CODEX_TRANSCRIPT_PATH`, or by searching
   recursively under `~/.codex/sessions/` and `~/.codex/archived_sessions/`
   for a filename ending with `CODEX_THREAD_ID.jsonl`.
2. Reads the session id from `CODEX_THREAD_ID` or `session_meta.payload.id`.
3. Reads Codex Desktop's cumulative
   `event_msg.payload.info.total_token_usage` records. For
   OpenAI cached input, `cached_input_tokens` is a subset of `input_tokens`,
   so the reader emits `input = input_tokens - cached_input_tokens`,
   `cache_read = cached_input_tokens`, and `cache_create = 0`.
4. Tracks `model` from `turn_context.payload.collaboration_mode.settings.model`.
   Defaults to `unknown` if the transcript does not carry it.
5. Emits `-` for `cost_usd` — the current Codex stream reports no dollar figure.
   If a future stream adds `total_cost_usd` to the token-count payload, the
   adapter passes it through untouched.
6. Prints `<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>`.

### Other runtimes

Drop an adapter at `runtimes/<name>.sh` inside the directive folder — its only
job is to answer the `cost` verb by printing
`<session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>`
on stdout (exit 2 if it can't read the session), and add a branch to the
detection block in `lib/runtime.sh`. Emit `0` for the two cache fields if the
runtime doesn't expose them, `unknown` for `model` if the transcript doesn't
surface one, and `-` for `cost_usd` unless the harness reports a dollar figure
of its own. **An adapter may sum harness-reported numbers; it must never
price.** `runtimes/codex.sh` is the template.

Until you do that:

- A commit from an **unrecognised runtime no-ops** the endpoint check (no
  transcript to reconcile against, so nothing to fail) — no waiver needed.
- The **manual env path** still writes a real cost row from values you supply:
  `AGENT_NAME=<name> AGENT_SESSION_ID=... AGENT_CUM_INPUT=... AGENT_CUM_OUTPUT=...
  git commit`. `AGENT_CUM_CACHE_CREATE`, `AGENT_CUM_CACHE_READ`, `AGENT_MODEL`
  and `AGENT_COST_USD` are optional — an omitted or non-decimal
  `AGENT_COST_USD` writes an empty cost cell rather than a guess. Use when you
  know the numbers.
- For the rare legitimate out-of-hook commit (or an unrecoverable reconciliation
  mismatch), a `governance: allow-agent-token-accounting <reason>` body waiver
  (reason required) bypasses the endpoint check for that commit. Audit trail:
  `git log --grep='allow-agent-token-accounting'`.

## What gets enforced where

All paths below are rooted at the installed directive folder
`.governance/packs/<owner>/<repo>/directives/agent-token-accounting/`.

| Layer | What it checks |
|---|---|
| `lib/runtime.sh` | Runtime detection + the session's reported usage. Sourced by both `hooks/pre-commit.sh` (the writer) and `check.sh` (the checker), so both read the same runtime-side value. Dispatches the `cost` verb to `runtimes/<runtime>.sh` and exposes `SESSION_ID` / `CUM_*` / `MODEL` / `COST_USD`. |
| `runtimes/<runtime>.sh` | One harness adapter: transcript discovery, 4-field token sum, model extraction, and the harness's own cost figure (or `-`). Answers the `cost` verb; prints 7 space-separated values. POSIX awk, no python. |
| `defaults.conf` | Pack-owned, and deliberately **doc-only** since issue #355: it explains why the kit keeps no rate card. There are no knobs to set. |
| `lib/receipt.sh` | Markdown section/table plumbing: find the `## Accounting` → `### Costs` region, emit its data rows, splice a new row into the tail (creating file/section/sub-table as needed), sanitise a free-text cell, resolve `issue-N*.md`. Bash + POSIX awk. |
| `lib/costs.sh` | The v5 row schema: header/separator constants, `costs_append_row` (recomputes `new-work`, writes the delta + `cum-*` + `cost-usd` + `source` columns), `costs_next_index` (the same-second cost-key counter), `costs_find_cum` (the endpoint's row lookup). |
| `lib/validate.sh` | `costs_validate_dir` — the whole receipt validator in one POSIX-awk program: per-row shape (v3 / v4 / v5 by cell count), numeric rules, `new-work`, empty-or-decimal `cost-usd`, non-empty `source` on v5, `cum-* ≥ delta`, cost-key uniqueness within and across receipts, per-session monotonicity, and `delta == cum(n) − cum(n−1)` against the nearest co-visible predecessor. |
| `lib/endpoint.sh` | Flat `key=value` frozen endpoint (`governance-token-endpoints/<tree>.endpoint`) and per-session checkpoint (`governance-token-checkpoints/<session>`): `endpoint_write` / `endpoint_verify` / `checkpoint_get` / `checkpoint_set`. |
| `lib/report.py` | **Off the commit path.** A stdlib-only, self-contained aggregation of the Accounting sections across `receipts/*.md` for per-issue and grand totals, including a count of rows with no reported cost. Run by hand: `python3 <dir>/report.py <receipts_dir> [--json]`. Nothing executable by git calls it. |
| `hooks/pre-commit.sh` | Bash glue: sources `lib/runtime.sh` for detection + usage, parses the issue from parent argv, generates the cost-key, appends the row (`costs_append_row`), `git add`s the receipt, freezes the staged-tree endpoint, and advances the checkpoint — **all before** git snapshots the tree. Wired into `.githooks/pre-commit`. No pricing step, so it cannot block on an unknown model. |
| `check.sh` (commit-msg + CI) | Always runs `costs_validate_dir` (repo-wide shape, global cost-key uniqueness, cumulative reconciliation / monotonicity). In Mode A (commit-msg), when a runtime is detected, additionally requires a frozen endpoint for the staged tree and verifies the staged receipt row matches it. Recognises one body waiver: `governance: allow-agent-token-accounting <reason>`. Mode B (CI) runs the receipt-shape check only — per-commit completeness is a write-time property; on the trunk the receipt is the record. |

## What it doesn't try to do

- **No authentication** of token counts. A wrapper that fabricates numbers will pass. That's a trust boundary — the directive makes tampering *visible* (git blame on the per-issue receipt), not impossible.
- **No commit-message metadata.** The durable anchor is the per-issue receipt row, not the commit message; keeping the directive to files-in-the-repo avoids a hard coupling to GitHub / GitLab PR tooling and survives squash natively.
- **No per-commit completeness for `--no-verify` commits.** With no transcript in CI to reconcile against, a hook-skipped commit's missing row can't be detected there; the absolute `cum-*` coordinates keep the session *total* honest regardless (the tokens roll into the next accounted commit's row).
- **No pricing, at all.** `cost-usd` is the harness's own figure or nothing (issue #355). The kit ships no rate card, so it can't be stale, can't be wrong about your negotiated rate, and can't block a commit over a model it has never heard of. The flip side: for a harness that reports no dollars, the ledger records tokens only — teach that harness's adapter to surface its own figure, don't reintroduce a rate table.
- **No invoice reconciliation.** Even a harness-reported figure is the harness's view, not your bill. Reconcile against the real invoice on your own cadence.

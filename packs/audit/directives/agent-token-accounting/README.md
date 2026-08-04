# Agent Token Accounting

Opt-in governance directive that gives the repo a durable, auditable ledger of
what its agent sessions cost — across any harness (Claude Code, Codex, pi,
Cursor, opencode, grok, or something homegrown).

## The principle: identity at commit, measurement at rest

A pre-commit hook is the worst possible measurement point. It is synchronous,
blocking, unretryable, and racing a session that is still running — and a
session's cost is not final at commit time anyway, because the session keeps
going after the commit lands. Any number captured there is a snapshot of a
moving quantity dressed up as a fact, and any failure to capture it turns a
*measurement* problem into a *commit* problem, which is exactly backwards.

So the two halves split, because they have different natures:

- **Identity** is cheap, local, and knowable *only* at commit time: the harness
  announces itself in the environment. The commit path records identity and
  validates structure. It never reads a harness file, never parses a
  transcript, never does arithmetic on tokens. Pure bash and git, kit-owned
  files only.
- **Measurement** is expensive, remote, retryable, and better late than wrong.
  It happens off the commit path: adapters refresh a kit-owned snapshot
  sidecar from each harness's *declared* surfaces — a pushed payload, a
  harness-named file, a queryable local server. A failed read means "try again
  later", never "commit blocked", and never a guessed number.

Two provenance rules follow, and they are load-bearing:

1. **The kit never prices.** `cost-usd` is the harness's own figure verbatim,
   or `-`. See "No rate card" below.
2. **The kit never guesses identity.** Every "newest file wins" / mtime
   heuristic is deleted. No identity means no session, which means no numbers:
   the row says `-` and `unresolved` until something real resolves it. A
   guessed session id silently bills one agent's spend to another, which is
   strictly worse than a blank.

## Why the row is per session, not per commit

A session that touches an issue across twenty commits is **one unit of spend**,
not twenty. Per-commit attribution forces deltas; deltas force a checkpoint;
and a checkpoint double-counts the moment a session spans branches. So v6 keeps
**one row per session per issue**, updated in place while the PR is open —
receipts freeze only once they reach the trunk, so the update window is exactly
the pull request's life.

That single change is what makes the ledger self-healing. When a session's
spend keeps growing after its last commit, the *next* commit — from any session
— folds the newer total into the older session's row. No per-commit row could
ever do that; it was frozen the moment it was written, permanently short by the
tail of the session.

## Where things live

The per-issue receipt `receipts/issue-<N>.md` is the single durable record.
Rows land under its `## Accounting` → `### Costs` sub-table, resolved from the
commit's `(#N)` anchor. Homing rows in the receipt — instead of one central
`COSTS.md` — keeps the record conflict-free (only the PR branch that owns the
issue writes its receipt) and bounded (the file grows with one issue, not the
whole repo's history), and it is naturally sealed once the receipt merges
(frozen on the trunk by `doc-integrity`).

Two kit-owned artifacts back it, both under the **per-worktree git dir** (a
worktree is the natural session-disambiguation boundary — two worktrees never
collide) and neither ever reaching a commit:

```
<git-dir>/governance/session-identity        flat key=value, last writer wins
    harness=<adapter-name>
    session=<session-id>
    declared=<absolute path the harness handed us, or empty>
    epoch=<unix seconds>

<git-dir>/governance/costs/<harness>-<session>     append-only, one per session
    v1 <epoch> <input> <cache_create> <cache_read> <output> <model> <cost|-> <source>
```

The identity file is written by a wired harness hook (SessionStart and friends)
or by an adapter's `emit` verb. It is optional — environment detection works
without it — and it is how a harness that exports *nothing* to its child
processes still gets identified. It is trusted only while it is younger than
`COSTS_IDENTITY_MAX_AGE_HOURS` (default 24), because a file, unlike an
environment, can outlive the session that wrote it.

The sidecar is append-only; each line is a snapshot of the harness's own
**session-cumulative** counters, never a delta. Writers are the adapter's
`emit` (live push) and `resolve` (off-path pull) verbs. The commit path only
ever reads it.

## Row schema (v6, 10 columns)

```
| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
```

- `date` — the day this session first touched this issue. Never rewritten.
- `harness` / `session` — the identity the environment (or the identity file)
  announced. `session` is the literal `-` when the harness does not name one.
- `model` — the harness-reported model id, or `-`.
- `input` / `cache-create` / `cache-read` / `output` — the harness's own
  session-cumulative token counters from the sidecar's authoritative snapshot,
  or `-` when nothing has resolved yet. Kept separate so the record stays
  lossless: cache-hit-rate analyses are recoverable after the fact.
- `cost-usd` — the dollar figure the harness itself reported, copied verbatim,
  or `-`.
- `source` — provenance of the numbers: `harness-feed`, `session-file`,
  `server`, `manual`, or `unresolved`.

### The fold rule

A session can have snapshots from more than one source. The authoritative one
is the latest snapshot overall, **except** that a `session-file` / `server`
reading wins any tie or later position — those carry full token detail, while a
`harness-feed` push may legitimately carry only cost and identity. Put the
other way round: prefer the latest file/server reading over a harness-feed one
whenever it is not older. Adapters and the directive both depend on this rule,
so it is specified here rather than implied.

### Legacy rows

Rows in the retired schemas are recognised by cell count — 17 = v5, 16 = v4,
12 = v3 — and **structurally tolerated, never re-judged**. They were written
under rules that no longer describe them, so re-validating them would only
manufacture violations nobody can act on; receipts on the trunk are frozen
anyway.

## No rate card

Up to v4 this directive shipped one: a `rate <model> <base> <cache_create>
<cache_read> <output>` row per model, in USD per million tokens, which the
commit hook multiplied against the transcript to fill `cost-usd`. Every number
in it was a guess about someone else's billing — hand-maintained, silently
stale the day a vendor moved a price, wrong for negotiated rates — and a model
with no row *blocked the commit*. Rendered to four decimal places, that guess
read like a measurement.

Now the harness reports the dollars or the cell stays `-`. A blank cost next to
`source = codex` is the honest record of "that harness does not report
dollars", not a bug. If you want dollars from a harness that doesn't surface
them, teach its **adapter** to read the harness's own figure — do not
reintroduce a rate table. If you want a spend estimate across a mixed fleet,
compute it in your reporting layer over the token columns, where it is visibly
an estimate.

## How a commit flows

`git commit` is the only entry point. There is no wrapper script to remember.

```
git commit -m "feat: x (#13)"
      │
      ▼
pre-commit ──► hooks/pre-commit.sh — "stamp & fold"
      │          1. detect_runtime_identity: harness + session + declared path
      │             from the environment, falling back to a FRESH identity file.
      │             No tokens. No cost. No guessing.
      │          2. Read the parent git argv (/proc/$PPID/cmdline on Linux,
      │             `ps -ww -o args=` on macOS/BSD) for the (#N) issue anchor,
      │             or take AGENT_ISSUE.
      │          3. Upsert this session's row in receipts/issue-<N>.md,
      │             refreshed from the sidecar's authoritative snapshot — or
      │             `-` everywhere with source `unresolved` when there isn't one.
      │          4. Fold every OTHER session row in that receipt whose sidecar
      │             has moved (self-healing convergence).
      │          5. `git add` the receipt.
      │
      ▼
git snapshots the tree (the row is already staged)
      │
      ▼
commit-msg ──► check.sh: identity truth. A staged receipt must carry a v6 row
      │        for exactly the detected harness + session. Numbers are NEVER
      │        compared. Plus the repo-wide Costs-table shape check.
      │
      ▼
commit lands
      │
      ▼
post-commit ─► hooks/post-commit.sh: resolve sweep, silent, always exit 0.
               Each known session's adapter is asked what the harness now says.
      │
      ▼
pre-push ────► hooks/pre-push.sh: the same sweep, one last time before the work
               leaves the machine (nothing in CI can measure a session that ran
               on a laptop). Never blocks a push; prints one line when a row is
               behind its sidecar.
```

The ordering is load-bearing. `git add` during **pre-commit** lands in the tree
git is about to snapshot; from any post-snapshot hook it would land in the
*next* commit's index.

### Worktrees

If you commit from a git worktree, `core.hooksPath` is shared with the main
repository by default, which means `pre-commit` fires from the main checkout's
`.githooks/` and can silently miss updates on branches. Pin the worktree to its
own hook directory:

```sh
git config --worktree core.hooksPath .githooks
```

## Identity detection ladder

`lib/runtime.sh` resolves the identity from the environment, in order:

| Signal | Harness | Session |
|---|---|---|
| `AGENT_NAME` set (any value) | `manual` | `AGENT_SESSION_ID`, else `manual` |
| `CLAUDECODE=1` | `claude-code` | `CLAUDE_CODE_SESSION_ID`, else identity file, else `-` |
| `CODEX_THREAD_ID` or `CODEX_TRANSCRIPT_PATH` | `codex` | `CODEX_THREAD_ID`, else `-` |
| `PI_CODING_AGENT=true` or `PI_SESSION_ID` | `pi` | `PI_SESSION_ID`, else `-` |
| `CURSOR_AGENT=1` | `cursor-agent` | identity file, else `-` |
| `OPENCODE=1` or `OPENCODE_SERVER` | `opencode` | `OPENCODE_SESSION_ID`, else identity file, else `-` |
| none of the above, fresh identity file | its `harness=` | its `session=` |
| nothing at all | — | no agent runtime; writer and check both no-op |

`CLAUDE_TRANSCRIPT_PATH`, `CODEX_TRANSCRIPT_PATH` and `PI_SESSION_FILE` are
carried through as the *declared path* and handed to the adapter's `resolve`
verb later. Environment identity always beats the identity file; the file may
only fill in a session id (or declared path) the environment left blank, and
only when it names the same harness.

## The adapter contract

Adapters are **kit-level**, not pack-level: "which harness am I talking to" is
one fact about the repo, not a per-directive one. One registry at
`.governance/runtimes/<harness>.sh`, shared with the sub-agent lane's `judge`
verb. Each file is self-contained bash, invoked as `bash <adapter> <verb>`
(never executed directly — the registry is a copied tree and a lost exec bit
must not silently disable accounting).

```
resolve <session-id> [<declared-path>]
    → one line: `<input> <cache_create> <cache_read> <output> <model> <cost|-> <source>`
    → exit 2 when it cannot resolve; the caller then records NOTHING.

emit
    ← the harness's own push payload on stdin (statusline / hook JSON).
      Appends a `harness-feed` snapshot and refreshes the identity file.
      Must be safe to call at high frequency.
```

**Identity-pinned reads only.** The only things an adapter may open are: an
explicitly passed declared path, a file whose *name contains the exact session
id* under the harness's documented state dir, or a harness-declared local
server. `ls -t`, `-mmin`, "the newest file" — forbidden, and deleted from every
adapter that had them.

An adapter may **sum** harness-reported numbers; it must never **price** them.
Emit `0` for cache fields a harness doesn't expose, `-` for an unknown model,
and `-` for `cost-usd` unless the harness reports a dollar figure of its own.
A harness with no documented per-session usage surface (Cursor today) simply
exits 2, and the row stays honestly `-` / `unresolved` — which is a true
statement, not a gap.

## What gets enforced where

All paths below are rooted at the installed directive folder
`.governance/packs/<owner>/<pack>/directives/agent-token-accounting/`.

| Layer | What it does |
|---|---|
| `lib/runtime.sh` | The identity ladder (`detect_runtime_identity`), the adapter-registry resolver (`adapter_for`, `adapter_names`), and the kit-owned artifact paths (`identity_file`, `sidecar_dir`, `sidecar_file`, `sidecar_last`). Sourced by the check and all three hooks, so every path resolves identity identically. |
| `lib/costs.sh` | The v6 row schema and the sidecar schema: header/separator constants, `costs_upsert_row` (one row per session, in place, keeping its original date), `costs_row` / `costs_row_snapshot` / `costs_session_keys` for lookups, `costs_snapshot_append` (append-only, deduplicated), and `costs_fold_snapshot` (the fold rule above). |
| `lib/receipt.sh` | Markdown section/table plumbing: find the `## Accounting` → `### Costs` region, emit its data rows, splice a new row into the tail (creating file/section/sub-table as needed), sanitise a free-text cell, resolve `issue-N*.md`. |
| `lib/validate.sh` | `costs_validate_dir` — the whole table validator in one POSIX-awk program: cell count, date shape, non-empty identity and model, integer-or-`-` token cells, decimal-or-`-` dollars, a `source` from the closed set, and one row per session per receipt. It never compares a number to anything. |
| `lib/resolve.sh` | The sweep driver: enumerate every session this worktree knows about (identity file plus every sidecar), invoke each adapter's `resolve`, validate the shape of what comes back, and append the snapshot. Refuses malformed adapter output rather than recording it. |
| `hooks/pre-commit.sh` | Stamp & fold, then `git add` the receipt — all before git snapshots the tree. Blocks only on structural impossibility (an agent runtime with no inferable issue anchor). Nothing about measurement can block anything. |
| `hooks/post-commit.sh` | The resolve heartbeat. Silent, always exit 0. |
| `hooks/pre-push.sh` | The resolver's last local chance. Never blocks a push; prints one line when a receipt row is behind its sidecar. |
| `check.sh` (commit-msg + CI) | Mode A: identity truth for the staged tree, plus the repo-wide shape check. Mode B (CI): shape only — unresolved rows are explicitly allowed, because CI has no session state and demanding numbers there would only teach agents to invent them. Recognises one body waiver: `governance: allow-agent-token-accounting <reason>`. |
| `defaults.conf` | Pack-owned. One knob — `COSTS_IDENTITY_MAX_AGE_HOURS` — plus the record of what this file deliberately does *not* contain (a rate card, a detection heuristic). |

## Installing

The directive ships as a self-contained folder under the `governance-kit/audit`
pack. The `governance` skill copies it wholesale and the hook generator wires
`hooks/pre-commit.sh`, `hooks/post-commit.sh` and `hooks/pre-push.sh` into the
matching dispatchers and `check.sh` into `.githooks/commit-msg` automatically.
Manual install is:

```sh
cp -r <governance-kit>/packs/audit/directives/agent-token-accounting \
      .governance/packs/governance-kit/audit/directives/
chmod +x .governance/packs/governance-kit/audit/directives/agent-token-accounting/check.sh \
         .governance/packs/governance-kit/audit/directives/agent-token-accounting/hooks/*.sh
```

There is no ledger file to seed — rows live in per-issue receipts, and the
pre-commit hook creates the receipt (an accounting-only stub with just an
`## Accounting` section) on demand. **The whole directive is bash and POSIX
awk** — commit path and resolver alike — so a consumer needs nothing but `bash`
and `git`.

Then add an `agent-token-accounting` Directives subsection to `CONSTITUTION.md`
via the `governance` skill's `directive` verbs (the directive and the
constitutional entry must land in one commit — that's the cardinal directive).

### Wiring a harness emitter

Nothing below is required: without it, a harness that exports environment
variables is still identified, and its adapter's `resolve` still measures it.
Wiring the harness's own hook or statusline to `bash
.governance/runtimes/<harness>.sh emit` buys two things — identification for a
harness that exports nothing, and live cost pushes between resolves. Because it
edits *your* harness configuration rather than the repo, `governance install`
offers it, records it in the install ledger, and reverses it on uninstall.

## What it doesn't try to do

- **No authentication of the numbers.** A harness or wrapper that reports
  fabricated figures will pass. That is a trust boundary: the directive makes
  tampering *visible* (git blame on the per-issue receipt), not impossible.
- **No commit-message metadata.** The durable anchor is the receipt row, not
  the commit message; keeping the directive to files-in-the-repo avoids a hard
  coupling to GitHub / GitLab PR tooling and survives squash natively.
- **No per-commit attribution.** By design — see "Why the row is per session".
  If you need to know which commit in a session was expensive, that question is
  answered by the transcript, not by the ledger.
- **No pricing, at all.** The kit ships no rate card, so it can't be stale,
  can't be wrong about your negotiated rate, and can't block a commit over a
  model it has never heard of.
- **No invoice reconciliation.** Even a harness-reported figure is the
  harness's view, not your bill. Reconcile against the real invoice on your own
  cadence.

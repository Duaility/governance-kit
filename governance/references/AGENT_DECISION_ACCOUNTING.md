<!-- last-verified: 2026-04-25 -->

# Agent Decision Accounting

Opt-in governance directive that gives the repo a durable, auditable
ledger of **load-bearing human decisions** made during agent-driven
development — across any runtime (Codex, Claude Code, Cursor, or
something homegrown). Sibling to [`agent-token-accounting`](AGENT_TOKEN_ACCOUNTING.md);
where that directive records *cost*, this one records *where the human
diverged from the agent's lean*.

## Why it's layered this way

Unlike token counts, divergence is not a signal the runtime emits for
free. The agent has to structurally declare its lean at question time,
so that when the human answers differently the divergence is mechanically
detectable rather than a judgment call read off a transcript after the
fact. That's the whole reason this directive exists:

- **Capture is deliberate**, not mined from transcripts. An agent that
  doesn't tag its own asks produces an empty ledger — that's a feature.
  Silent "somebody diverged here" inference from chat logs is noisy and
  retrospective. Rows authored at question time are authoritative.
- **Baseline density matters.** Recording only divergences gives you a
  numerator with no denominator — you can count overrides but not compute
  override rate. The directive records *every load-bearing decision*.
- **`reframed` is the highest-value signal.** A binary "diverged? y/n"
  flag collapses the case where the human rejects the *question itself*,
  which is the only signal that says "the agent is asking the wrong
  questions," not just "the agent's lean is wrong." The fixed four-state
  vocabulary preserves it.
- **Squash-merge safety.** Commit trailers (`Decision-Key:`,
  `Decision-Diverged:`) survive squash merges; the ledger
  (`DECISIONS.md`) is the durable anchor.

## Trailer schema

Both trailers are optional — a commit that recorded no load-bearing
decisions omits both. If one is present the other must be, too.

```
Decision-Key: codex-abc-d001,codex-abc-d002
Decision-Diverged: 2/2
```

- `Decision-Key` — comma-separated list of keys, each resolving to
  exactly one append-only row in `DECISIONS.md`.
- `Decision-Diverged` — `"M/N"` where `N` equals the count of listed keys
  and `M` equals the count of listed rows whose `diverged` is not
  `agreed`. The counter is cheap to produce and makes divergence rate
  visible in `git log` without parsing the ledger.

## Ledger schema

`DECISIONS.md` lives at repo root alongside `COSTS.md`. Append-only,
11 columns:

```
| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
```

- `decision-key` — unique within the file. Convention:
  `<agent>-<session-short>-d<NNN>`.
- `agent` — runtime id (`claude-code`, `codex`, ...).
- `session` — stable runtime session / thread id.
- `issue` — `#N`, same anchor the rest of governance-kit uses.
- `phase ∈ {scoping, plan-review, pr-review, post-merge}` — *when* in
  the lifecycle the decision happened. `scoping` is pre-plan, `plan-review`
  is while drafting a plan, `pr-review` is on an open PR, `post-merge`
  is after the change has landed.
- `question` — one-line summary of the ask. Keep tight; this goes in a
  markdown cell.
- `lean` — the agent's recommended answer. **Required — not inferred.**
  If the agent didn't declare a lean up front, the row has no business
  existing; divergence against an unstated lean is post-hoc fiction.
- `choice` — the human's chosen answer.
- `diverged ∈ {agreed, overrode, reframed, deferred}`:
  - `agreed` — human picked the lean.
  - `overrode` — human picked a different option the agent offered.
  - `reframed` — human rejected the question itself ("wrong thing to ask").
  - `deferred` — human kicked it to later (signals ambiguity the agent missed).
- `cost-key` — optional cross-ref to a `COSTS.md` row so
  "cost of this override" is a single join away. Empty / `-` means
  unlinked. Cross-check runs only when `COSTS.md` is present; this
  directive does not hard-require `agent-token-accounting`.
- `note` — free-text, optional. Keep it short; `DECISIONS.md` is a
  ledger, not a discussion thread.

## What's a "load-bearing" decision?

Not every `AskUserQuestion` gets a row. Rule of thumb:

- **Record** — decisions that shape scope, architecture, API surface,
  wire format, naming vocabulary, security posture, or the set of
  follow-ups.
- **Skip** — procedural pings ("continue? y/n"), clarification of an
  already-agreed item ("which of the two paths you just showed?"), or
  typo-level fixes.

When in doubt, record. The cost of an extra ledger row is cents; the
cost of a missing row is an entire missing data point.

## Installing

The directive ships as a self-contained folder under the
`agent-governance` pack. The `governance init` skill copies it wholesale
into `tests/governance/directives/agent-decision-accounting/`. Manual
install:

```sh
cp -r <governance-kit>/extensions/packs/agent-governance/directives/agent-decision-accounting \
      tests/governance/directives/
cp    <governance-kit>/extensions/packs/agent-governance/directives/agent-decision-accounting/install-assets/DECISIONS.md \
      DECISIONS.md
chmod +x tests/governance/directives/agent-decision-accounting/check.sh
```

Stdlib-only Python 3, no `pip install` required. The only runtime
dependency is `python3` on `$PATH`.

Then add an `agent-decision-accounting` Directives subsection to
`CONSTITUTION.md` via the `governance directive add` verb (the directive
test and the constitutional entry must land in one commit — that's the
cardinal directive).

This directive is **not** in the `agent-governance.standard` preset. It
ships opt-in until divergence rates prove the signal is worth the
install cost for a given repo.

## Runtime-agnostic by construction

There is **no per-runtime reader** under `runtimes/`, unlike
`agent-token-accounting`. The reason: cost is a mechanical signal the
runtime emits for free, so sibling readers are the right shape. A
*structured lean*, by contrast, is not something Claude Code or Codex
emit today — it has to come from agent discipline at question time.

Both runtimes write the same markdown rows and stamp the same trailers;
below are worked examples.

### Claude Code

Claude Code exports `CLAUDECODE=1` and a Claude-side session id is
available via `~/.claude/projects/<encoded-cwd>/*.jsonl` (same mechanism
`agent-token-accounting/runtimes/claude-code.sh` uses). When the agent
poses a load-bearing question:

1. Generate a stable `decision-key` — convention
   `claude-code-<session-short>-d<NNN>` where `NNN` is monotonic within
   the session.
2. Append a row to `DECISIONS.md` **before** presenting the question
   (so the row exists if the user answers and walks away).
3. After the user answers, rewrite the `choice` / `diverged` cells on
   the same line — parsers are row-append-only but in-progress row
   *completion* is fine. The directive fails if a row's `diverged` cell
   is missing or outside the vocabulary.
4. When the agent runs `git commit`, include the trailers directly:

   ```sh
   git commit -m "feat: rewrite readme (#42)

   Decision-Key: claude-code-cbdb387d-d001,claude-code-cbdb387d-d002
   Decision-Diverged: 1/2"
   ```

   The `commit-msg` hook reads the trailers, cross-checks against
   `DECISIONS.md`, and blocks the commit on any mismatch.

### Codex

Codex exports `CODEX_THREAD_ID`. The flow is identical to Claude Code's
— only the `agent` column value changes:

```
| codex-01HXYZ-d001 | codex | 01HXYZabcdef | #42 | plan-review | Scope rewrite to quickstart only? | yes | no, full rewrite | overrode |  | user wanted philosophy framing |
```

When the Codex CLI stamps a commit, include both trailers in the `-m`
arg. There's no Codex-specific reader; the directive's `check.sh`
treats the repo identically regardless of which runtime authored the
row.

### Other runtimes

Any runtime that can write a markdown row and append trailers to a
commit message is already supported. The directive enforces shape and
cross-checks — it does not care who wrote the row. A fresh runtime
needs no `runtimes/<name>.sh` sibling; this is the major structural
difference from `agent-token-accounting`.

## What gets enforced where

All paths below are rooted at the installed directive folder
`tests/governance/directives/agent-decision-accounting/`.

| Layer | What it checks |
|---|---|
| `lib/ledger.py` | Stdlib-only Python that owns the ledger: `LedgerRow` dataclass, `parse`, `find_by_decision_key`, `validate`. 11-column schema only (no legacy shapes yet — this directive is new). Catches wrong column count, duplicate `decision-key`, non-vocab `diverged` / `phase`, empty / malformed `issue`. |
| `lib/trailers.py` | Parses commit trailers and cross-checks `Decision-Key` / `Decision-Diverged` against a per-key snapshot (diverged value + cost-key). Catches: one-of-pair trailer missing, bad counter format, denominator mismatch, numerator mismatch, duplicate keys inside the same trailer, missing / ambiguous ledger rows. |
| `check.sh` (commit-msg + CI) | Two modes. Mode A (commit-msg hook): validates the pending commit's trailer-ledger relationship. Mode B (CI): walks `base..HEAD` and validates every non-merge, non-revert commit that carries a `Decision-Key` trailer. Both modes also run repo-wide `lib/ledger.py validate` for shape checks, and a soft `cost-key` cross-check against `COSTS.md` when that file is present. |

## What it doesn't try to do

- **No automated row creation.** The agent writes the row. A wrapper
  that never tags its asks produces an empty ledger — that's by design;
  this directive cannot force an agent to declare its lean, only enforce
  the shape when it does.
- **No analytics.** The directive ships the ledger, not a dashboard.
  Override rate, reframe rate, time-to-override, and cost-of-divergence
  are all joinable from `DECISIONS.md` (plus `COSTS.md` for the last
  one) — tooling is a follow-up.
- **No comment-thread capture.** Decisions made in issue / PR comments
  that never reach a commit are out of scope for v1. The ledger is
  commit-anchored; backfilling from a comment thread is a later
  feature.
- **No rejection / replacement chain.** When the human `reframed` a
  question, the replacement question (if any) goes in its own row; the
  `note` column is the v1 way to hand-link the two. A dedicated
  `replaces:` column can come later if someone actually needs the chain
  machine-readable.

# Agent Steering Accounting

Opt-in governance directive that gives the repo a durable, auditable ledger of
**human steering events** for agent-authored commits — the moments where the
operator denied a tool call, interrupted a turn, or (under an opt-in lexical
tier) typed a correction that redirected the agent.

This is the human-side counterpart to [`agent-token-accounting`](AGENT_TOKEN_ACCOUNTING.md).
That directive captures *machine* cost (token consumption, dollars). This one
captures *steering* cost (where the agent's instructions or directives drifted
from operator intent and the operator had to correct it). Both ledgers live at
repo root, both are append-only, both survive squash merges via mirrored commit
trailers, and both are layered the same way: trailers for branch-time
provenance, the Markdown table for the durable record, a stable join key in
both, and a governance directive that cross-checks the two.

## Why it's layered this way

Direct alternatives all break under squash:

- **Counting denials in commit-message bodies** — squash merges rewrite the
  body to whatever the maintainer types. The signal disappears.
- **Storing transcripts** — JSONL session files live on one contributor's
  laptop and rotate. They are not durable across the repo's lifetime.
- **Computing keys from commit SHAs** — branch SHAs disappear under squash.

What works: durable rows in `STEERING.md` keyed by `steer-key`, mirrored as
repeated `Steer-Key:` trailers on the original commit, cross-checked by
`tests/governance/directives/agent-steering-accounting/check.sh`.

## Trailer schema

Every agent-authored commit with detected steering events carries three
summary trailers + one `Steer-Key:` trailer per row:

```
Steer-Count: 3
Steer-Types: interrupt=1,tool-denial=2
Steer-Tiers: structural=3
Steer-Key: steer-<session-short>-<epoch>-1
Steer-Key: steer-<session-short>-<epoch>-2
Steer-Key: steer-<session-short>-<epoch>-3
```

Why both layers:

- **`Steer-Count` / `Steer-Types` / `Steer-Tiers`** are the headline
  reviewers skim in `git log` — same role `Token-Total` and `Cost-USD`
  play for the cost ledger. They survive squash merges and let you sort
  commits by steering volume without joining against `STEERING.md`.
  `Types` and `Tiers` are sorted `key=N,key=N` (or the literal `none`
  if zero events).
- **`Steer-Key`** is the durable join key — one repeated trailer per
  ledger row. Multiple trailers per commit by design; git trailers
  natively support repeated keys.

A commit with **zero** detected events carries **none** of these trailers —
the directive is satisfied by absence. The failure modes are: the ledger
gained rows but no trailer was stamped, a trailer points at a key with no
row, summary counts disagree with the per-event trailers, or summary
breakdowns disagree with the matched rows' `type` / `tier` columns.

## Ledger schema

`STEERING.md` is the durable record:

```
| steer-key | session | issue | type | tier | tool | proposed | user-reason | commit |
```

- `steer-key` — `steer-<session-short>-<epoch>-<idx>`. Unique within the file,
  monotonically non-decreasing in `<epoch>` (the ledger is append-only — never
  reorder).
- `session` — runtime session id (e.g. Claude Code's `sessionId`). Used to
  scope the dedup boundary so a single session that produces multiple commits
  doesn't double-record events.
- `issue` — `#N` from the commit subject's `(#N)` anchor, or empty for repos
  that don't enforce anchors.
- `type` ∈ `tool-denial` | `interrupt` | `correction`.
- `tier` ∈ `structural` | `lexical`. The default-on tier is `structural`
  (denials + interrupts). The `lexical` tier (corrections) is gated behind
  `STEERING_LEXICAL=1`.
- `tool` — for denials, the tool name the user blocked (`Bash`, `Edit`,
  `Write`, …). Empty for interrupts and corrections.
- `proposed` — for denials, a one-line summary of what the agent proposed
  (Bash command's first line, or the tool input's most informative scalar
  field). Truncated to 80 chars by the ledger sanitizer.
- `user-reason` — verbatim text the operator typed. For denials, the message
  appended via `To tell you how to proceed, the user said:\n…`. For
  corrections, the user message itself. Empty for interrupts. Truncated to
  240 chars.
- `commit` — short subject of the commit that recorded this row.

## Detection model

`lib/extract.py` walks a Claude Code JSONL transcript and emits one event per
detection. Two tiers:

### Tier 1 — structural (runtime sentinels)

- **Tool denial**: `tool_result` content starts with the canonical phrase
  `The user doesn't want to proceed with this tool use`. The corresponding
  `tool_use` is found via `tool_use_id` to recover the tool name + a short
  `proposed` summary. If the user typed a reason, the verbatim text after
  `To tell you how to proceed, the user said:\n` is captured into
  `user-reason`. Empty-reason denials are recorded with empty `user-reason`
  — they are still steering signals, just lower-information.
- **Interrupt**: a user message whose text begins with
  `[Request interrupted by user` (with or without `for tool use`). No reason
  text by construction.

Tier 1 has near-zero false positives: both signals are runtime-emitted
sentinels, not heuristics over user prose.

### Tier 2 — semantic correction

The extractor collects every user message that immediately follows an
assistant turn (and isn't itself a tool-result wrapper or an interrupt), then
classifies them in a single batched call to the active runtime's headless
CLI:

- `claude -p` (Claude Code) — primary
- `codex exec` (Codex) — primary, when the future Codex adapter ships
- regex fallback — only when neither CLI is on `$PATH` or the CLI errors out

The CLI is by definition installed in any session that wrote the transcript,
so this is a free dependency and there's no separate API key, model
deployment, or auth flow to set up.

The classifier prompt asks for a per-item JSON verdict (`{"i": N, "redirect":
true|false, "reason": "<≤80-char one-liner or null>"}`). Verdicts are cached
by SHA-256 of `(assistant_turn, user_message)` in
`$GIT_DIR/agent-steering-classify-cache.json`, so amends, retries, and
re-runs return the same answer. The cached `tier` cell records which path
actually produced the verdict — `classifier` for CLI verdicts, `lexical` for
regex-fallback verdicts.

The regex fallback (used silently when the CLI is unreachable) matches:

```
^(no|stop|wait|actually|instead|don't|hold on|back up|undo|revert|
  that's wrong|you're wrong)\b
```

(case-insensitive, on the user message). High-precision, high-FN — covers
the obvious cases until the CLI is reachable again.

There is no env-var gate inside the directive — installation is the gate.
Repos that don't want correction-tier rows simply don't install the
directive.

## Privacy

`user-reason` is committed verbatim to the repo's history. **Do not enable
this directive on a public repo without thinking through what those messages
could leak.** The directive is opt-in only — it ships in
`duaility/agent-governance` but is deliberately excluded from every preset
(`minimal`, `standard`, `strict`). The lexical tier's separate gate is the
second layer of intentional friction.

For private repos in trusted teams, the verbatim text *is* the value: it is
the audit trail that explains why the agent took the path it did. For
mixed-audience repos, consider redacting at extraction time (a future
extractor flag) rather than after the fact — once a row is committed,
removing it requires a force-push.

## Installing

The directive ships as a self-contained folder under the `agent-governance`
pack. Manual install:

```sh
cp -r <governance-kit>/extensions/packs/agent-governance/directives/agent-steering-accounting \
      tests/governance/directives/
cp    <governance-kit>/extensions/packs/agent-governance/directives/agent-steering-accounting/install-assets/STEERING.md \
      STEERING.md
chmod +x tests/governance/directives/agent-steering-accounting/check.sh \
         tests/governance/directives/agent-steering-accounting/hooks/*.sh \
         tests/governance/directives/agent-steering-accounting/runtimes/*.sh
```

Then add an `agent-steering-accounting` Directives subsection to
`CONSTITUTION.md` via the `governance directive add` verb.

Stdlib-only Python 3, no `pip install` required. The only runtime dependency
is `python3` on `$PATH`.

## How a commit flows

```
git commit -m "feat: x (#13)"
      │
      ▼
pre-commit ──► tests/governance/directives/agent-steering-accounting/hooks/pre-commit.sh
      │          1. Detect runtime (CLAUDECODE=1 → claude-code; future: codex).
      │          2. Resolve session id + transcript via runtimes/<runtime>.sh.
      │          3. Walk parent argv to recover the (#N) issue anchor + subject.
      │          4. python3 lib/extract.py <transcript> [--lexical]
      │             — emits TSV: ts, type, tier, tool, proposed, user-reason.
      │          5. Dedup: count rows already in STEERING.md for this session;
      │             skip that prefix of the extractor's output.
      │          6. Append remaining rows via lib/ledger.py append-row, one
      │             steer-key per row: steer-<session-short>-<epoch>-<idx>.
      │          7. git add STEERING.md (so rows land in this commit's tree).
      │          8. Write handoff env file at
      │             $(git rev-parse --git-path governance-pending-steering.env).
      │
      ▼
(governance tests run — check.sh sees the new rows in-tree)
      │
      ▼
prepare-commit-msg ──► sources the handoff env, stamps one Steer-Key:
                       trailer per appended row, removes the handoff file.
      │
      ▼
commit-msg ──► tests/governance/directives/agent-steering-accounting/check.sh <msg>
                  Mode A. Cross-checks:
                    - every newly-added STEERING.md row has a Steer-Key trailer
                    - every Steer-Key trailer has a matching ledger row
                    - no duplicate trailers within a single commit
```

In CI / `bash tests/governance/run.sh`, the same `check.sh` runs in Mode B,
walking `merge-base..HEAD` with the same row↔trailer invariant on each
non-merge, non-revert commit.

## Dedup boundary

The extractor returns *every* steering event in the session JSONL. The hook
records only the *new* events: the count of rows already in `STEERING.md`
for this session is the prefix to skip. Append-only ordering of the ledger
plus the chronological order of the JSONL makes this exact under normal
operation. The append-only invariant is itself enforced by `check.sh`'s
ledger validator (rows must be monotonically non-decreasing in their
embedded epoch), so a tampered ledger fails the directive before the hook
trusts the dedup count.

## Runtime support

Today only Claude Code (`CLAUDECODE=1`) is wired. The runtime adapter layer
is in place — `runtimes/<name>.sh` is the only file an additional runtime
needs to ship. Codex is the obvious next step; its session log shape needs
confirmation before a parser lands. Until then, Codex commits are silent
no-ops for this directive (no transcript discovered, no rows appended).

## Escape hatches

- `SKIP_GOVERNANCE=1 git commit ...` — local hook bypass (extractor doesn't
  run, no rows appended). CI re-enforces row/trailer cross-checks.
- `git commit --no-verify` — same effect: skips the local hooks entirely.

There is no per-tier env-var gate inside the directive. The directive's
install step is the only gate.

## Out of scope (deferred follow-ups)

- Codex transcript parser + `codex exec` classifier wiring — same schema,
  different transcript parser; the CLI hook in `_detect_cli` already picks
  up `codex` when present.
- Cross-session aggregation / dashboards.
- Inclusion in `core` pack or any default preset.
- Backfilling historical steering events from old session JSONLs.

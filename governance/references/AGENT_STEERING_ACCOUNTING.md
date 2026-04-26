# Agent Steering Accounting

Opt-in governance directive that gives the repo a durable, auditable ledger of
**human steering events** for agent-authored commits — the moments where the
operator interrupted a turn or typed a message classified as a course
correction by the active runtime's CLI (with a regex fallback when the CLI is
unreachable). Tool denials are deliberately **not** tracked: a click on
"deny" is most often "I'll do that myself" / "wrong tool", not an intent
redirect, and the substring sentinel for the canonical denial phrase produced
false positives whenever an agent read this directive's own source. The
directive's install step is the only gate; there are no internal env-var
toggles for tiers.

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

- **Counting interrupts in commit-message bodies** — squash merges rewrite the
  body to whatever the maintainer types. The signal disappears.
- **Storing transcripts** — JSONL session files live on one contributor's
  laptop and rotate. They are not durable across the repo's lifetime.
- **Computing keys from commit SHAs** — branch SHAs disappear under squash.

What works: durable rows in `STEERING.md` keyed by `steer-key`, with the row
→ commit join carried by the `commit |` column, plus a per-commit summary
trailer triple cross-checked by
`tests/governance/directives/agent-steering-accounting/check.sh`.

## Trailer schema

Every agent-authored commit (one carrying an `Agent:` trailer from
`agent-token-accounting`) stamps the always-on summary triple:

```
Steer-Count: 3
Steer-Types: correction=2,interrupt=1
Steer-Tiers: classifier=2,structural=1
```

A zero-event commit still carries the triple as the explicit zero-assertion:

```
Steer-Count: 0
Steer-Types: none
Steer-Tiers: none
```

Why summary-only, and why always-on:

- **`Steer-Count` / `Steer-Types` / `Steer-Tiers`** are the headline
  reviewers skim in `git log` — same role `Token-Total` and `Cost-USD`
  play for the cost ledger. They survive squash merges and let you sort
  commits by steering volume without joining against `STEERING.md`.
  `Types` and `Tiers` are sorted `key=N,key=N` (or the literal `none`
  on a zero-event commit). The numbers must agree with the rows the
  commit adds to `STEERING.md`: `Steer-Count` equals the row count, and
  the breakdowns tally those rows' `type` / `tier` columns.
- **Per-event `Steer-Key:` trailers were retired** in #66. The row →
  commit join uses `STEERING.md`'s `commit |` column instead — one
  `git grep` scoped to the ledger gets every event for a given commit
  subject, without the trailers having to mirror the rows. Dropping the
  per-event trailers also fixes a retry-after-failed-commit-msg bug
  where the second `git commit` invocation re-stamped zero `Steer-Key:`
  trailers because the rows the first attempt appended already counted as
  "already-recorded" events.
- **Always-on**: silence on a no-event commit was indistinguishable from
  "the directive crashed", "the directive wasn't installed", or "no
  runtime was detected". A positive `Steer-Count: 0` collapses those
  three failure modes into a single visible assertion: the directive ran,
  the transcript was readable, the count is zero.

Commits **without** an `Agent:` trailer (human commits, no recognised
runtime) are exempt — no Steer-* trailers expected. The failure modes are:
an agent commit that lacks the summary triple, the summary count
disagrees with the rows the commit adds to the ledger, the breakdowns
disagree with those rows' `type` / `tier` columns, or a newly-added row's
`commit |` cell doesn't match the pending subject (Mode A only — squash
merges may rewrite the subject after the row was stamped, so Mode B's CI
walk skips that comparison). Historical commits in the repo's log may
still carry `Steer-Key:` trailers; the new check ignores them.

## Ledger schema

`STEERING.md` is the durable record:

```
| steer-key | session | issue | type | tier | user-reason | commit |
```

- `steer-key` — `steer-<session-short>-<epoch>-<idx>`. Unique within the file,
  monotonically non-decreasing in `<epoch>` (the ledger is append-only — never
  reorder).
- `session` — runtime session id (e.g. Claude Code's `sessionId`). Used to
  scope the dedup boundary so a single session that produces multiple commits
  doesn't double-record events.
- `issue` — `#N` from the commit subject's `(#N)` anchor, or empty for repos
  that don't enforce anchors.
- `type` ∈ `interrupt` | `correction`.
- `tier` ∈ `structural` | `classifier` | `lexical`. `structural` covers
  interrupts (runtime sentinels). `classifier` covers corrections classified
  by the runtime CLI. `lexical` covers corrections the silent regex fallback
  caught when the CLI was unreachable. All three run by default — the
  directive's install step is the only gate.
- `user-reason` — for `correction` rows, the classifier's ≤80-char summary
  of the redirect intent (or the verbatim user message under the lexical
  fallback). Empty for `interrupt` rows on Claude Code today, since the
  runtime doesn't surface a typed interrupt reason. Truncated to 240 chars.
- `commit` — short subject of the commit that recorded this row.

## Detection model

`lib/extract.py` walks a Claude Code JSONL transcript and emits one event per
detection. Two tiers:

### Tier 1 — structural (runtime sentinels)

- **Interrupt**: a user message whose text begins with
  `[Request interrupted by user` (with or without `for tool use`). No reason
  text by construction.

Tier 1 has near-zero false positives: the signal is a runtime-emitted
sentinel, not a heuristic over user prose. **Tool denials were intentionally
removed**: a user clicking "deny" on a tool call is most often "I'll do that
myself" / "wrong tool", not an intent redirect, and the substring sentinel
for the canonical denial phrase produced false positives whenever an agent
read this directive's own source code or documentation (the phrase appears
in both as part of describing the directive).

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

`user-reason` is committed to the repo's history. The shape of the text varies
by tier:

- **`structural`** — empty `user-reason` on Claude Code today (the runtime
  doesn't surface a typed interrupt reason). A future runtime that captures
  one will record it verbatim.
- **`classifier`** — the runtime CLI's one-line summary of the redirect
  intent. The verbatim user message is *not* committed; only the LLM's
  ≤80-char summary lands in `user-reason`.
- **`lexical`** — verbatim user message, recorded only when the runtime CLI
  is unreachable and the regex fallback ran. This path is silent — there is
  no separate env-var gate.

**Do not install this directive on a public repo without thinking through
what those messages could leak.** The directive is opt-in only — it ships in
`duaility/agent-governance` but is deliberately excluded from every preset
(`minimal`, `standard`, `strict`). Installing the directive commits to
recording every tier listed above; there are no per-tier opt-outs at runtime.
For mixed-audience repos, the lowest-leak path is to keep the runtime CLI
reachable so the `classifier` tier (summary, not verbatim) is the path that
actually runs.

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
      │          4. python3 lib/extract.py <transcript> --cache <path>
      │             — emits TSV: ts, type, tier, user-reason.
      │             Tier-2 always runs; classifier vs lexical depends on
      │             whether the runtime CLI is on $PATH.
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
prepare-commit-msg ──► sources the handoff env, stamps the summary triple
                       (Steer-Count / Steer-Types / Steer-Tiers), removes
                       the handoff file.
      │
      ▼
commit-msg ──► tests/governance/directives/agent-steering-accounting/check.sh <msg>
                  Mode A. Cross-checks:
                    - agent commits carry the full summary triple
                    - Steer-Count equals the count of rows the commit adds
                      to STEERING.md
                    - Steer-Types / Steer-Tiers tally those rows' columns
                      and total to Steer-Count
                    - each newly-added row's `commit |` cell matches the
                      pending subject
```

In CI / `bash tests/governance/run.sh`, the same `check.sh` runs in Mode B,
walking `merge-base..HEAD` with the same summary-vs-row contract on each
non-merge, non-revert commit. The row.commit-cell == subject check is
skipped in Mode B because squash merges can rewrite the subject after the
row was stamped.

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

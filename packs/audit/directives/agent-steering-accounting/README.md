# Agent Steering Accounting

Governance directive that gives the repo a durable, auditable ledger of
**human steering events** for agent-authored commits — the moments where the
operator interrupted a turn or typed a message classified as a course
correction by the active runtime's CLI (with a regex fallback when the CLI is
unreachable). Tool denials are deliberately **not** tracked: a click on
"deny" is most often "I'll do that myself" / "wrong tool", not an intent
redirect, and the substring sentinel for the canonical denial phrase produced
false positives whenever an agent read this directive's own source. The
directive's install step is the only gate; there are no internal env-var
toggles for tiers.

This is the human-side counterpart to [`agent-token-accounting`](../agent-token-accounting/README.md).
That directive captures *machine* cost (token consumption, dollars). This one
captures *steering* cost (where the agent's instructions or directives drifted
from operator intent and the operator had to correct it). Both records home
their rows in the commit's per-issue receipt — `receipts/issue-<N>.md`, under a
`## Accounting` section (cost rows in `### Costs`, steering rows in
`### Steering`) — instead of a central ledger at repo root. Homing rows in the
receipt keeps the record conflict-free (only the PR branch that owns the issue
writes it) and bounded, and it is naturally sealed once the receipt merges
(frozen on the trunk by `doc-integrity`). The receipt is also squash-robust by
construction: the rows are files in the diff, not commit-message metadata.

> **No commit trailers (issue #293).** Earlier versions stamped an always-on
> summary triple (`Steer-Count`/`Steer-Types`/`Steer-Tiers`) onto every commit
> and cross-checked the stamp against the rows the commit staged. The triple was
> a `git log`-skimmable copy of facts already in the receipt rows, and its only
> enforced contract — "stamped count == staged rows" — is vacuous once the stamp
> is gone. Steering completeness was always best-effort regardless (the
> extractor is non-blocking — a transient classifier failure logs and exits 0
> rather than blocking a commit), so the directive never guaranteed "every
> transcript event is recorded", only that whatever rows exist are valid. That
> invariant is exactly what `check.sh`'s `validate-dir` enforces, and it now
> stands on its own.

## Why it's layered this way

Direct alternatives all break under squash:

- **Counting interrupts in commit-message bodies** — squash merges rewrite the
  body to whatever the maintainer types. The signal disappears.
- **Storing transcripts** — JSONL session files live on one contributor's
  laptop and rotate. They are not durable across the repo's lifetime.
- **Computing keys from commit SHAs** — branch SHAs disappear under squash.

What works: durable rows in the commit's per-issue receipt
`receipts/issue-<N>.md` (under `## Accounting` → `### Steering`) keyed by
`steer-key`, validated for shape by
`.governance/packs/<owner>/<repo>/directives/agent-steering-accounting/check.sh`.
The previously-central `STEERING.md` is now sealed legacy history (a
`doc-integrity` frozen-file) — it stops receiving writes; no migration.

Every accounted steering event must resolve to an issue (the `(#N)` anchor on
the commit subject). The hook refuses to write events it can't attribute to an
issue — there are no issue-less rows.

## Row schema

Steering rows live in the commit's per-issue receipt — `receipts/issue-<N>.md`,
under the `## Accounting` → `### Steering` sub-table. v2 is 9 columns (issue
#229 added `ordinal` + `timestamp`):

```
| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
```

- `steer-key` — `steer-<session-short>-<epoch>-<idx>`. Globally unique across
  all `receipts/*.md`, monotonically non-decreasing in `<epoch>`. Treat it as
  an opaque join token — do not parse it.
- `session` — runtime session id (e.g. Claude Code's `sessionId`).
- `issue` — `#N` from the commit subject's `(#N)` anchor. Required: every
  accounted event must resolve to an issue (it's the row's home receipt), and
  the hook refuses to write events it can't attribute — there are no issue-less
  rows.
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
- `ordinal` (v2, issue #229) — the event's 1-based position in the session's
  deterministic event stream. With `session` it forms the event's identity:
  dedup appends a `(session, ordinal)` pair once, ever (an identity test, not
  the old positional "skip the first N"), per-session ordinals are strictly
  increasing, and the same `(session, ordinal)` in two receipts — a cross-branch
  re-append — is flagged.
- `timestamp` (v2) — the ISO timestamp the extractor already emits for the
  event; recorded rather than dropped on write.

Legacy v1 rows (7 columns, no `ordinal`/`timestamp`) keep parsing and are
validated to the v1 rules; only new rows carry the v2 columns.

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
read this directive's own source code or documentation.

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
the obvious cases until the CLI is reachable again. This is the *default*
phrase list and is tunable per repo — see **Configuration** below.

There is no env-var gate inside the directive — installation is the gate.
(The config knobs below *tune* detection; they are not feature gates and
cannot turn the directive off.)

## Configuration

Two classifier knobs are tunable per repo, via the same layered-overlay model
every configurable directive uses: a pack-owned `defaults.conf` ships in the
directive folder (the live defaults AND their docs, refreshed by `governance
pack update`, never hand-edited), and the user-owned overlay
`.governance/conf/governance-kit/audit/agent-steering-accounting.conf` holds
only your deltas. `lib/conf.py` mirrors the bash `conf_list` / `conf_get`
helpers so the Python classifier and extractor read the same effective values.

- **Lexical-fallback trigger phrases** — the redirect-trigger list shown above,
  used only on the silent `lexical` path when the runtime CLI is unreachable.
  In the overlay, a bare line **adds** a phrase, `!phrase` **drops** one of the
  defaults (gitignore-style negation). Clearing the whole list disables the
  lexical fallback (it never matches) rather than matching everything.
- **`CANDIDATE_MAX_LEN`** — the maximum user-message length (chars) still
  considered a classification candidate; longer messages are clipped before the
  CLI call. Default `2000`. Set `CANDIDATE_MAX_LEN=<int>` in the overlay, or the
  env var `GOVERNANCE_CANDIDATE_MAX_LEN` (which wins). A non-integer value fails
  loudly rather than silently reverting.

Neither knob touches `check.sh`: they shape only *which events the extractor
records*, never the directive's pass/fail verdict. The ledger contract enums
(`type` ∈ `interrupt`/`correction`, `tier` ∈ `structural`/`classifier`/`lexical`)
are the accounting schema, not configuration, and stay fixed.

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
  is unreachable and the regex fallback ran. This path is silent.

The directive is mandatory (`always_install: true`) — in this kit's model every
commit is agent-authored, so steering-accounting is part of the audit chain, not
an extra. Public-repo operators handle the privacy tradeoff by layering
redaction inside the classifier hook (the verbatim text only enters the receipt
after `lib/extract.py` and `lib/ledger.py` write the row), **not** by skipping
the directive — skipping it would leave a documented hole in the audit chain.
For mixed-audience repos, the lowest-leak path is to keep the runtime CLI
reachable so the `classifier` tier (summary, not verbatim) is the path that runs.
**Think through what those messages could leak before working in a public repo.**

## Installing

The directive ships as a self-contained folder under the `governance-kit/audit`
pack. Manual install:

```sh
cp -r <governance-kit>/packs/audit/directives/agent-steering-accounting \
      .governance/packs/governance-kit/audit/directives/
chmod +x .governance/packs/governance-kit/audit/directives/agent-steering-accounting/check.sh \
         .governance/packs/governance-kit/audit/directives/agent-steering-accounting/hooks/*.sh \
         .governance/packs/governance-kit/audit/directives/agent-steering-accounting/runtimes/*.sh
```

There is no ledger file to seed at install — rows live in per-issue receipts,
and the pre-commit hook creates the receipt (an accounting-only stub with just
a `## Accounting` section) on demand the first time a commit for that issue
needs one. The directive ships no `STEERING.md` install-asset and no
`prepare-commit-msg` hook (issue #293 retired the summary trailers).

Then add an `agent-steering-accounting` Directives subsection to
`CONSTITUTION.md` via the `governance directive add` verb.

Stdlib-only Python 3, no `pip install` required. The only runtime dependency
is `python3` on `$PATH`. The shared markdown section/table plumbing lives in
`lib/receipt_io.py`, and `lib/report.py` (in the token directive) aggregates the
Accounting sections across `receipts/*.md`.

## How a commit flows

```
git commit -m "feat: x (#13)"
      │
      ▼
pre-commit ──► .governance/packs/<owner>/<repo>/directives/agent-steering-accounting/hooks/pre-commit.sh
      │          1. Detect runtime (CLAUDECODE=1 → claude-code; future: codex).
      │          2. Resolve session id + transcript via runtimes/<runtime>.sh.
      │          3. Walk parent argv to recover the (#N) issue anchor + subject
      │             (/proc/$PPID/cmdline on Linux, sysctl(KERN_PROCARGS2) via
      │             lib/argv.py on macOS — `ps -o args=` mangles UTF-8 under
      │             LC_ALL=C, see issue #140).
      │          4. python3 lib/extract.py <transcript> --cache <path>
      │             — emits TSV: ordinal, ts, type, tier, user-reason.
      │             Tier-2 always runs; classifier vs lexical depends on
      │             whether the runtime CLI is on $PATH. A transient extractor
      │             failure logs and exits 0 (non-blocking — best-effort).
      │          5. Identity dedup (issue #229): read the (session) ordinals
      │             already recorded across receipts/*.md (lib/ledger.py
      │             existing-ordinals); keep only events whose ordinal isn't
      │             already present — an identity test, not "skip the first N".
      │          6. Resolve the issue from the (#N) anchor; refuse to write
      │             events that can't be attributed to an issue.
      │          7. Append the new rows via lib/ledger.py append-row to
      │             receipts/issue-<N>.md under `## Accounting` → `### Steering`
      │             (creating the stub receipt if absent), one steer-key per
      │             row, each carrying its ordinal + timestamp.
      │          8. git add the receipt (so rows land in this commit's tree).
      │
      ▼
git snapshots the tree (the rows are already staged)
      │
      ▼
commit-msg ──► check.sh: lib/ledger.py validate-dir over receipts/*.md —
               per-row shape, type/tier sets, receipt-homed issue, append-only
               epoch order, per-session ordinal strict-increase, global
               steer-key uniqueness, cross-receipt (session, ordinal) identity.
      │
      ▼
commit lands
```

In CI / `bash .governance/run.sh`, the same `check.sh` runs `validate-dir` over
the repo's receipts — the only contract the directive enforces now that the
summary trailers are retired.

## Dedup boundary

The extractor returns *every* steering event in the session JSONL, each tagged
with a stable per-session `ordinal` (its 1-based position in the deterministic
event stream). The hook records only events whose `(session, ordinal)` isn't
already present across `receipts/*.md` — an identity test, not the old
positional "skip the first N recorded rows" (issue #229). The positional scheme
re-appended and misattributed events across branches in the same session; the
ordinal makes dedup branch-independent and makes a cross-branch duplicate
*detectable* — the same `(session, ordinal)` landing in two receipts is flagged
by `check.sh`'s `validate-dir`, alongside the append-only epoch-ordering and
per-session ordinal-monotonicity checks.

## Runtime support

Today only Claude Code (`CLAUDECODE=1`) is wired. The runtime adapter layer
is in place — `runtimes/<name>.sh` is the only file an additional runtime
needs to ship. Codex is the obvious next step; its session log shape needs
confirmation before a parser lands. Until then, Codex commits are silent
no-ops for this directive (no transcript discovered, no rows appended).

## Escape hatches

- `SKIP_GOVERNANCE=1 git commit ...` — local hook bypass (extractor doesn't
  run, no rows appended). CI re-runs the ledger-shape check.
- `git commit --no-verify` — same effect: skips the local hooks entirely.
- `governance: allow-agent-steering-accounting <reason>` — a body waiver
  (reason required) for an irreparable `(session, ordinal)` duplicate already
  merged to the trunk. Audit trail: `git log --grep='allow-agent-steering-accounting'`.

No bootstrap waiver lives in `check.sh`: it only validates receipt-ledger shape,
which an install commit with no steering rows trivially passes.

## Out of scope (deferred follow-ups)

- Codex transcript parser + `codex exec` classifier wiring — same schema,
  different transcript parser; the CLI hook in `_detect_cli` already picks
  up `codex` when present.
- Cross-session aggregation / dashboards.
- Backfilling historical steering events from old session JSONLs.

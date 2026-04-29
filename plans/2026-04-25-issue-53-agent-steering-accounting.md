# Plan: agent-steering-accounting directive (issue-53)

Tracks [governance-kit#53](https://github.com/Duaility/governance-kit/issues/53).

## Goal

Add an opt-in directive `agent-steering-accounting` to the `duaility/agent-governance` pack
that records human-steering events (tool denials, interrupts, opt-in lexical corrections)
detected from the active session JSONL into an append-only `STEERING.md`, mirrored as
repeated `Steer-Key:` trailers on the commit. Parallel to `agent-token-accounting` —
captures *human* steering cost where the existing directive captures *machine* token cost.

## Design decisions

1. **Hook split mirrors agent-token-accounting**: `pre-commit` extracts events and appends
   rows + `git add`s the ledger; `prepare-commit-msg` stamps trailers from a handoff env
   file. By the time `prepare-commit-msg` runs the tree is snapshotted, so `git add` from
   there would land in the *next* commit.
2. **Per-event row identity, repeated trailer per row**: `steer-<session-short>-<epoch>-<idx>`
   per row; one `Steer-Key:` trailer per row (git natively supports repeated keys).
   `check.sh` validates row↔trailer symmetry.
3. **Branch boundary via session row count**: extractor returns *every* event in the
   transcript; hook skips the first N where N = count of rows already in `STEERING.md`
   for this session. Append-only ordering + chronological JSONL makes this exact.
4. **Two-tier detection**: structural (denials + interrupts) on by default; lexical
   corrections gated behind `STEERING_LEXICAL=1`. Lexical regex from issue #53.
5. **Privacy is the load-bearing tradeoff**: `user-reason` is committed verbatim. Directive
   is opt-in only — not in any preset. Documented prominently in constitution + reference doc.
6. **Codex transcript support deferred**: only `runtimes/claude-code.sh` ships in v1; the
   adapter layer is in place so Codex is a single new file when its session-log shape is
   confirmed.

## Scope

- New directive folder under `extensions/packs/agent-governance/directives/agent-steering-accounting/`
  with `directive.yaml`, `constitution.md`, `check.sh`, `lib/{extract,ledger,trailers}.py`,
  `hooks/{pre-commit,prepare-commit-msg}.sh`, `runtimes/claude-code.sh`,
  `install-assets/STEERING.md`, `evals/test.sh`.
- Reference doc at `governance/references/AGENT_STEERING_ACCOUNTING.md`.
- Catalog entry in `governance/references/DIRECTIVES_CATALOG.md`.
- Eval coverage: 5 cases (clean pass, no-events pass, missing-trailer fail,
  missing-row fail, reordered-ledger fail).

## Out of scope

- LLM-classifier tier (deferred).
- Codex `runtimes/codex.sh` (follow-up; same schema, different parser).
- Cross-session aggregation / dashboards.
- Inclusion in `core` pack or any default preset.
- Backfilling historical steering events.

## Acceptance

- [x] Directive folder exists with all required files (`directive.yaml`, `constitution.md`,
      `check.sh`, `lib/`, `hooks/`, `runtimes/`, `install-assets/`, `evals/`).
- [x] Extractor detects tool-denials with verbatim user reason from Claude Code JSONL
      (smoke-tested against this kit's session corpus).
- [x] Extractor detects interrupts (`[Request interrupted by user`) and lexical
      corrections behind `STEERING_LEXICAL=1`.
- [x] `pre-commit` appends one row per detected event and stamps a single `Steer-Key:`
      trailer per row via the handoff env file.
- [x] `STEERING.md` install asset exists at the directive's `install-assets/` with the
      9-column header + append-only banner.
- [x] `check.sh` fails on (a) row added without trailer, (b) trailer without row,
      (c) reordered ledger; passes on (d) clean state and (e) zero events.
- [x] Evals cover all five cases — `bash scripts/test-packs.sh` is green.
- [x] Directive is opt-in via the `duaility/agent-governance` pack only — not added
      to `minimal` / `standard` / `strict` presets.
- [x] `DIRECTIVES_CATALOG.md` documents the directive with privacy + runtime-coupling
      caveats.

## Validation

- `bash scripts/test-packs.sh` — green (5 new eval assertions).
- `bash .governance/run.sh` — green on this repo (directive doesn't break
  existing flow; the kit doesn't enable it on itself).
- Manual smoke test in a scratch repo: install the directive, deny a tool call mid-session
  with a typed reason, `git commit`, verify `STEERING.md` got a row with the verbatim
  reason and the commit has a matching `Steer-Key:` trailer.
- CI workflow `governance.yml` continues to pass.

## Update — review-driven fixes

- **P1** — stale `STEERING_LEXICAL=1` references in `constitution.md` and
  `AGENT_STEERING_ACCOUNTING.md` removed; privacy note now describes the
  actual per-tier text shape (structural verbatim, classifier summary,
  lexical verbatim) under the install-only gate.
- **P2** — `_classify_with_cli` now requires complete batch coverage from
  the runtime CLI before any verdicts are accepted. Partial coverage falls
  back to regex for the entire batch instead of caching silent
  `redirect: False` for un-ruled candidates.

## Update — follow-on commits

- **Summary trailers**: per-commit `Steer-Count`, `Steer-Types`, `Steer-Tiers` parallel to
  `Token-Total` / `Cost-USD` on the cost ledger. Reviewers can skim `git log` for steering
  volume without joining against `STEERING.md`. `check.sh` enforces summary↔per-event↔row
  agreement.
- **Tier-2 classifier**: tier-2 (corrections) now shells out to the active runtime's
  headless CLI (`claude -p`, future `codex exec`) by default, with the regex as a silent
  fallback when the CLI is unreachable. Removed the `STEERING_LEXICAL=1` gate — the
  directive's install step is the only gate, no internal env-var toggles. Verdicts are
  cached by message-pair hash so re-runs are deterministic. New `tier: classifier` label
  alongside `structural` and `lexical`. Classifier code split into `lib/classifier.py`.

## Update — dogfood install + corrections surfaced through dogfooding

Installed the directive into `governance-kit` itself, plus three corrections the
dogfood install made visible:

- **bash 3.2 compat in `hooks/pre-commit.sh`.** Original used `declare -A`
  (associative arrays, bash 4+) and `local -n` (namerefs, bash 4.3+). macOS
  ships bash 3.2 at `/bin/bash`, which is what `#!/usr/bin/env bash` resolves
  to on a default install — so the hook crashed mid-flight on every Mac
  developer. Replaced with newline-separated accumulators folded by
  `sort | uniq -c` at format time. The hook now runs end-to-end on stock
  macOS bash without dependency churn.

- **Always-on summary trailers.** Under the original contract, a zero-event
  commit carried no Steer-* trailers at all — making "directive ran and saw
  nothing" indistinguishable from "directive crashed", "directive wasn't
  installed at this commit", or "no runtime detected". Now every
  agent-authored commit (one carrying an `Agent:` trailer from
  `agent-token-accounting`) stamps the summary triple unconditionally; zero
  events emits `Steer-Count: 0` / `Steer-Types: none` / `Steer-Tiers: none`.
  Per-event `Steer-Key:` trailers are still only emitted when events exist.
  `trailers.py` validates always-on for any commit with `Agent:` and adds a
  per-breakdown total cross-check (`sum(types) == Steer-Count`) so a stale
  breakdown can't ride alongside a `Steer-Count: 0`.

- **Self-bootstrapping exemption in `check.sh` Mode B.** Mode B walks
  `base..HEAD`, so the install commit itself was about to be held to a
  contract that wasn't in the tree before it. New rule: a commit is checked
  only if its first parent already carried this directive's `check.sh`.
  Subsequent commits that *modify* the directive inherit the parent's
  enforcement contract; the install commit (whose parent didn't have it) is
  exempt.

- **Fixed strict-adjacency bug in tier-2 candidate collection.** The
  extractor required `last_assistant_idx == idx - 1` — i.e. a user message
  had to land on the JSONL line *literally adjacent* to an assistant message
  to become a tier-2 candidate. Real Claude Code transcripts interleave
  `tool_use` (assistant role) and `tool_result` (user role) entries between
  an assistant text turn and the next user redirect, so a real user message
  always lands many lines after `last_assistant_idx`. The result: the
  adjacency check rejected **every real candidate in every real session**.
  Confirmed empirically against this PR's own transcript — 7 real user
  redirects, 0 candidates collected, classifier never invoked, cache file
  never written, every commit's `Steer-Count` stuck at 0 even when the
  user clearly redirected the agent. Replaced with a "most-recent
  assistant turn" pairing: any non-tool-result user message that follows
  at least one assistant turn becomes a candidate, with the most recent
  assistant text/tool_use providing the classifier's context. Verified:
  re-running the fixed extractor against this PR's transcript surfaces 4
  classifier-confirmed redirects including the *"get rid of tool denials
  entirely"* message.

- **Removed tool-denial detection entirely.** Dogfooding the directive
  surfaced that tool denials aren't a real steering signal: a click on
  "deny" is most often "I'll do that myself" / "wrong tool", not an
  intent redirect. Worse, the original substring sentinel (`if DENIAL_PHRASE
  not in payload`) false-matched any tool result containing the canonical
  phrase — including when an agent read this directive's own
  `extract.py` source, the `AGENT_STEERING_ACCOUNTING.md` reference doc,
  or any STEERING.md content quoting prior denial rows. The first dogfood
  amend recorded three "denial" rows that were all false positives of
  exactly this kind (an agent reading the directive's own files into its
  context). Cut the entire signal: the `type` enum drops from
  `tool-denial`/`interrupt`/`correction` to `interrupt`/`correction`, and
  the schema drops the now-always-empty `tool` and `proposed` columns
  (9 cols → 7). `lib/extract.py` loses the entire `tool_uses` index,
  `_summary_for_tool`, `DENIAL_PHRASE`, `REASON_MARKER`, and
  `_parse_reason`. `lib/ledger.py` updates `VALID_TYPES`, `LedgerRow`,
  `parse`, `validate`, and the `append-row` CLI signature.
  `hooks/pre-commit.sh` drops the `tool` / `proposed` TSV columns and
  the corresponding `append-row` args. Eval coverage extended to 11
  cases (added `retired-tool-denial-type` to confirm the validator now
  rejects rows with the retired type).

Side effects: copied the directive folder into `.governance/local/directives/`,
seeded `STEERING.md` from `install-assets/`, appended the `### agent-steering-accounting`
section to `CONSTITUTION.md`, registered the directive under the
`duaility/agent-governance` block in `.governance/installed-packs.yaml`,
and added an Evolution Log entry. Hook dispatchers are dynamic so no regen
was needed. Eval coverage extended from 8 cases to 10 (added
`human-commit-exempt` and `zero-mismatch`); all 10 pack evals + 14 governance
directives pass locally on bash 3.2.57.

## Open follow-ups

- Codex transcript adapter (`runtimes/codex.sh`) once the session-log shape is confirmed.
- Optional redaction flag on the extractor for mixed-audience repos that want the ledger
  but not verbatim text in `user-reason`.
- Cross-session dashboard / aggregation tooling (separate concern).

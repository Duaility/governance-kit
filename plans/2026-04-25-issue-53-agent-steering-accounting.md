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
- `bash tests/governance/run.sh` — green on this repo (directive doesn't break
  existing flow; the kit doesn't enable it on itself).
- Manual smoke test in a scratch repo: install the directive, deny a tool call mid-session
  with a typed reason, `git commit`, verify `STEERING.md` got a row with the verbatim
  reason and the commit has a matching `Steer-Key:` trailer.
- CI workflow `governance.yml` continues to pass.

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

## Open follow-ups

- Codex transcript adapter (`runtimes/codex.sh`) once the session-log shape is confirmed.
- Optional redaction flag on the extractor for mixed-audience repos that want the ledger
  but not verbatim text in `user-reason`.
- Cross-session dashboard / aggregation tooling (separate concern).

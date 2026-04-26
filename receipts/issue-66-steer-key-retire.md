# Receipt: drop per-event Steer-Key trailers + fix retry-after-failed-commit-msg

Issue: [#66](https://github.com/Duaility/governance-kit/issues/66)

## What changed

The `agent-steering-accounting` directive switches from a row ↔ trailer
bidirectional cross-check to a **summary-only** contract.

Before, every detected steering event was mirrored as a repeated `Steer-Key:`
trailer on the commit message, and `check.sh` enforced full symmetry: every
newly-added `STEERING.md` row had a matching trailer, every trailer had a
matching row, and the summary triple (`Steer-Count` / `Steer-Types` /
`Steer-Tiers`) had to agree with both sides.

After, the commit message carries only the summary triple. The directive
checks that:

1. Every agent-authored commit (one carrying an `Agent:` trailer) stamps
   the full summary triple, even at `Steer-Count: 0` — same always-on
   contract as before.
2. `Steer-Count` equals the number of rows the commit adds to
   `STEERING.md`.
3. `Steer-Types` and `Steer-Tiers` tally those rows' `type` and `tier`
   columns and total to `Steer-Count`.
4. In Mode A (commit-msg), each newly-added row's `commit |` cell matches
   the pending subject. The check is tolerant of ledger.py's 80-char
   truncation (`…` suffix) and the pre-commit argv-walker's known greedy
   `(.+)` regex — accepts either `subject.startswith(cell)` or vice versa.
5. Mode B (CI walk) skips the row.commit-cell check because squash merges
   can rewrite the subject after the row was stamped.

The row → commit join now flows through `STEERING.md`'s `commit |` column
instead of through repeated `Steer-Key:` trailers. `git grep '<commit-subject>'
STEERING.md` enumerates every event for a given commit — one shorter hop than
walking trailers via `git log --format=%B`.

Falls out of the change: the **retry-after-failed-commit-msg bug** the issue
opens with. When a `commit-msg` rejection (e.g. an over-length subject) bounces
a commit, the second `git commit` invocation re-runs pre-commit. Under the old
contract, the events the first attempt extracted now counted as "existing rows"
in the dedup check, so `NEW_EVENTS_COUNT` collapsed to 0, the handoff stamped
zero `Steer-Key:` trailers, and `check.sh` failed the retry with "STEERING.md
adds row 'steer-…' but no matching `Steer-Key:` trailer". The user had to
manually re-stamp the trailer set + summary triple to get past the second
commit-msg run. Under the new contract, the rows the first attempt appended
are still **staged** in `STEERING.md` on retry; the new pre-commit hook
re-derives `Steer-Count` / `Steer-Types` / `Steer-Tiers` from the staged diff
(rather than from the events newly appended in *this* invocation), so the
retry's commit-msg sees a consistent count and breakdown without operator
intervention.

Edits land at both layers per the pack-and-dogfood dual-edit rule:

- **Pack source** (`extensions/packs/agent-governance/directives/agent-steering-accounting/`):
  - `lib/trailers.py` rewritten — `extract_steer_keys`, `find_by_steer_key`
    import, `_STEER_KEY_TRAILER_RE`, and the bidirectional cross-check are
    gone. New `validate(...)` takes the steer-keys parsed from the diff
    plus an optional `subject` and returns violation strings.
  - `check.sh` rewritten — Mode A passes the pending subject; Mode B passes
    `subject=""`. Single CLI shape: `validate <label> <ledger>
    [--subject SUBJ] <msg|-> [added-key...]`.
  - `hooks/prepare-commit-msg.sh` no longer emits `Steer-Key:` lines; only
    the summary triple. Idempotency guard switched from `Steer-Count|Steer-Key`
    to `Steer-Count` alone.
  - `hooks/pre-commit.sh` drops `AGENT_STEERING_KEYS` from the handoff and
    derives `STAGED_COUNT` / `TYPES_RAW` / `TIERS_RAW` from
    `git diff --cached -- STEERING.md` (the staged-diff path that fixes the
    retry case). The append loop no longer tracks `KEYS_LIST`.
  - `constitution.md` rewritten to describe the summary-only contract.
  - `directive.yaml` summary line updated.
  - `install-assets/STEERING.md` header updated to reference the `commit |`
    join column instead of `Steer-Key:` trailers.
  - `lib/ledger.py` docstring updated likewise. The unused
    `find-by-steer-key` / `existing-keys` CLI subcommands were left in
    place — they're harmless utilities, and removing them isn't load-bearing
    for #66.
  - `evals/test.sh` rewritten: 10 cases (was 11). `missing-trailer` and
    `missing-row` are retired; `bad-count` now asserts `Steer-Count` vs row
    count; new `retry-after-failed-commit-msg` fixture pre-stages a
    `STEERING.md` row and verifies the summary-only contract validates
    without re-stamping. `pass-clean` carries the summary triple only.
- **Dogfood install** (`tests/governance/directives/agent-steering-accounting/`):
  byte-identical to pack except for `evals/` and `install-assets/`. Synced
  via direct file copy after the pack edits landed.
- `CONSTITUTION.md`: `### agent-steering-accounting` Directive / Rationale /
  Exceptions blocks rewritten; Evolution Log entry appended (2026-04-26,
  closes #66).
- `governance/references/AGENT_STEERING_ACCOUNTING.md`: trailer-schema
  section rewritten; flow diagram's prepare-commit-msg + commit-msg notes
  updated. The "Steer-Key is the durable join key" bullet replaced with
  a "per-event trailers were retired in #66" bullet pointing at the
  `commit |` column.
- `governance/references/DIRECTIVES_CATALOG.md`: directive row rewritten
  to describe the summary-only contract.
- `README.md`: human-steering bullet under **Visibility** rephrased to
  drop the `Steer-Key:` per-event-trailer reference.

## Out of scope

- **Rewriting historical commits' trailers.** Existing commits in this
  repo's log carry `Steer-Key:` trailers from the old contract. The new
  validator ignores them — they're treated like any other foreign trailer.
  No `git filter-branch`, no rebase, no rewrite.
- **Renaming the directive or restructuring `STEERING.md` columns.** The
  7-column schema (`steer-key | session | issue | type | tier | user-reason
  | commit`) is unchanged. `steer-key` stays as the unique row id.
- **The two-tier extraction model** (`structural` / `classifier` /
  `lexical`) is untouched. Same extractor, same classifier prompt, same
  cache.
- **Token-accounting trailers.** Separate directive; not edited.
- **Retiring `lib/ledger.py`'s `find-by-steer-key` / `existing-keys`
  CLI subcommands.** They're unused after this change but harmless;
  removing them would be a refactor beyond the issue's scope.
- **Tightening the row.commit-cell check** in Mode B. Squash merges can
  rewrite the subject after the row was stamped, so Mode B passes
  `subject=""` to skip the check. Fixing this would require either
  recording the squash-rewritten subject back onto the row or matching
  on a subject prefix — both bigger changes than #66 warrants.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Per-event `Steer-Key:` trailers are gone from the directive.**
   Search `extensions/packs/agent-governance/directives/agent-steering-accounting/`
   and `tests/governance/directives/agent-steering-accounting/` for
   `Steer-Key`. Surviving hits are documentation-only (history-of-the-rename
   prose in `constitution.md`, `check.sh`, `prepare-commit-msg.sh`,
   `lib/trailers.py`'s docstring, and the eval's retry-bug comment) — none
   of them stamp or extract trailers.
2. **Summary-only contract enforced.** `lib/trailers.py validate` no longer
   imports or calls `find_by_steer_key`; its `validate(...)` signature is
   `(msg, label, ledger_path, added_keys, *, subject)`. `check.sh` builds
   `added_keys` from the STEERING.md diff and passes it through.
3. **Retry case passes.** `bash scripts/test-packs.sh` shows
   `agent-steering-accounting retry-after-failed-commit-msg — pass case`
   among 10 eval cases (8 pass, 5 fail per intent). All 14 eval files green.
4. **Dogfood green.** `bash tests/governance/run.sh` exits 0 with all 14
   directives passing; the `agent-steering-accounting` Mode B walk over
   `merge-base..HEAD` accepts every historical commit (which still carries
   `Steer-Key:` trailers) under the new summary-only contract because the
   summary triple already agreed with the rows by construction.
5. **Pack and dogfood directories are in sync** outside `evals/` and
   `install-assets/`. Run
   `diff -r extensions/packs/agent-governance/directives/agent-steering-accounting/ tests/governance/directives/agent-steering-accounting/`
   — only the two known differences appear.
6. **Constitution captures the change.** `CONSTITUTION.md` line 187
   carries the 2026-04-26 Evolution Log entry referencing #66; the
   `### agent-steering-accounting` directive block (lines 139–148)
   describes the summary-only contract with no per-event trailer language.
7. **Hook + handoff shape updated.** `hooks/pre-commit.sh` no longer
   writes `AGENT_STEERING_KEYS=` to the handoff env; the diagnostic
   `agent-steering: runtime=… session=… new=N staged=M total=T` line
   replaces the old `new=N total=T` form. `hooks/prepare-commit-msg.sh`
   no longer references `AGENT_STEERING_KEYS`.
8. **This commit itself satisfies `commit-issue-receipt-match` and
   `agent-steering-accounting`.** The commit's `(#66)` anchor matches the
   `issue-66` token on this very file; the new pre-commit hook stamps the
   summary triple from the staged STEERING.md diff (including any rows
   appended for this session), and a downstream commit-msg failure now
   self-heals on retry without manual trailer stamping.

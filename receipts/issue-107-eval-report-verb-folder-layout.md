# issue-107 — rewrite `eval-report.sh` for verb-folder layout

Closes [#107](https://github.com/Duaility/governance-kit/issues/107).

## Checklist

- [x] Rewrite `scripts/eval-report.sh` to walk `governance/evals/<verb>/`
- [x] Strip stale `evals/` prefix from every `files` entry across the five `evals.json`
- [x] Add `fixture_empty_by_design` opt-in flag for intentionally-empty fixtures
- [x] Verify report exits 0 with all five verbs ready

## What changed

- **Rewrite `scripts/eval-report.sh` to walk `governance/evals/<verb>/`.** The old script hardcoded `SKILLS=(governance-bootstrap governance-amend)` — two skills that haven't existed in this repo since the unified-skill collapse. It exited non-zero with both rows marked `missing`. The rewrite drops the hardcoded list, auto-discovers verbs by globbing `governance/evals/*/evals.json`, and emits one row per verb against a single `governance` skill. Header reads "Governance skill evals report" and the markdown table is keyed by verb (not skill). JSON output renamed `skills` → `verbs` for the same reason. A "total" row is added so the per-verb counts roll up to a single number (29 cases / 203 assertions today).
- **Strip stale `evals/` prefix from every `files` entry across the five `evals.json`.** The path convention `"evals/files/<fixture>/"` was a leftover from the pre-collapse layout where each skill had its own top-level dir (e.g. `governance-bootstrap/evals/files/foo/`). After the collapse, the fixture lives at `governance/evals/<verb>/files/<fixture>/`, so the leading `evals/` segment resolves to a directory that doesn't exist. Stripped `"evals/files/` → `"files/` across all 29 fixture references in `governance/evals/{init,uninstall,reset,pack,directive}/evals.json`. Path is now relative to the verb's `evals.json` directory, which matches what the rewritten script joins on.
- **Add `fixture_empty_by_design` opt-in flag for intentionally-empty fixtures.** `governance/evals/uninstall/files/clean-repo/` ships with only a README on purpose — the eval verifies `governance uninstall` is a no-op on a repo with zero kit footprint, so an empty tree IS the test. The naïve "directory contains only README.md → placeholder" rule false-positived on it. Added an opt-in `"fixture_empty_by_design": true` field at the eval-case level (set on `uninstall` case 2) and taught the script to exempt those cases from the placeholder check. Other cases still fail loudly if their fixtures haven't been seeded.
- **Verify report exits 0 with all five verbs ready.** `bash scripts/eval-report.sh` now emits a clean report: directive (7 / 50), init (5 / 36), pack (8 / 58), reset (5 / 33), uninstall (4 / 26) — all `ready`, zero missing, zero placeholder, total 29 / 203, exit 0. `bash .governance/run.sh` continues to pass 14/14 directives.

## Out of scope

- **Executing the evals.** Evals are LLM-graded behavioral checks; running them means spinning up a Claude Code session per case against a seeded fixture. `eval-report.sh` only reports *readiness*, not pass/fail. An execution harness is a separate piece of work.
- **Schema / validation for `evals.json`.** No formal schema lives in-tree today. The rewrite only loosens the placeholder rule with one new optional field; codifying the full shape can wait until there are more consumers.
- **Updating the historical `plans/` docs that reference the old `SKILLS=` list.** Those plans describe past PRs and are accurate for the state at the time. Rewriting them would be revisionist; the live source of truth is the script itself.

## Verification

- `bash scripts/eval-report.sh` → exits 0 with all five verbs (`directive`, `init`, `pack`, `reset`, `uninstall`) reporting `ready`, totals 29 cases / 203 assertions, no missing or placeholder fixtures.
- `for f in governance/evals/*/evals.json; do jq -e . "$f"; done` → all five files parse as valid JSON after the prefix strip and the `fixture_empty_by_design` insertion.
- `bash .governance/run.sh` → 14/14 dogfood directives green; the script rewrite + JSON edits don't break any constitutional check.
- Spot-checked the path resolution: `governance/evals/uninstall/files/clean-repo/` matches the (now-stripped) `"files/clean-repo/"` reference, and the empty-by-design exemption lets that fixture pass without seeding it.

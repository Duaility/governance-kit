<!-- governance: allow-plan-per-issue predates-rule -->

# Author evals for all three skills

## Goal

Bring eval coverage to parity across the three skills so `scripts/eval-report.sh` reports ready for each. Before this change: `governance-bootstrap` and `governance-amend` had `evals.json` specs but no seeded fixture directories (only placeholder READMEs), and `governance-gardener` had no eval spec at all.

## Steps

1. **Author `governance-gardener/evals/evals.json`** — four cases mirroring the shape of the other two skills' specs (prompt, expected_output, assertions, fixture path). Cases cover: (1) happy-path health report with AskUserQuestion defaulting to "nothing", (2) dirty-tree refusal, (3) ungoverned-repo exit with bootstrap recommendation, (4) user opts into bump-stamps follow-up.
2. **Seed `governance-bootstrap/evals/files/`** with three fixtures: `empty-polyglot-repo/` (package.json + pyproject.toml + tiny src), `already-bootstrapped-repo/` (pre-existing governance with `# CUSTOMIZED` markers so graders detect overwrites), `go-service-repo/` (go.mod + main.go).
3. **Seed `governance-amend/evals/files/`** with three fixtures: `seeded-repo/` (baseline bootstrapped), `repo-with-file-size-rule/` (adds `file-size-limit.sh` at 500 lines), `repo-with-console-log-rule/` (adds `no-console-log.sh` plus `docs/LOGGING.md` referencing the rule by name so the skill must surface a dangling reference on removal).
4. **Seed `governance-gardener/evals/files/`** with four fixtures: `governed-repo-with-drift/` (seeded A1/A3/C2/C5 signals), `dirty-tree-repo/` (bootstrapped + instructions to create an uncommitted file after seed), `ungoverned-repo/` (bare repo), `governed-repo-bump-eligible/` (stale stamp with unchanged watched paths).
5. **Verify** — run `bash scripts/eval-report.sh` and expect all three skills to flip from `fixtures-incomplete` / `missing` to `ready` with exit 0. Run `bash tests/governance/run.sh` to confirm the repo's governance suite still passes.

## Non-goals

- Executing the evals. They are LLM-graded behavioral checks; executing them requires spinning up a Claude Code session per case against the seeded fixture, which a human runs. `scripts/eval-report.sh` only reports *readiness*, not pass/fail.
- Reorganizing the three skills under a top-level `skills/` directory. The user deferred that suggestion to a later change so this PR stays focused.

## Design notes

- Fixtures are intentionally minimal: just enough files to exercise the scenario, not production-sized. Each fixture's README tells the grader how to seed (`git init && git add -A && git commit -m seed`) and any case-specific post-seed step (e.g., dirty-tree requires appending to `UNCOMMITTED.md` after the seed commit).
- The `already-bootstrapped-repo/` fixture embeds visible `# CUSTOMIZED` comment markers in its `lib.sh` / `run.sh` / `rules/no-secrets.sh` so the grader can assert the bootstrap skill did not overwrite hand-edited files.
- Gardener fixture `governed-repo-with-drift/` seeds multiple axes at once (A1 aspirational rule, A3 doc drift with an annotation, C2 test-without-rule orphan, C5 hedge language in the `no-secrets` invariant). The health report should surface at least one per axis.
- `governed-repo-bump-eligible/` carries a `last-verified: 2024-06-01` stamp that has clearly expired against a 90-day freshness window, but the watched path (`src/api.ts`) is unchanged since the stamp — so the signal is A4 (bump-only), not A3 (drift).

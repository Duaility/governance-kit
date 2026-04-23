# governed-repo-with-drift

A bootstrapped repo seeded with known drift across all three axes. Gardener eval case 1 — the skill should produce a health report surfacing these findings:

- **Alignment A1 (aspirational rule):** `CONSTITUTION.md` names `agents-md-exists` as an Invariant, but no `tests/governance/rules/agents-md-exists/check.sh` script exists.
- **Alignment A3 (doc drift):** `docs/ARCHITECTURE.md` has a `<!-- last-verified: 2024-01-01 -->` stamp; the watched path `src/server.ts` was edited after the stamp (seeded with a recent commit).
- **Consistency C2 (test without rule):** `tests/governance/rules/no-console-log/check.sh` exists on disk but is not named in any Invariants entry.
- **Consistency C5 (hedge language):** the `no-secrets` Invariant's Rule line contains "should" — Invariants should be hard rules.

**Seed steps for the grader:**
1. Copy fixture; `git init && git add -A && git commit -m "seed"`.
2. To make the A3 signal fire, amend `src/server.ts` and commit — e.g. `echo '// bump' >> src/server.ts && git commit -am "touch server"`. The `last-verified` stamp in `docs/ARCHITECTURE.md` predates this commit.

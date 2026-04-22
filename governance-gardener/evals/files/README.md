# Eval fixtures

Each subdirectory is a seed repo state for one gardener eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

- `governed-repo-with-drift/` — a bootstrapped repo with obvious Alignment/Friction/Consistency signals seeded in (aspirational rule, stale stamp with drift, dead-rule candidate). Eval case 1.
- `dirty-tree-repo/` — a bootstrapped repo plus an uncommitted file (`UNCOMMITTED.md`). Delete the file and re-seed if you need a clean variant. It backs both the follow-up-mode refusal eval and the report-only-on-dirty-tree eval; eval cases 2 and 5.
- `ungoverned-repo/` — a bare repo with just a README.md and no governance scaffolding. Eval case 3.
- `governed-repo-bump-eligible/` — a bootstrapped repo with one doc whose `last-verified` stamp has expired but whose watched paths are unchanged, making it bump-only. Eval case 4.
- `governed-repo-with-drift/` also backs the negative-routing eval where gardener should redirect a one-rule amendment request to governance-amend; eval case 6.

Fixtures are intentionally minimal — the eval checks the skill's *behavior* on well-understood seed states, not its ability to handle large repos.

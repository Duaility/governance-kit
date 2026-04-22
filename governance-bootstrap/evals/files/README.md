# Eval fixtures

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

- `empty-polyglot-repo/` — a minimal Python + TypeScript repo with no governance; eval case 1.
- `already-bootstrapped-repo/` — a repo that already has `tests/governance/` from a prior run; eval case 2. The pre-existing files should carry a visible marker (e.g., a comment `# CUSTOMIZED`) so the grader can detect overwrites.
- `go-service-repo/` — a minimal Go service with `go.mod`, `main.go`, and no governance; eval case 3.

Fixtures are intentionally small — the eval checks the skill's *behavior*, not its ability to handle large repos.

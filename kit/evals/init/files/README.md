# Eval fixtures — `governance init`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "chore: seed fixture (#0)"` inside it, and point the skill at that directory. The Conventional Commits subject with an issue anchor matters: the kit's `commit-message-format` directive will reject a non-conforming seed commit, and the grader expects `bash .governance/run.sh` to exit 0 on the post-init baseline.

- `empty-polyglot-repo/` — a minimal Python + TypeScript repo with no governance; eval cases 1 and 5. Ships the baseline files `required-docs` expects (LICENSE, SECURITY.md, ARCHITECTURE.md, a non-governance CI workflow) plus a `.gitignore` that lists `.env`, so a clean init can land the rest of the scaffold and immediately pass.
- `already-bootstrapped-repo/` — a repo that already has `.governance/` from a prior run; eval cases 2 and 4. The pre-existing files carry a visible `# CUSTOMIZED` comment so the grader can detect overwrites.
- `go-service-repo/` — a minimal Go service with `go.mod`, `main.go`, and the same baseline-docs set as `empty-polyglot-repo/`; eval case 3.

Fixtures are intentionally small — the eval checks the skill's *behavior* (preset surfacing, manifest pair shape, custom-directive policy-surface classification, augment-vs-overwrite handling), not its ability to handle large repos.

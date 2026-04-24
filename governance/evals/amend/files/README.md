# Eval fixtures

Each subdirectory is a seed repo state for one eval case. Before running, copy the fixture, `git init && git add -A && git commit -m "seed"`, and point the skill at that directory.

- `seeded-repo/` — a repo that has already run `governance-bootstrap` (has `tests/governance/`, `CONSTITUTION.md`, hooks). No key-material rule yet. For eval 1.
- `repo-with-file-size-rule/` — seeded repo with `tests/governance/rules/file-size-limit/check.sh` at the default 500-line limit. For eval 2.
- `repo-with-console-log-rule/` — seeded repo with `tests/governance/rules/no-console-log/check.sh` enabled and documented in CONSTITUTION.md. For eval 3.
- `seeded-repo/` also backs the negative-routing eval where amend should refuse a general health-check request and answer directly without mutating files; eval case 4.

All three share the same scaffolding; they differ only in which rules are pre-installed and what the constitution records.

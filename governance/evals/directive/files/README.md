# Eval fixtures — `governance directive {add,modify,remove}`

Each subdirectory is a seed repo state for one eval case. Before running, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"`, and point the skill at that directory.

Every fixture ships the install state pair — `.governance/install.yaml` (v3) and `.governance/packs.lock` (v2) — so DIRECTIVE_AMEND_FLOW.md Step 5b lockfile-sync assertions are testable.

- `seeded-repo/` — post-init repo with two installed packs: `governance-kit/core` (`source: builtin`, owns `secrets-hygiene`) and `acme/seeded-repo` (`source: local`, owns `no-secrets`). Backs eval cases 1 (add new directive into local pack), 4 (negative-routing health check), 5 (change-set obligation `plan-captured`), and 6 (refuse to modify a `builtin`-owned directive).
- `repo-with-file-size-rule/` — post-init repo with a local pack that owns `file-size-limit` at the default 500-line threshold. Backs eval case 2 (modify threshold; lockfile no-op).
- `repo-with-console-log-rule/` — post-init repo with a local pack that owns `no-console-log`. The fixture's `docs/LOGGING.md` references the directive by name so the removal eval can verify dangling-reference reporting. Backs eval case 3 (remove directive; lockfile updated; pack entry removed if last directive).

All three fixtures share the same scaffolding (`.governance/run.sh`, `.governance/lib.sh`, install pair). They differ only in which directives are pre-installed and what the constitution records.

# AGENTS.md

Entry point for humans and agents working in this repo. Skim top-to-bottom, then jump to the doc you need.

## What this repo is

`governance-kit` ships three Claude Code / Codex skills that together implement **governance-driven development** — a workflow where every rule in a `CONSTITUTION.md` has a matching executable test, and the two evolve as one commit.

The three skills:

| Skill | Purpose |
|---|---|
| [governance-bootstrap](governance-bootstrap/SKILL.md) | Scaffolds CONSTITUTION.md, `tests/governance/`, pre-commit + commit-msg hooks, and a CI workflow. |
| [governance-amend](governance-amend/SKILL.md) | Adds or modifies a rule atomically across test + constitution + evolution log. |
| [doc-gardener](doc-gardener/SKILL.md) | Detects stale docs (time-based or drift-against-code) and opens a remediation PR. |

## How governance works here

This repo dogfoods its own tooling. See [CONSTITUTION.md](CONSTITUTION.md) for the live rule set — currently 10 invariants covering constitution existence, agent entry point, secret scanning, .env hygiene, workflow hardening, doc-link integrity, Conventional Commits, large-file limits, committed-artifact prevention, and merge-conflict markers.

The enforcement layering:

1. **Pre-commit hook** (`.git/hooks/pre-commit`) — runs `tests/governance/run.sh` before each commit. Skippable with `SKIP_GOVERNANCE=1` or `git commit --no-verify` for hotfixes.
2. **CI workflow** ([.github/workflows/governance.yml](.github/workflows/governance.yml)) — runs the same tests on every PR and push to `main`. Cannot be skipped.

Run governance locally:

```sh
bash tests/governance/run.sh
```

## Repo layout

```
governance-kit/
├── CONSTITUTION.md              # Rules + rationale. Edit alongside the tests.
├── README.md                    # Short public overview.
├── AGENTS.md                    # You are here.
├── governance-bootstrap/        # Skill 1 — scaffolds governance in any repo.
│   ├── SKILL.md
│   ├── assets/                  # Templates copied into target repos.
│   └── references/              # RULES_CATALOG.md, NATIVE_TESTS.md.
├── governance-amend/            # Skill 2 — adds/modifies a rule atomically.
│   ├── SKILL.md
│   └── ...
├── doc-gardener/                # Skill 3 — scans + remediates stale docs.
│   ├── SKILL.md
│   └── ...
├── tests/governance/            # Rule tests for THIS repo (dogfood).
│   ├── run.sh
│   ├── lib.sh
│   └── rules/*.sh
└── .github/workflows/
    └── governance.yml
```

## Working in this repo

### Modifying a skill

Each skill is a self-contained directory with a `SKILL.md` (frontmatter + instructions), `assets/` (files copied to target repos), `references/` (deep-dive docs loaded on demand), and `evals/` (behavioral tests).

When editing a skill's behavior, keep the `description:` frontmatter field tight — it's what determines whether the skill auto-triggers. Too generic and it fires on everything; too specific and users have to name the skill by hand.

### Adding or changing a governance rule

Do not edit [CONSTITUTION.md](CONSTITUTION.md) by hand. Invoke the `governance-amend` skill — it enforces the cardinal rule (test + constitution + evolution-log entry all land together). See [governance-amend/SKILL.md](governance-amend/SKILL.md).

### Adding a new rule to the catalog

1. Add the bash test under `governance-bootstrap/assets/tests-bash/rules/<name>.sh`.
2. Document it in [governance-bootstrap/references/RULES_CATALOG.md](governance-bootstrap/references/RULES_CATALOG.md).
3. If it belongs in the default menu, surface it in the Step 3 `AskUserQuestion` flow inside [governance-bootstrap/SKILL.md](governance-bootstrap/SKILL.md).

### Commit messages

Conventional Commits are enforced. Prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. A `commit-msg` hook validates the pending subject line.

## Linking the skills into a runtime

This repo's skills are made available to local agent runtimes via symlinks:

```sh
ln -s $(pwd)/governance-bootstrap ~/.claude/skills/governance-bootstrap
ln -s $(pwd)/governance-bootstrap ~/.codex/skills/governance-bootstrap
# ...and the same for governance-amend and doc-gardener.
```

Edits to source files flow to both runtimes live.

## Further reading

- [CONSTITUTION.md](CONSTITUTION.md) — the live rule set and amendment process.
- [governance-bootstrap/references/RULES_CATALOG.md](governance-bootstrap/references/RULES_CATALOG.md) — every ready-made rule and its check.
- [governance-bootstrap/references/NATIVE_TESTS.md](governance-bootstrap/references/NATIVE_TESTS.md) — porting bash rules to pytest / jest / go test, husky / pre-commit.com snippets.
- [README.md](README.md) — the public-facing overview.

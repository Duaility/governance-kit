# governance-kit

**Frontier models do the work. You set the direction.** governance-kit turns a repo's rules, invariants, and principles into the steering signal a capable coding agent actually reads — versioned alongside the code, legible to the next agent that touches it, and enforced at every commit.

Conforms to the [Agent Skills](https://agentskills.io) format, so it installs into [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), Cursor, OpenCode, and 40+ other skills-compatible agents via a single [`npx skills`](https://github.com/vercel-labs/skills) command. MIT-licensed.

---

## What is governance-driven development?

Frontier models can ship real work. What they need from their human collaborators isn't supervision — it's **direction**: what "done" looks like, what must never regress, which trade-offs are non-negotiable. Governance-driven development treats that direction as a first-class artifact — versioned, machine-readable, and executable — instead of leaving it as ambient prose nobody updates.

The status quo scatters the steering signal. Prose in `CLAUDE.md` or `AGENTS.md` drifts out of attention. Pre-commit configs enforce checks but strip the *why*, so an agent hitting an edge case can't generalize from the rule's intent. And when direction changes, the rule, the test, and the rationale land in different PRs and decay at different rates.

governance-kit collapses all three into one unit. Every invariant ships as `rule + test + rationale` in a single folder, evolves in one atomic commit, and stays legible to the agent that reads it next week.

## Quickstart

```sh
# Install the skill into your agent (see Install below for scope options)
npx skills add Duaility/governance-kit

# In a fresh repo, launch your agent and ask it to bootstrap
claude
> governance init
```

`npx skills` auto-detects [governance/SKILL.md](governance/SKILL.md) and symlinks it into every skills-compatible runtime it finds on your machine (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`, …). `governance init` then bootstraps `CONSTITUTION.md`, `tests/governance/`, a pre-commit hook, and the `core` pack in the current repo. Make a bad commit to see it fire:

```sh
$ git commit -m "stuff"
[FAIL] conventional-commits — pending commit — 'stuff' does not match
       Conventional Commits with an issue suffix (<type>(scope)?: <subject> (#123))
```

## What a rule looks like

Every rule is a self-contained folder. Here's `conventional-commits` from the `core` pack:

```
conventional-commits/
├── rule.yaml         # category, summary, surface, hook
├── check.sh          # the executable test (runs in commit-msg + CI)
├── constitution.md   # Rule / Rationale / Enforced by / Exceptions
└── evals/test.sh     # pass + fail fixtures
```

The `constitution.md` carries the *why*:

```markdown
### conventional-commits

- **Rule**: Commit messages match `<type>(scope)?!?: subject (#123)`.
- **Rationale**: A trailing `(#123)` anchors every commit to a GitHub issue;
  the typed prefix keeps changelogs scannable. Together they make `git log` a
  readable audit trail instead of a stream of "fix stuff".
- **Enforced by**: `tests/governance/rules/conventional-commits/check.sh`
- **Exceptions**: Merge and revert commits are skipped automatically.
```

When the rule changes, all four files move together — the kit enforces this.

## Install

The recommended path is [`npx skills`](https://github.com/vercel-labs/skills), the open install CLI for [Agent Skills](https://agentskills.io):

```sh
npx skills add Duaility/governance-kit -g              # all agents, user-wide
npx skills add Duaility/governance-kit -a claude-code  # one agent only
npx skills add Duaility/governance-kit                 # project-scoped, committed to repo
```

<details>
<summary>Manual install (no <code>npx</code>, or for hacking on the kit)</summary>

Clone the repo and symlink the skill folder into each runtime you use:

```sh
git clone https://github.com/Duaility/governance-kit
cd governance-kit
ln -s "$(pwd)/governance" ~/.claude/skills/governance   # Claude Code
ln -s "$(pwd)/governance" ~/.codex/skills/governance    # Codex
```

Edits in the clone flow to both runtimes live — handy when contributing to governance-kit itself.

</details>

## Verbs

```
governance init                                    # bootstrap a repo
governance uninstall [--dry-run|--soft|--hard]     # tear-down
governance pack {search,add,update,remove,list}    # community pack lifecycle
governance rule {add,modify,remove}                # atomic rule amendments
```

> [!IMPORTANT]
> Don't edit `CONSTITUTION.md` or files under `tests/governance/rules/` by hand. The `rule *` verbs enforce the atomic-triple invariant — hand-edits will drift the constitution out of sync with the tests.

## Core pack

The kit-bundled `core` pack ships these rules:

| Rule | What it checks |
|---|---|
| `conventional-commits` | Commit messages match `<type>(scope)?: subject (#123)`. |
| `doc-freshness` | Opted-in docs carry a `<!-- last-verified: YYYY-MM-DD -->` marker within 90 days. |
| `no-broken-internal-doc-links` | Markdown links to local paths resolve. |
| `no-orphan-todos` | Every `TODO` / `FIXME` references an issue. |
| `repo-hygiene` | No merge markers, oversized files, build artefacts, debug statements, or overlong source files. |
| `required-docs` | Baseline root-level docs and hook scaffolding exist. |
| `secrets-hygiene` | No plaintext secrets in tracked files; `.env` is gitignored and untracked. |
| `workflows-hardened` | GitHub Actions workflows declare `permissions:` and pin third-party actions to a SHA. |

Full catalog: [governance/references/RULES_CATALOG.md](governance/references/RULES_CATALOG.md).

## Community packs

| Pack | Purpose | Install |
|---|---|---|
| [duaility/agent-governance](https://github.com/Duaility/governance-kit/tree/main/extensions/packs/agent-governance) | Agent-driven development discipline: issue tracking, plan-per-issue, commit-issue-plan match, per-commit token accounting. | `governance pack add gh:Duaility/governance-kit/extensions/packs/agent-governance` |

Authoring your own pack: [governance/references/AUTHORING_PACKS.md](governance/references/AUTHORING_PACKS.md).

## Core Philosophy

- **Agents execute. Humans steer.** Frontier models take on the heavy lifting — writing, editing, refactoring. The human contribution is *direction*. governance-kit is the channel for that direction, not a tripwire set against an untrusted worker.
- **Rationale is alignment data.** A rule without a *why* is a pattern to match. A rule with a *why* is a principle a capable agent can apply to edge cases the rule-author never imagined. Every rule folder ships both.
- **Direction evolves atomically.** When an invariant changes, the check, the `CONSTITUTION.md` entry, and the Evolution Log entry land in one commit. The steering signal never drifts away from the code it's steering.
- **Agents are authors, not bypass routes.** The `rule *` verbs are the single writer. Agents amend rules by invoking the verb, not by quietly editing `CONSTITUTION.md` — the steering surface stays auditable commit-by-commit.

## Why not just pre-commit / husky / lefthook?

Those tools run hooks. governance-kit runs hooks *and* keeps the rule's rationale, tests, and evolution history co-located with the hook — so a new maintainer reading `CONSTITUTION.md` can trace any rule back to the commit that introduced it and the test that enforces it. The `check.sh` scripts are plain bash; you can drop them into pre-commit / husky directly if you only want the enforcement half. See [governance/references/NATIVE_TESTS.md](governance/references/NATIVE_TESTS.md).

## Contributing

See [AGENTS.md](AGENTS.md) for repo layout, how to add rules to the `core` pack, and the dogfooding setup. One-time-per-clone:

```sh
./scripts/setup-clone.sh   # sets core.hooksPath=.githooks
```

Worktrees inherit this config — no per-worktree action needed.

## License

MIT

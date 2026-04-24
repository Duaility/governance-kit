# governance-kit

**Rules your agents can't ignore.** Every invariant ships as `rule + test + rationale` in a single folder, so the reason a rule exists travels with the script that enforces it — and lands in one atomic commit when it changes.

Conforms to the [Agent Skills](https://agentskills.io) format, so it installs into [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), Cursor, OpenCode, and 40+ other skills-compatible agents via a single [`npx skills`](https://github.com/vercel-labs/skills) command. MIT-licensed.

---

## Why governance-driven development?

Prose rules in `CLAUDE.md` / `AGENTS.md` are unenforceable — an agent can read them and still skip them. Pre-commit configs enforce rules but strip the *why*: six months later nobody remembers which rule was a paranoid overreaction and which one caught a real incident. And when you do change a rule, the test, the docs, and the rationale drift out of sync across three PRs.

governance-kit collapses that triangle into one unit:

- **Rules carry their rationale.** Each rule folder bundles `check.sh`, a `constitution.md` subsection (Rule / Rationale / Enforced by / Exceptions), and `evals/` fixtures.
- **Amendments are atomic.** Adding, modifying, or removing a rule lands the test, the CONSTITUTION update, and an Evolution Log entry in a single commit — enforced by the kit itself.
- **Packs are SHA-pinned, with opt-in capability scoping.** Community rule packs can declare `reads:` / `writes:` globs in `rule.yaml`; when a rule declares them, the skill statically sweeps its `check.sh` for out-of-bound paths and aborts the install on any violation.
- **Agents author rules via verbs, not by editing markdown.** The `governance rule *` verbs are the single writer — no hand-edits to `CONSTITUTION.md`.

## Quickstart

```sh
# Install the skill into your agent (globally, once)
npx skills add Duaility/governance-kit -g

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

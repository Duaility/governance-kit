# governance-kit

**Frontier models do the work. You set the direction.** governance-kit turns a repo's directives, guidelines, and principles into the steering signal a capable coding agent actually reads — versioned alongside the code, legible to the next agent that touches it, and enforced at every commit.

Conforms to the [Agent Skills](https://agentskills.io) format, so it installs into [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), Cursor, OpenCode, and 40+ other skills-compatible agents via a single [`npx skills`](https://github.com/vercel-labs/skills) command. MIT-licensed.

> [!NOTE]
> **Built for agent-heavy engineering teams.** If you're spec-driving features for an agent to implement, [spec-kit](https://github.com/github/spec-kit) is a better fit. governance-kit is the layer above — keeping the rules your agent must satisfy on every commit from drifting out of sync with the code, the tests, or each other.

---

## What is governance-driven development?

If you're shipping with agents, you've felt the pain. Your `CLAUDE.md` drifted three sprints ago and nobody noticed. Your agent forgot a rule it followed last week. Your pre-commit hook caught a regression but couldn't tell the agent *why* it failed, so the next attempt repeats the same class of mistake. Your steering signal lives in five places — `CLAUDE.md`, `.cursorrules`, pre-commit configs, CI, code review threads — and your agent only ever sees fragments.

Governance-driven development collapses the steering signal into one unit. Every directive ships as an **atomic triple**: a self-contained directive folder (test + rationale + metadata + eval), a matching subsection in `CONSTITUTION.md`, and a dated entry in its **Evolution Log** — the running, human-readable record of every amendment to the constitution. They land in one commit or none do. Directive, enforcement, and the record of why it changed can never drift apart.

The reason rationale lives next to the hook isn't documentation — it's **alignment data**. A bare hook is a tripwire: pattern match, fail, retry. A directive with rationale is a principle a frontier model can apply to edge cases the author never imagined.

```
agent reads CONSTITUTION.md  →  understands the *why*
agent writes code            →  generalizing from principle, not pattern
pre-commit hook fails        →  emits directive id + rationale
agent self-corrects          →  applying the principle, not retrying blind
```

Agents edit code. They also edit directives — but only through the `governance directive` verbs, never by hand-editing `CONSTITUTION.md`. The atomic-triple invariant carries every amendment with its test, its rationale, and its Evolution Log entry in a single commit. Agents are authors of the steering signal, not bypass routes around it.

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

## What a directive looks like

Every directive is a self-contained folder. Here's `doc-freshness` from the `core` pack:

```
doc-freshness/
├── directive.yaml    # category, summary, surface, hook
├── check.sh          # the executable test (runs in pre-commit + CI)
├── constitution.md   # Directive / Rationale / Enforced by / Exceptions
└── evals/test.sh     # pass + fail fixtures
```

The `constitution.md` carries the *why*:

```markdown
### doc-freshness

- **Directive**: Docs opted into `tests/governance/freshness.conf` carry a
  `<!-- last-verified: YYYY-MM-DD -->` marker dated within the last 90 days.
- **Rationale**: Critical runbooks and onboarding docs decay. A periodic
  "someone re-read this" checkpoint keeps them honest — if the deadline passes,
  either the doc still reflects reality (bump the date) or it doesn't (fix it).
- **Enforced by**: `tests/governance/directives/doc-freshness/check.sh`
- **Exceptions**: Remove a doc from `freshness.conf` to opt it out entirely.
```

The rationale is the load-bearing part: an agent reading a doc with a stale marker knows not to trust it as ground truth, and an agent updating a doc knows to bump the date. A bare hook can enforce the date format; only the co-located rationale tells the next agent what the date *means*. When the directive changes, all four files move together — the kit enforces this.

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
governance init                                       # bootstrap a repo
governance uninstall [--dry-run|--soft|--hard]        # tear-down
governance pack {search,add,update,remove,list}       # community pack lifecycle
governance directive {add,modify,remove}              # atomic directive amendments
```

> [!IMPORTANT]
> Don't edit `CONSTITUTION.md` or files under `tests/governance/directives/` by hand. The `directive *` verbs enforce the atomic-triple invariant — hand-edits will drift the constitution out of sync with the tests.

## Core pack

The kit-bundled `core` pack ships these directives:

| Directive | What it checks |
|---|---|
| `conventional-commits` | Commit messages match `<type>(scope)?: subject (#123)`. |
| `doc-freshness` | Opted-in docs carry a `<!-- last-verified: YYYY-MM-DD -->` marker within 90 days. |
| `no-broken-internal-doc-links` | Markdown links to local paths resolve. |
| `no-orphan-todos` | Every `TODO` / `FIXME` references an issue. |
| `repo-hygiene` | No merge markers, oversized files, build artefacts, debug statements, or overlong source files. |
| `required-docs` | Baseline root-level docs and hook scaffolding exist. |
| `secrets-hygiene` | No plaintext secrets in tracked files; `.env` is gitignored and untracked. |
| `workflows-hardened` | GitHub Actions workflows declare `permissions:` and pin third-party actions to a SHA. |

Full catalog: [governance/references/DIRECTIVES_CATALOG.md](governance/references/DIRECTIVES_CATALOG.md).

## Community packs

| Pack | Purpose | Install |
|---|---|---|
| [duaility/agent-governance](https://github.com/Duaility/governance-kit/tree/main/extensions/packs/agent-governance) | Agent-driven development discipline: issue templates, issue tracking, plan-per-issue, commit-issue-plan match, per-commit token accounting. | `governance pack add gh:Duaility/governance-kit/extensions/packs/agent-governance` |

Authoring your own pack: [governance/references/AUTHORING_PACKS.md](governance/references/AUTHORING_PACKS.md).

## Transparency

If you're trusting agents to ship code, you should be able to see exactly what they were told, what they did, what it cost, and how much you had to steer them. governance-kit makes three layers of that legible:

- **Directive provenance.** Every line of `CONSTITUTION.md` is git-blameable to the commit that introduced it and the test that enforces it, and the **Evolution Log** at the bottom of the file carries a dated, human-readable summary of every amendment. The atomic-triple invariant means policy and enforcement can never silently diverge — they land together or not at all.
- **Token accounting.** Every agent-authored commit carries token + cost trailers (`Token-Input`, `Token-Output`, `Cost-USD`, …) and a matching row in an append-only `COSTS.md` ledger that survives squash-merges. Every change has a price tag.
- **Steering accounting.** Every commit carries summary trailers (`Steer-Count`, `Steer-Types`, `Steer-Tiers`) and one `Steer-Key:` row per detected human-steering event — interrupt or redirect — in an append-only `STEERING.md` ledger. You can see at a glance which commits ran on autopilot and which needed your hand on the wheel.

Token and steering accounting ship in the [`agent-governance`](#community-packs) pack. Directive provenance is core.

## Why not just pre-commit / husky / lefthook?

Those tools run hooks. governance-kit runs hooks *and* keeps the directive's rationale, tests, and evolution history co-located with the hook — so a new maintainer reading `CONSTITUTION.md` can trace any directive back to the commit that introduced it and the test that enforces it. The `check.sh` scripts are plain bash; you can drop them into pre-commit / husky directly if you only want the enforcement half. See [governance/references/NATIVE_TESTS.md](governance/references/NATIVE_TESTS.md).

## Contributing

See [AGENTS.md](AGENTS.md) for repo layout, how to add directives to the `core` pack, and the dogfooding setup. One-time-per-clone:

```sh
./scripts/setup-clone.sh   # sets core.hooksPath=.githooks
```

Worktrees inherit this config — no per-worktree action needed.

## License

MIT

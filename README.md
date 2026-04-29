# governance-kit

**Declare the repo state you want. Let agents converge on it.**

governance-kit turns your repo's rules into a versioned constitution — a declarative description of the state the repository must stay in. Agents read it, checks compare it against reality on every commit, and every agent-authored change leaves a git-native audit trail.

Conforms to the [Agent Skills](https://agentskills.io) format. Installs into [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), Cursor, OpenCode, and 40+ skills-compatible agents via [`npx skills`](https://github.com/vercel-labs/skills). MIT-licensed.

> [!NOTE]
> **Built for agent-heavy engineering teams.** If you're spec-driving features for an agent to implement, [spec-kit](https://github.com/github/spec-kit) is the right fit. governance-kit is the layer above — keeping the rules your agent must satisfy on every commit from drifting out of sync with the code, the tests, or each other.

---

## Why governance-driven development?

Coding agents do the engineering work now. The hard part is no longer just telling one agent what to do in one session; it is keeping the repository understandable across many branches, many agents, and many handoffs.

governance-kit treats governance as repo state:

- **Desired state** lives in `CONSTITUTION.md`: directives, rationale, enforcement paths, exceptions, and an evolution log.
- **Current state** is the working tree, staged diff, commit message, PR state, receipts, and ledgers.
- **Reconciliation** happens through `.governance/run.sh` and hook dispatchers. A failed directive names the gap and its rationale; the agent fixes the repo, reruns the check, and repeats until reality matches the declared state.
- **Abstractions** keep humans out of low-level ceremony. You reason about directives, packs, receipts, and ledgers instead of scattered hook scripts, chat transcripts, and one-off agent instructions.

That gives a practical steering surface. Your guidance has to reach the next agent, on the next branch, without you. governance-kit's answer is a **constitution**: a versioned set of directives every agent reads on every commit, plus a `STEERING.md` ledger that captures the per-turn redirects you did not promote into a directive.

It also gives a practical visibility surface. When agents ship the diffs, you need a readable trail, not a stack of PRs. Every agent-authored commit can leave append-only ledgers — `CONSTITUTION.md` (rules + evolution log), `COSTS.md` (token cost), `STEERING.md` (where you had your hand on the wheel). Git-native. You read the repo's state record, not the chat history.

```mermaid
flowchart LR
    C[CONSTITUTION.md<br/>desired repo state]
    G{Governance checks}
    A[Agent fixes the gap]
    R[(Repo<br/>current state)]

    C --> G
    R --> G
    G -->|"gap + rationale"| A
    A -->|"commit"| R
    G -->|"pass"| OK([Ready to merge])
```

Agents do the work. The constitution describes the state the repo must satisfy. The directives keep both sides honest — a frontier-model agent reading a directive's rationale generalizes to cases the author never encoded; you read the ledgers as the state record for what the agent fleet just shipped.

The stance in one line: **describe the state, continuously check reality, and let agents reconcile the difference.**

## Visibility

If you're trusting agents to ship code, you need to see exactly what they were told, what they did against each issue, what it cost, and how much you had to steer them. Four git-native, append-only artifacts:

- **Directive provenance** (`CONSTITUTION.md`). Every line is git-blameable to the commit that introduced it and the test that enforces it. The **Evolution Log** at the bottom of the file carries a dated, human-readable summary of every amendment. Because the CLI verbs require the check, the rationale, and the log entry to land together, policy and enforcement can't silently diverge.
- **Per-issue receipts** (`receipts/issue-<N>-*.md`). One receipt per issue, with `## Checklist`, `## What changed`, `## Out of scope`, and `## Verification` sections. Every `- [x]` checklist item must crosswalk into `## What changed` or `## Verification` — the trust boundary that prevents silent box-flipping. The receipt is what a reviewer reads instead of the diff.
- **Token cost** (`COSTS.md`). Every agent-authored commit carries token + cost trailers (`Token-Input`, `Token-Output`, `Cost-USD`, …) and a matching row in the ledger. Survives squash-merges via a stable `Cost-Key`. Every change has a price tag.
- **Human steering** (`STEERING.md`). Every commit carries summary trailers (`Steer-Count`, `Steer-Types`, `Steer-Tiers`) tallying the rows it added to the ledger — one row per detected human-steering event (interrupt or redirect). See at a glance which commits ran on autopilot and which needed your hand on the wheel.

These compose into a chain — **issue → receipt → commit → cost** — and breaking any link fails the next push. Directive provenance is core. Receipts, the chain, and token cost ship in the [`agent-governance`](#community-packs) pack; steering accounting is in the same pack but opt-in only (it records human correction text verbatim — privacy tradeoff).

## Quickstart

```sh
# Install the skill into your agent (see Install for scope options)
npx skills add Duaility/governance-kit

# In a fresh repo, launch your agent and ask it to bootstrap
claude
> governance init
```

`npx skills` auto-detects [governance/SKILL.md](governance/SKILL.md) and symlinks it into every skills-compatible runtime on your machine (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`, …). `governance init` bootstraps `CONSTITUTION.md`, `.governance/`, a pre-commit hook, and the `governance-kit/core` pack.

Make a bad commit to see the gate fire:

```sh
$ git commit -m "stuff"
[FAIL] commit-message-format — pending commit — 'stuff' does not match
       Conventional Commits with an issue suffix (<type>(scope)?: <subject> (#123))
```

The agent reads the id + rationale and self-corrects on the next attempt.

## How it ships

### Verbs

```
governance init                                       # bootstrap a repo
governance uninstall [--dry-run|--soft|--hard]        # tear-down
governance pack {search,add,update,remove,list}       # community pack lifecycle
governance directive {add,modify,remove}              # atomic directive amendments
```

> [!IMPORTANT]
> Don't hand-edit `CONSTITUTION.md` or files under `.governance/`. The `directive *` verbs keep the check, the rationale, and the history in lockstep — hand-edits will drift the constitution out of sync with the tests.

### Anatomy of a directive

Every directive is a self-contained folder. The minimum, here `doc-freshness` from the `governance-kit/core` pack:

```
doc-freshness/
├── directive.yaml    # category, summary, surface, hook
├── check.sh          # the executable test (pre-commit + CI)
├── constitution.md   # Directive / Rationale / Enforced by / Exceptions
└── evals/test.sh     # pass + fail fixtures
```

Directives that need more carry optional siblings — `lib/` (shared bash/Python), `hooks/<pre-commit|commit-msg|prepare-commit-msg|post-commit|pre-push>.sh` (side-effect scripts wired into the dispatcher by the hook generator), `runtimes/<name>.sh` (per-runtime helpers), and `install-assets/` (templates seeded at bootstrap). All travel with the directive — `git mv` relocates the whole folder. `agent-token-accounting` uses every one of these.

The `constitution.md` carries the *why*:

```markdown
### doc-freshness

- **Directive**: Docs opted into `.governance/freshness.conf` carry a
  `<!-- last-verified: YYYY-MM-DD -->` marker dated within the last 90 days.
- **Rationale**: Critical runbooks and onboarding docs decay. A periodic
  "someone re-read this" checkpoint keeps them honest — if the deadline
  passes, either bump the date or fix the doc.
- **Enforced by**: `.governance/packs/governance-kit/core/directives/doc-freshness/check.sh`
- **Exceptions**: Remove a doc from `freshness.conf` to opt it out.
```

A bare hook checks the date format. The rationale tells the next agent — and the next human — what the date is *for*.

```mermaid
flowchart LR
    R[Reads directive<br/>+ rationale] --> W[Writes code]
    W --> Q{Check on commit}
    Q -->|pass| OK([Lands])
    Q -->|"fail — emits<br/>id + rationale"| R
```

### Composition

Directives are invariants on state, not steps in a procedure. Each one describes a condition the repo must satisfy; the runner re-evaluates them all on every firing. `.governance/run.sh` iterates `directives/*/check.sh` alphabetically — no `depends_on:`, no `order:`, no graph engine.

When directive B logically depends on directive A's postcondition — e.g. "PR must have a review" depends on "PR must exist" — B reads the precondition itself and skips-with-info if it's not met. The cascade falls out of re-evaluation: fix what's currently violating, re-run, the next gate fires, fix that, re-run, done.

This is declarative reconciliation applied to a repository. A directive describes the desired state; its check observes current state; the agent takes the mandated action; then `bash .governance/run.sh` surfaces the next gap. Don't chain actions; describe state and let re-evaluation converge.

### Core pack

Ships with `governance init`:

| Directive | What it checks |
|---|---|
| `commit-message-format` | Commit messages match `<type>(scope)?: subject (#123)` — Conventional Commits prefix plus a trailing GitHub issue reference. |
| `doc-freshness` | Opted-in docs carry a `<!-- last-verified: YYYY-MM-DD -->` marker within 90 days. |
| `no-broken-internal-doc-links` | Markdown links to local paths resolve. |
| `no-orphan-todos` | Every `TODO` / `FIXME` references an issue. |
| `repo-hygiene` | No merge markers, oversized files, build artefacts, debug statements, or overlong source files. |
| `required-docs` | Baseline root-level docs and hook scaffolding exist. |
| `secrets-hygiene` | No plaintext secrets in tracked files; `.env` is gitignored and untracked. |
| `workflows-hardened` | GitHub Actions workflows declare `permissions:` and pin third-party actions to a SHA. |

Full catalog: [governance/references/DIRECTIVES_CATALOG.md](governance/references/DIRECTIVES_CATALOG.md).

## Install

The recommended path is [`npx skills`](https://github.com/vercel-labs/skills), the open install CLI for [Agent Skills](https://agentskills.io):

```sh
npx skills add Duaility/governance-kit -g              # all agents, user-wide
npx skills add Duaility/governance-kit -a claude-code  # one agent only
npx skills add Duaility/governance-kit                 # project-scoped, committed to repo
```

<details>
<summary>Manual install (no <code>npx</code>, or for hacking on the kit)</summary>

Clone and symlink the skill folder into each runtime you use:

```sh
git clone https://github.com/Duaility/governance-kit
cd governance-kit
ln -s "$(pwd)/governance" ~/.claude/skills/governance   # Claude Code
ln -s "$(pwd)/governance" ~/.codex/skills/governance    # Codex
```

Edits in the clone flow to both runtimes live — handy when contributing to governance-kit itself.

</details>

## Community packs

| Pack | Purpose | Install |
|---|---|---|
| [duaility/agent-governance](extensions/packs/agent-governance/README.md) | The audit chain for agent-driven repos. See below. | `governance pack add gh:Duaility/governance-kit/extensions/packs/agent-governance` |

### `duaility/agent-governance`

The chain — **issue → receipt → commit → cost** — turned into mechanical directives. Install when every commit in your repo is agent-authored and you need a reviewer-readable trail per issue.

| Directive | What it enforces | Preset |
|---|---|---|
| `issue-templates` | `.github/ISSUE_TEMPLATE/` carries `config.yml` (blank issues off), `proposal.yml`, `bug.yml` with the required handoff fields. | standard |
| `issues-tracked` | `QUALITY.md` exists at repo root with `## Open` and `## Resolved` sections. | standard |
| `receipt-per-issue` | Every `receipts/*.md` has a unique `issue-<N>` filename token, the four required sections, and each `- [x]` checklist item crosswalks into `## What changed` or `## Verification`. | minimal |
| `commit-issue-receipt-match` | Every non-merge commit's issue anchor (`(#N)` or `Issue: #N`) matches an `issue-<N>` token on a touched receipt. | minimal |
| `agent-token-accounting` | Every commit carries token + cost trailers and a matching `COSTS.md` row keyed by `Cost-Key`. | standard |
| `agent-steering-accounting` | Every agent-authored commit stamps `Steer-Count` / `Steer-Types` / `Steer-Tiers` and appends rows to `STEERING.md`. **Opt-in — not in any preset**, because it records human correction text verbatim. | — |

Authoring your own pack: [governance/references/AUTHORING_PACKS.md](governance/references/AUTHORING_PACKS.md).

## Why not just pre-commit / husky / lefthook?

Those tools run hooks. governance-kit runs hooks **and** carries the rationale, the audit trail, and the evolution history alongside the test. A new maintainer can trace any directive back to its commit and its check. The `check.sh` scripts are plain bash — drop them into pre-commit or husky directly if you only want the enforcement half. See [governance/references/NATIVE_TESTS.md](governance/references/NATIVE_TESTS.md).

## Contributing

See [AGENTS.md](AGENTS.md) for repo layout, how to add directives to the `governance-kit/core` pack, and the dogfooding setup. One-time-per-clone:

```sh
./scripts/setup-clone.sh   # sets core.hooksPath=.githooks
```

Worktrees inherit this config — no per-worktree action needed.

## License

MIT

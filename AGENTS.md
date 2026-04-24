<!-- last-verified: 2026-04-24 -->

# AGENTS.md

Entry point for humans and agents working in this repo. Skim top-to-bottom, then jump to the doc you need.

<!-- governance: rules-to-follow -->
## Rules to follow

If you are an agent — or a human — working in this repo, **read [CONSTITUTION.md](CONSTITUTION.md) and follow it**. It defines the principles, guidelines, and invariants that every change in this repo must satisfy.

- The mechanical invariants are enforced by `tests/governance/run.sh` (run via the pre-commit hook locally and the [governance.yml](.github/workflows/governance.yml) workflow in CI).
- The principles and guidelines cannot be mechanically checked — you are expected to read them and apply judgment. A change that defies a principle without explanation will block the PR.

See the **Compliance** section of [CONSTITUTION.md](CONSTITUTION.md) for the full directive, including how to document approved deviations.
<!-- /governance: rules-to-follow -->

## What this repo is

`governance-kit` ships Claude Code / Codex skills that together implement **governance-driven development** — a workflow where every rule in a `CONSTITUTION.md` has a matching executable test, and the two evolve as one commit.

The user-facing entry point is the unified [`governance`](governance/SKILL.md) skill. It exposes four verb families — `init`, `uninstall`, `pack {search,add,update,remove,list}`, `rule {add,modify,remove}` — and is the single writer for every governance-kit lifecycle operation.

| Skill | Purpose |
|---|---|
| [governance](governance/SKILL.md) | **User-facing entry point.** Unified verb surface: `init`, `uninstall`, `pack *`, `rule *`. |

## How governance works here

This repo dogfoods its own tooling. The live rule set lives in [CONSTITUTION.md](CONSTITUTION.md); rule scripts live under [tests/governance/rules/](tests/governance/rules/).

Run the suite locally:

```sh
bash tests/governance/run.sh
```

Escape hatches: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` skip the local hook for hotfixes. CI re-enforces every rule on every PR — there is no developer-side bypass for CI.

## Repo layout

```
governance-kit/
├── CONSTITUTION.md              # Rules + rationale. Edit alongside the tests.
├── README.md                    # Short public overview.
├── AGENTS.md                    # You are here.
├── governance/                  # Unified lifecycle skill — verb entry point.
│   ├── SKILL.md
│   ├── assets/                  # Templates copied into target repos.
│   │   ├── CONSTITUTION.template.md
│   │   ├── AGENTS.directive.md
│   │   ├── governance.yml
│   │   ├── setup-clone.sh
│   │   ├── tests-bash/          # Universal bash runner shipped into every target repo.
│   │   ├── amend/               # Templates for `rule *` (rule.template.sh, invariant-section.template.md).
│   │   └── packs/               # Kit-bundled packs — today: `core` plus the shared `lib/`.
│   │       └── core/
│   │           ├── pack.yaml           # pack id + presets
│   │           └── rules/
│   │               └── <rule-id>/      # self-contained rule folder
│   │                   ├── rule.yaml       # per-rule metadata
│   │                   ├── check.sh        # executable test
│   │                   ├── constitution.md # Invariant subsection
│   │                   └── evals/test.sh   # pass/fail fixtures
│   ├── references/              # INIT_FLOW.md, UNINSTALL_FLOW.md, RULE_AMEND_FLOW.md,
│   │                            #   VERBS.md, RULE_VERBS.md, PACK_VERBS.md,
│   │                            #   RULES_CATALOG.md, AUTHORING_PACKS.md, NATIVE_TESTS.md,
│   │                            #   RULE_AUTHORING.md, UNINSTALL_MATRIX.md,
│   │                            #   MANIFEST_SCHEMA.md, AGENT_TOKEN_ACCOUNTING.md.
│   └── evals/                   # Behavioral fixtures for the verbs.
├── extensions/                  # Community pack catalog + monorepo of community-shaped packs.
│   ├── catalog.community.json
│   ├── catalog.schema.json
│   └── packs/
│       └── agent-governance/    # duaility/agent-governance — authored as a community pack.
├── tests/governance/            # Rule tests for THIS repo (dogfood).
│   ├── run.sh
│   ├── lib.sh
│   └── rules/<id>/check.sh       # each rule is a self-contained folder
└── .github/workflows/
    └── governance.yml
```

## Working in this repo

### Modifying the governance skill

Each skill is a self-contained directory with a `SKILL.md` (frontmatter + instructions), `assets/` (files copied to target repos), `references/` (deep-dive docs loaded on demand), and `evals/` (behavioral tests).

When editing a skill's behavior, keep the `description:` frontmatter field tight — it's what determines whether the skill auto-triggers. Too generic and it fires on everything; too specific and users have to name the skill by hand.

### Adding or changing a governance rule

Do not edit [CONSTITUTION.md](CONSTITUTION.md) by hand. Invoke the `governance` skill's `rule *` verbs — they enforce the cardinal rule (test + constitution + evolution-log entry all land together). See [governance/references/RULE_AMEND_FLOW.md](governance/references/RULE_AMEND_FLOW.md).

### Adding a new rule to the catalog

Rules live inside **packs**, each at its own pack root. Today:
`core` lives at `governance/assets/packs/core/` (kit-bundled),
and `duaility/agent-governance` lives at `extensions/packs/agent-governance/`
(community-shaped, authored as if hosted in its own repo but colocated
here under the monorepo layout — see `extensions/README.md`).
Each rule is a self-contained folder — test, snippet, metadata, and
eval all live together under `rules/<rule-id>/`.

1. Create `<pack-root>/<pack-dir>/rules/<id>/` and populate it with:
   - `rule.yaml` — scalar fields `category`, `recommended`, `summary`,
     `surface` (`repo-state`|`change-set`), `hook`
     (`pre-commit`|`commit-msg`|`prepare-commit-msg`|`none`), optional
     `always_install` (reserved to `core`).
   - `check.sh` — the bash test.
   - `constitution.md` — the Invariant subsection (Rule / Rationale /
     Enforced by / Exceptions).
   - `evals/test.sh` — pass + fail fixtures. Run `bash scripts/test-packs.sh`
     to confirm.
   - Optional sibling folders for rules that need external code:
     `lib/` (stdlib Python or bash shared across the rule's pieces),
     `hooks/<pre-commit|commit-msg|prepare-commit-msg>.sh` (side-effect
     scripts wired into the generated dispatcher by the hook generator),
     `runtimes/<name>.sh` (per-runtime helpers). All three are copied
     along with `check.sh` when the rule installs, so a rule is one
     `git mv` away from relocating.
2. If the rule should be part of `minimal` / `standard` / `strict`,
   add its id to the relevant preset block in the pack's `pack.yaml`.
3. Document it in [governance/references/RULES_CATALOG.md](governance/references/RULES_CATALOG.md).
4. For authoring an entirely new pack, see
   [governance/references/AUTHORING_PACKS.md](governance/references/AUTHORING_PACKS.md).

### Commit messages

Conventional Commits are enforced. Prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. A `commit-msg` hook validates the pending subject line.

## Linking the skills into a runtime

This repo's skills are made available to local agent runtimes via symlinks:

```sh
ln -s $(pwd)/governance ~/.claude/skills/governance
ln -s $(pwd)/governance ~/.codex/skills/governance
```

Edits to source files flow to both runtimes live.

## Further reading

- [CONSTITUTION.md](CONSTITUTION.md) — the live rule set and amendment process.
- [governance/references/RULES_CATALOG.md](governance/references/RULES_CATALOG.md) — every ready-made rule and its check.
- [governance/references/AUTHORING_PACKS.md](governance/references/AUTHORING_PACKS.md) — writing a third-party pack.
- [governance/references/NATIVE_TESTS.md](governance/references/NATIVE_TESTS.md) — porting bash rules to pytest / jest / go test, husky / pre-commit.com snippets.
- [README.md](README.md) — the public-facing overview.

<!-- last-verified: 2026-04-23 -->

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

The unified entry point is the [`governance`](governance/SKILL.md) skill. It exposes four verb families — `init`, `uninstall`, `pack {search,add,update,remove,list}`, `rule {add,modify,remove}` — and is the user-facing surface for every governance-kit lifecycle operation. The per-lifecycle skills below are in **retirement in progress** (issue [#31](https://github.com/Duaility/governance-kit/issues/31)): they still own the authoritative flows and assets that the unified skill delegates to, and they will be deleted once the unified skill absorbs the prose and relocates the assets under `governance/`.

| Skill | Purpose |
|---|---|
| [governance](governance/SKILL.md) | **User-facing entry point.** Unified verb surface: `init`, `uninstall`, `pack *`, `rule *`. |
| [governance-bootstrap](governance-bootstrap/SKILL.md) | *(Retirement in progress.)* Authoritative 8-step flow for `governance init`; owns the pack tree, templates, hook lib, and CI workflow. |
| [governance-amend](governance-amend/SKILL.md) | *(Retirement in progress.)* Authoritative atomic-triple flow for `governance rule {add,modify,remove}`; owns the rule + invariant templates. |
| [governance-gardener](governance-gardener/SKILL.md) | Walks the governance surface and produces a Governance Health Report flagging blind spots, dead rules, escape-hatch friction, and doc drift. Optional follow-up actions open PRs. Not in scope for the issue #31 rework. |
| [governance-reset](governance-reset/SKILL.md) | *(Retirement in progress.)* Authoritative 6-step flow for `governance uninstall`; owns the ownership-marker discipline, install-manifest schema, and dry-run / soft / hard mode logic. |

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
│   └── references/              # VERBS.md (per-verb reference).
├── extensions/                  # Community pack catalog + JSON schema.
│   ├── catalog.community.json
│   └── catalog.schema.json
├── governance-bootstrap/        # Skill 1 — scaffolds governance in any repo.
│   ├── SKILL.md
│   ├── assets/                  # Templates copied into target repos.
│   │   └── packs/               # Rule packs (core, agent-governance, ...).
│   │       └── <pack>/
│   │           ├── pack.yaml           # pack id + presets
│   │           └── rules/
│   │               └── <rule-id>/      # self-contained rule folder
│   │                   ├── rule.yaml       # per-rule metadata
│   │                   ├── check.sh        # executable test
│   │                   ├── constitution.md # Invariant subsection
│   │                   └── evals/test.sh   # pass/fail fixtures
│   └── references/              # RULES_CATALOG.md, NATIVE_TESTS.md,
│                                #   AUTHORING_PACKS.md.
├── governance-amend/            # Skill 2 — adds/modifies a rule atomically.
│   ├── SKILL.md
│   └── ...
├── governance-gardener/         # Skill 3 — walks governance, emits a health report.
│   ├── SKILL.md
│   └── ...
├── governance-reset/            # Skill 4 — uninstalls a bootstrapped setup cleanly.
│   ├── SKILL.md
│   ├── references/              # UNINSTALL_MATRIX.md, MANIFEST_SCHEMA.md.
│   └── evals/
├── tests/governance/            # Rule tests for THIS repo (dogfood).
│   ├── run.sh
│   ├── lib.sh
│   └── rules/<id>/check.sh       # each rule is a self-contained folder
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

Rules live inside **packs** under `governance-bootstrap/assets/packs/<pack>/`.
Each rule is a self-contained folder — test, snippet, metadata, and
eval all live together under `rules/<rule-id>/`. Two packs ship in-tree
today: `core` (general rules) and `agent-governance` (rules for repos
operating under agent-driven development).

1. Create `governance-bootstrap/assets/packs/<pack>/rules/<id>/` and
   populate it with:
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
3. Document it in [governance-bootstrap/references/RULES_CATALOG.md](governance-bootstrap/references/RULES_CATALOG.md).
4. For authoring an entirely new pack, see
   [governance-bootstrap/references/AUTHORING_PACKS.md](governance-bootstrap/references/AUTHORING_PACKS.md).

### Commit messages

Conventional Commits are enforced. Prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. A `commit-msg` hook validates the pending subject line.

## Linking the skills into a runtime

This repo's skills are made available to local agent runtimes via symlinks:

```sh
ln -s $(pwd)/governance-bootstrap ~/.claude/skills/governance-bootstrap
ln -s $(pwd)/governance-bootstrap ~/.codex/skills/governance-bootstrap
# ...and the same for governance-amend, governance-gardener, and governance-reset.
```

Edits to source files flow to both runtimes live.

## Further reading

- [CONSTITUTION.md](CONSTITUTION.md) — the live rule set and amendment process.
- [governance-bootstrap/references/RULES_CATALOG.md](governance-bootstrap/references/RULES_CATALOG.md) — every ready-made rule and its check.
- [governance-bootstrap/references/AUTHORING_PACKS.md](governance-bootstrap/references/AUTHORING_PACKS.md) — writing a third-party pack.
- [governance-bootstrap/references/NATIVE_TESTS.md](governance-bootstrap/references/NATIVE_TESTS.md) — porting bash rules to pytest / jest / go test, husky / pre-commit.com snippets.
- [README.md](README.md) — the public-facing overview.

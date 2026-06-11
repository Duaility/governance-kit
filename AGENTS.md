<!-- last-verified: 2026-04-24 -->

# AGENTS.md

Entry point for humans and agents working in this repo. Skim top-to-bottom, then jump to the doc you need.

<!-- governance: directives-to-follow -->
## Rules to follow

If you are an agent — or a human — working in this repo, **read [CONSTITUTION.md](CONSTITUTION.md) and follow it**. It defines the principles, guidelines, and directives that every change in this repo must satisfy.

- The mechanical directives are enforced by `.governance/run.sh` (run via the pre-commit hook locally and the [governance.yml](.github/workflows/governance.yml) workflow in CI).
- The principles and guidelines cannot be mechanically checked — you are expected to read them and apply judgment. A change that defies a principle without explanation will block the PR.

See the **Compliance** section of [CONSTITUTION.md](CONSTITUTION.md) for the full directive, including how to document approved deviations.
<!-- /governance: directives-to-follow -->

## What this repo is

`governance-kit` ships Claude Code / Codex skills that together implement **governance-driven development** — a workflow where every directive in a `CONSTITUTION.md` has a matching executable test, and the two evolve as one commit.

The user-facing entry point is the unified [`governance`](governance/SKILL.md) skill. It exposes four verb families — `init`, `uninstall`, `pack {search,add,update,remove,list}`, `directive {add,modify,remove}` — and is the single writer for every governance-kit lifecycle operation.

| Skill | Purpose |
|---|---|
| [governance](governance/SKILL.md) | **User-facing entry point.** Unified verb surface: `init`, `uninstall`, `pack *`, `directive *`. |

## How governance works here

This repo dogfoods its own tooling. The live directive set lives in [CONSTITUTION.md](CONSTITUTION.md); every directive — kit-bundled, community-pack, or hand-authored — lives under [.governance/packs/](.governance/packs/) at `<owner>/<name>/directives/<id>/`. Hand-authored repo-local packs (this repo's own dogfood lives at [.governance/packs/duaility/governance-kit/](.governance/packs/duaility/governance-kit/)) are just packs whose `pack.yaml` has no `source:` field.

Run the suite locally:

```sh
bash .governance/run.sh
```

Escape hatches: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` skip the local hook for hotfixes. CI re-enforces every directive on every PR — there is no developer-side bypass for CI.

## Repo layout

```
governance-kit/
├── CONSTITUTION.md              # Directives + rationale. Edit alongside the tests.
├── README.md                    # Short public overview.
├── AGENTS.md                    # You are here.
├── governance/                  # Unified lifecycle skill — verb entry point.
│   ├── SKILL.md
│   ├── assets/                  # Templates copied into target repos.
│   │   ├── CONSTITUTION.template.md
│   │   ├── AGENTS.snippet.md
│   │   ├── governance.yml
│   │   ├── enable-governance.sh
│   │   ├── tests-bash/          # Universal bash runner shipped into every target repo.
│   │   ├── amend/               # Templates for `directive *` (directive.template.sh, directive-section.template.md).
│   │   ├── catalog.community.json   # Advisory index of known community packs (read by `governance pack search`).
│   │   ├── catalog.schema.json      # JSON Schema for catalog entries.
│   │   └── packs/lib/           # Shared pack tooling (packs.sh, install.sh, hooks.sh, …).
├── packs/                       # Kit-bundled concern packs (source of truth).
│   └── <concern>/               # foundation, security, docs, commits, hygiene, audit, integrity
│       ├── pack.yaml            # pack id + presets
│       └── directives/
│           └── <directive-id>/  # self-contained directive folder
│               ├── directive.yaml    # per-directive metadata
│               ├── check.sh          # executable test
│               ├── constitution.md   # Directive subsection
│               ├── config.conf       # optional: seeds the user overlay
│               ├── defaults.conf     # optional: pack-owned live default list
│               └── evals/test.sh     # pass/fail fixtures
│   ├── references/              # INIT_FLOW.md, UNINSTALL_FLOW.md, RESET_FLOW.md,
│   │                            #   DIRECTIVE_AMEND_FLOW.md,
│   │                            #   VERBS.md, DIRECTIVE_VERBS.md, PACK_VERBS.md,
│   │                            #   DIRECTIVES_CATALOG.md, PACK_AUTHORING.md, NATIVE_TESTS.md,
│   │                            #   DIRECTIVE_AUTHORING.md, UNINSTALL_MATRIX.md,
│   │                            #   INSTALL_SCHEMA.md, LOCK_SCHEMA.md, AGENT_TOKEN_ACCOUNTING.md.
│   └── evals/                   # Behavioral fixtures for the verbs.
├── .governance/            # Directive tests for THIS repo (dogfood).
│   ├── run.sh
│   ├── lib.sh
│   ├── install.yaml             # init choices + side-effect ledger
│   ├── packs.lock               # pack pin state (id, version, source, sha)
│   ├── conf/<owner>/<pack>/<directive-id>.conf # user-owned per-directive config overlays (pack-qualified)
│   └── packs/<owner>/<name>/directives/<id>/check.sh  # every directive lives in some pack
└── .github/workflows/
    └── governance.yml
```

## Working in this repo

### Modifying the governance skill

Each skill is a self-contained directory with a `SKILL.md` (frontmatter + instructions), `assets/` (files copied to target repos), `references/` (deep-dive docs loaded on demand), and `evals/` (behavioral tests).

When editing a skill's behavior, keep the `description:` frontmatter field tight — it's what determines whether the skill auto-triggers. Too generic and it fires on everything; too specific and users have to name the skill by hand.

### Adding or changing a governance directive

Do not edit [CONSTITUTION.md](CONSTITUTION.md) by hand. Invoke the `governance` skill's `directive *` verbs — they enforce the cardinal rule (test + constitution + evolution-log entry all land together). See [governance/references/DIRECTIVE_AMEND_FLOW.md](governance/references/DIRECTIVE_AMEND_FLOW.md).

### Adding a new directive to the catalog

Directives live inside **packs**, each at its own pack root. The kit ships seven
bundled concern packs — `governance-kit/{foundation,security,docs,commits,hygiene,audit,integrity}`,
each at `packs/<concern>/`. Community packs are authored in their own
repos and consumed by target repos via `governance pack add gh:<owner>/<repo>`;
they are not bundled here. Each directive is a self-contained folder — test,
snippet, metadata, and eval all live together under `directives/<directive-id>/`.

1. Create `<pack-root>/<pack-dir>/directives/<id>/` and populate it with:
   - `directive.yaml` — scalar fields `category`, `recommended`, `summary`,
     `surface` (`repo-state`|`change-set`), `hook`
     (`pre-commit`|`commit-msg`|`prepare-commit-msg`|`post-commit`|`pre-push`|`none`), optional
     `always_install` (reserved to the bundled `governance-kit/*` packs).
   - `check.sh` — the bash test.
   - `constitution.md` — the Directive subsection (Directive / Rationale /
     Enforced by / Exceptions).
   - `config.conf` (optional) — an all-comment template that seeds the user
     overlay `.governance/conf/<owner>/<pack>/<id>.conf` at install. `defaults.conf` (optional)
     — a pack-owned live default list for a list-valued directive, refreshed on
     `pack update`. Read both via the `lib.sh` helpers (`conf_get`, `conf_list`).
     See [governance/references/PACK_AUTHORING.md](governance/references/PACK_AUTHORING.md).
   - `evals/test.sh` — pass + fail fixtures. Run `bash scripts/test-packs.sh`
     to confirm.
   - Optional sibling folders for directives that need external code:
     `lib/` (stdlib Python or bash shared across the directive's pieces),
     `hooks/<pre-commit|commit-msg|prepare-commit-msg|post-commit|pre-push>.sh` (side-effect
     scripts wired into the generated dispatcher by the hook generator),
     `runtimes/<name>.sh` (per-runtime helpers). All three are copied
     along with `check.sh` when the directive installs, so a directive is one
     `git mv` away from relocating.
2. If the directive should be part of `minimal` / `standard` / `strict`,
   add its id to the relevant preset block in the pack's `pack.yaml`.
3. Document it in [governance/references/DIRECTIVES_CATALOG.md](governance/references/DIRECTIVES_CATALOG.md).
4. For authoring an entirely new pack, see
   [governance/references/PACK_AUTHORING.md](governance/references/PACK_AUTHORING.md).

### Versioning & releases

Version lines are written **only** by [`scripts/release.sh`](scripts/release.sh), in `chore(release)` commits — feature and fix PRs never touch `governance/assets/kit.yaml`, any bundled pack's `packs/<concern>/pack.yaml` `version`, `SKILL.md` frontmatter, `.governance/install.yaml`'s `kit_version`, or any `kit-version=` marker. The kit (framework) and the bundled packs version on **independent** semver axes. Full policy, the tag scheme (`kit/vX.Y.Z`, `core/vX.Y.Z`), and the release procedure: [governance/references/VERSIONING.md](governance/references/VERSIONING.md) and [governance/references/RELEASE_FLOW.md](governance/references/RELEASE_FLOW.md).

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

- [governance/references/PHILOSOPHY.md](governance/references/PHILOSOPHY.md) — the stance behind GDD: rules over prompts, receipts over plans, ledgers over transcripts.
- [CONSTITUTION.md](CONSTITUTION.md) — the live directive set and amendment process.
- [governance/references/DIRECTIVES_CATALOG.md](governance/references/DIRECTIVES_CATALOG.md) — every ready-made directive and its check.
- [governance/references/PACK_AUTHORING.md](governance/references/PACK_AUTHORING.md) — writing a third-party pack.
- [governance/references/NATIVE_TESTS.md](governance/references/NATIVE_TESTS.md) — porting bash directives to pytest / jest / go test, husky / pre-commit.com snippets.
- [governance/references/VERSIONING.md](governance/references/VERSIONING.md) — the two version axes (kit vs pack), the semver policy, the tag scheme, and the release procedure.
- [README.md](README.md) — the public-facing overview.

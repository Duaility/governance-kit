<!-- last-verified: 2026-06-15 -->

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

The user-facing entry point is the unified [`governance`](skill/SKILL.md) skill. **The skill is an installer; the kit is the product** (issues #194, #198): the published skill is the thin shim at [skill/](skill/) — `SKILL.md` (three lifecycle verbs plus a delegate rule) and one stdlib-only [bootstrap.py](skill/bootstrap.py) that resolves/fetches kit trees into the shared cache. It carries no kit code, no kit version, and no flow docs — everything (`pack {search,create,add,update,remove,list}`, `directive {add,modify,remove}`, `reset`, all flow docs, templates, engines) lives in the kit at [kit/](kit/) and executes from the kit version each repo pins in `install.yaml`. Both skill files are hand-authored source; nothing in `skill/` is derived. The skill is the single writer for every governance-kit lifecycle operation.

| Skill | Purpose |
|---|---|
| [governance](skill/SKILL.md) | **User-facing entry point** (published thin shim). Installer (`install`, `update`, `uninstall`); delegates `pack *`, `directive *`, `reset` to the repo-pinned kit. |

## How governance works here

This repo dogfoods its own tooling. The live directive set lives in [CONSTITUTION.md](CONSTITUTION.md); every directive — kit-bundled, community-pack, or hand-authored — lives under [.governance/packs/](.governance/packs/) at `<owner>/<name>/directives/<id>/`. Hand-authored repo-local packs (this repo's own dogfood lives at [.governance/packs/duaility/governance-kit/](.governance/packs/duaility/governance-kit/)) are just packs whose `pack.yaml` has no `source:` field.

Run the suite locally:

```sh
bash .governance/run.sh
```

Escape hatches: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` skip the local hook for hotfixes. CI re-enforces every directive on every PR — there is no developer-side bypass for CI.

### The dogfood: a protected consumer

This repo is a **normal consumer of its own product**: `.governance/` is exactly what `governance install` produces for a repo pinned at **real release tags**. The bundled concern packs (`governance-kit/{foundation,docs,commits,audit}`) are pinned in [.governance/packs.lock](.governance/packs.lock) at published `<pack>/vX.Y.Z` tags, and the vendored tree under `.governance/packs/` — plus the runtime files (`run.sh`, `lib.sh`, the hook dispatchers) — is materialized from those pins. It moves **only** in post-release `governance pack update` / `governance update` PRs, never by hand. So `.governance/` lags `packs/` and `kit/` by one release **by design**: every release thereby exercises the `update` flow.

**Do not hand-edit anything under `.governance/`.** Its integrity is guarded the way every consumer's is: the install/update verbs record a content digest of each managed unit (per-directive in `packs.lock`, per-runtime-file in `install.yaml`), and the bundled [`managed-tree-integrity`](packs/foundation/directives/managed-tree-integrity/) directive recomputes those digests on every commit — a hand-edit changes a digest and fails the check, offline, in any repo. (During the transition the repo-local `consumed-tree-integrity` directive still byte-matches the vendored tree against its pins; it is retired once `managed-tree-integrity` reaches the vendored tree at the next release.)

So: **directive and kit PRs touch `packs/` and `kit/` only** — the source trees. The committed `.governance/` consumed tree catches up at release time, via the real verb. A new or edited directive is dogfooded by its own `evals/test.sh` (run by `scripts/test.sh` in CI), so "does it break our own repo?" surfaces in the same PR without vendoring anything.

## Repo layout

```
governance-kit/
├── CONSTITUTION.md              # Directives + rationale. Edit alongside the tests.
├── README.md                    # Short public overview.
├── AGENTS.md                    # You are here.
├── skill/                       # Published thin shim — what `npx skills` installs.
│   ├── SKILL.md                 # Lifecycle verbs + delegate-to-kit rule.
│   └── bootstrap.py             # Stdlib-only fetch bootstrap (resolve/current). No kit code.
├── kit/                         # The kit artifact (tagged kit/vX.Y.Z) — the product.
│   ├── assets/                  # Templates copied into target repos.
│   │   ├── CONSTITUTION.template.md
│   │   ├── AGENTS.snippet.md
│   │   ├── governance.yml
│   │   ├── tests-bash/          # Universal bash runner shipped into every target repo.
│   │   ├── amend/               # Templates for `directive *` (directive.template.sh, directive-section.template.md).
│   │   ├── catalog.community.json   # Advisory index of known community packs (read by `governance pack search`).
│   │   ├── catalog.schema.json      # JSON Schema for catalog entries.
│   │   └── packs/lib/           # Shared pack tooling (packs.sh, install.sh, hooks.sh, …).
├── packs/                       # Kit-bundled concern packs (source of truth).
│   └── <concern>/               # foundation, docs, commits, audit
│       ├── pack.yaml            # pack id + presets
│       └── directives/
│           └── <directive-id>/  # self-contained directive folder
│               ├── directive.yaml    # per-directive metadata (judge: block if it needs a model judgment)
│               ├── check.sh          # executable test (omitted only for explicit schedule-only judges)
│               ├── constitution.md   # Directive subsection
│               └── evals/test.sh     # pass/fail fixtures
│   ├── references/              # INIT_FLOW.md, UNINSTALL_FLOW.md, RESET_FLOW.md,
│   │                            #   DIRECTIVE_AMEND_FLOW.md, SCHEDULE_FLOW.md,
│   │                            #   VERBS.md, DIRECTIVE_VERBS.md, PACK_VERBS.md,
│   │                            #   DIRECTIVES_CATALOG.md, PACK_AUTHORING.md, NATIVE_TESTS.md,
│   │                            #   DIRECTIVE_AUTHORING.md, LIB_API.md,
│   │                            #   UNINSTALL_MATRIX.md, JUDGE.md,
│   │                            #   INSTALL_SCHEMA.md, LOCK_SCHEMA.md.
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

The published skill is `skill/`: a `SKILL.md` plus a stdlib-only `bootstrap.py` (resolve a published `kit/vX.Y.Z` tag or the repo's pin, fetch it into `~/.governance/cache/kits/`, report paths, refuse offline-with-nothing-cached). Both are hand-authored source — nothing in `skill/` is derived from `kit/`, so there is no build step. Everything else — every flow doc (including the lifecycle flows), templates, references, evals, the apply engines, every version gate — lives in the kit at `kit/` and never ships with the skill; the skill reads them from the fetched/pinned kit tree at run time. The one shared contract between the two is the cache layout, locked by `scripts/test-bootstrap.py`. The skill versions independently of the kit (its frontmatter `version` is the installer's own; kit releases don't touch `skill/`).

When editing `skill/SKILL.md`, keep the `description:` frontmatter field tight — it's what determines whether the skill auto-triggers. Too generic and it fires on everything; too specific and users have to name the skill by hand. Never put an unquoted `: ` (colon-space) inside the description — it breaks YAML frontmatter parsing and `npx skills` discovery (issue #196).

### Adding or changing a governance directive

Do not edit [CONSTITUTION.md](CONSTITUTION.md) by hand. Invoke the `governance` skill's `directive *` verbs — they enforce the cardinal rule (test + constitution + evolution-log entry all land together). See [kit/references/DIRECTIVE_AMEND_FLOW.md](kit/references/DIRECTIVE_AMEND_FLOW.md).

### Adding a new directive to the catalog

Directives live inside **packs**, each at its own pack root. The kit ships four
bundled concern packs — `governance-kit/{foundation,docs,commits,audit}`,
each at `packs/<concern>/`. The kit also ships the off-commit-path,
harness-pegged scheduled lane (the `.governance/schedule.sh` driver — a
kit-managed runtime file present on every install, next to `run.sh`/`lib.sh`
— plus the `governance workflow generate` verb, which compiles every
non-empty directive-owned `SCHEDULE_CRON` into one workflow and re-adjudicates
each directive's `judge:` block independently through its author-fixed
`SCHEDULE_CMD` config — see
[kit/references/SCHEDULE_FLOW.md](kit/references/SCHEDULE_FLOW.md)), but no
longer bundles any schedule-only directives; those are authored in repo-local
or community packs (this repo dogfoods them in its repo-local
`duaility/governance-kit` pack). Community packs are authored in their own
repos and consumed by target repos via `governance pack add gh:<owner>/<repo>`;
they are not bundled here. Each directive is a self-contained folder — test,
snippet, metadata, and eval all live together under `directives/<directive-id>/`.

1. Create `<pack-root>/<pack-dir>/directives/<id>/` and populate it with:
   - `directive.yaml` — scalar fields `category`, `recommended`, `summary`,
     `surface` (`repo-state`|`change-set`), `hook`
     (`pre-commit`|`commit-msg`|`prepare-commit-msg`|`post-commit`|`pre-push`|`none`), optional
     `always_install` (reserved to the bundled `governance-kit/*` packs), and
     optional typed `config:` entries (`name`, `type`, `doc`, `default`,
     `tunable`). The manifest is the sole home for config defaults and docs.
   - `check.sh` — the bash test.
   - `constitution.md` — the Directive subsection (Directive / Rationale /
     Enforced by / Exceptions).
     The user overlay `.governance/conf/<owner>/<pack>/<id>.conf` is seeded at
     install when `config:` exists. Only entries marked `tunable: true` accept
     overlay values; environment variables are not a config tier. Read via
     `conf_get <id> <KEY> "$(dirname "$0")/directive.yaml"` or
     `conf_list <id> "$(dirname "$0")/directive.yaml" <KEY>`.
     See [kit/references/PACK_AUTHORING.md](kit/references/PACK_AUTHORING.md).
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
3. Document it in [kit/references/DIRECTIVES_CATALOG.md](kit/references/DIRECTIVES_CATALOG.md).
4. For authoring an entirely new pack, see
   [kit/references/PACK_AUTHORING.md](kit/references/PACK_AUTHORING.md).

Touch `packs/` only. Do **not** also edit the committed consumed tree under
`.governance/packs/` — that tree is materialized from released tags by
`governance pack update` in a post-release PR (see "The dogfood: a protected
consumer" above), and `managed-tree-integrity` (with `consumed-tree-integrity`
during the transition) will reject a hand-edit. Your directive's own
`evals/test.sh`, run by `scripts/test.sh` on every PR, gives the "does it break
our own repo?" signal without vendoring anything.

### Versioning & releases

Version lines are written **only** by [`scripts/release.sh`](scripts/release.sh), in `chore(release)` commits — feature and fix PRs never touch `kit/assets/kit.yaml`, any bundled pack's `packs/<concern>/pack.yaml` `version`, `SKILL.md` frontmatter, `.governance/install.yaml`'s `kit_version`, or any `kit-version=` marker. The kit (framework) and each bundled pack version on **independent** semver axes. Full policy, the tag scheme (`kit/vX.Y.Z`, per-pack `<pack>/vX.Y.Z`, cut lazily), and the release procedure: [kit/references/VERSIONING.md](kit/references/VERSIONING.md) and [kit/references/RELEASE_FLOW.md](kit/references/RELEASE_FLOW.md).

### Commit messages

Conventional Commits are enforced. Prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. A `commit-msg` hook validates the pending subject line.

### Documentation: two surfaces, one job each

The repo carries two documentation surfaces. They are **not** interchangeable — put each fact in exactly one home, and link rather than copy.

- **`kit/references/*.md` — the spec & contributor surface.** Normative runbooks the kit/agent *executes* at run time (`INIT_FLOW.md`, `UPDATE_FLOW.md`, `UNINSTALL_FLOW.md`, …), verb specs, schemas, authoring contracts, versioning policy, `PHILOSOPHY.md`. Shipped inside the kit artifact and versioned with the `kit/vX.Y.Z` tag. **This is the source of truth for *how the kit behaves*** — when the site and a reference disagree, the reference wins. Keep it operational; do not add marketing/narrative prose here.
- **`docs/` → the published site ([duaility.github.io/governance-kit](https://duaility.github.io/governance-kit)).** Human narrative: onboarding (`guide/*`), concept explainers (`concepts/*`), troubleshooting, limitations. Deployed from `main` by [docs.yml](.github/workflows/docs.yml). **This is the source of truth for *understanding and getting started*.**

The site's **Reference tab (`docs/reference/*.mdx`) is generated** from `kit/references/*.md`, so the spec is single-sourced and cannot drift: [`scripts/docs-site/gen-reference.mjs`](scripts/docs-site/gen-reference.mjs) renders each Reference page from its canonical source (run by `npm run docs:gen`, checked in CI by `npm run docs:gen:check`). Edit the `kit/references` source, never `docs/reference/*.mdx`. The narrative tabs (`guide/*`, `concepts/*`) are hand-authored and link down into `kit/references` for the authoritative spec.

Rule of thumb: a *normative claim about behavior* (a flag, a schema field, a flow step) belongs in `kit/references` (and is rendered into the site's Reference tab); a *narrative explanation* (why this matters, how to get started) belongs on the site and links down to the reference. The README is the landing page that routes to both.

## Linking the skills into a runtime

This repo's skills are made available to local agent runtimes via symlinks:

```sh
ln -s $(pwd)/skill ~/.claude/skills/governance
ln -s $(pwd)/skill ~/.codex/skills/governance
```

Edits to source files flow to both runtimes live.

## Further reading

- [kit/references/PHILOSOPHY.md](kit/references/PHILOSOPHY.md) — the stance behind GDD: rules over prompts, receipts over plans, ledgers over transcripts.
- [CONSTITUTION.md](CONSTITUTION.md) — the live directive set and amendment process.
- [kit/references/DIRECTIVES_CATALOG.md](kit/references/DIRECTIVES_CATALOG.md) — every ready-made directive and its check.
- [kit/references/PACK_AUTHORING.md](kit/references/PACK_AUTHORING.md) — writing a third-party pack.
- [kit/references/DIRECTIVE_AUTHORING.md](kit/references/DIRECTIVE_AUTHORING.md) — the craft guide for writing a good directive check.
- [kit/references/LIB_API.md](kit/references/LIB_API.md) — the canonical `lib.sh` helper API every `check.sh` can call, and the version-floor obligation.
- [kit/references/SCHEDULE_FLOW.md](kit/references/SCHEDULE_FLOW.md) — the off-commit-path judge lane (explicit `schedule` trigger, issues #142, #355), compiled into one workflow via `governance workflow generate`.
- [kit/references/JUDGE.md](kit/references/JUDGE.md) — the shared judge declaration: a directive gates a section a fresh-context sub-agent must populate, via the remediation loop (issue #272).
- [kit/references/NATIVE_TESTS.md](kit/references/NATIVE_TESTS.md) — porting bash directives to pytest / jest / go test, husky / pre-commit.com snippets.
- [kit/references/VERSIONING.md](kit/references/VERSIONING.md) — the two version axes (kit vs pack), the semver policy, the tag scheme, and the release procedure.
- [README.md](README.md) — the public-facing overview.

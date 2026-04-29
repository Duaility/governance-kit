# Authoring a governance pack

A **pack** is a self-contained bundle of governance directives that `governance-bootstrap` can discover, offer, and install into a target repo. This doc covers the layout, manifest schema, and conventions for writing one — whether you ship it in-tree under `governance/assets/packs/` (kit-bundled) or `extensions/packs/` (community-shaped, monorepo-hosted) or distribute it out-of-tree.

Read [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) first for what each existing directive does and what the surface distinction means.

## Layout

Directives are **atoms**. Each directive is a self-contained folder that owns its test, its Directive snippet, its metadata, and its eval fixtures. Nothing about a directive lives outside its folder.

```
<pack>/
├── pack.yaml                  # pack identity + presets
└── directives/
    └── <directive-id>/
        ├── directive.yaml          # per-directive metadata (category, summary, hook, …)
        ├── check.sh           # the executable test
        ├── constitution.md    # Directive subsection (Directive / Rationale / Enforced by / Exceptions)
        └── evals/
            └── test.sh        # pass + fail fixtures using eval-lib.sh
```

Adding, moving, deleting, or shipping a directive to another pack is a single `git mv` of its folder. The folder name **is** the directive id — there is no separate registry to update.

Kit-bundled packs (today: `governance-kit/core`) live under `governance/assets/packs/<pack>/`. Community-shaped packs that ship alongside the kit live under `extensions/packs/<slug>/` — `<slug>` is the slug half of a scoped `<author>/<slug>` id. Out-of-tree packs live anywhere the bootstrap skill is pointed at.

## `pack.yaml` schema

`pack.yaml` carries pack-level identity and the preset graph. Per-directive data lives in each directive's `directive.yaml`, not here.

### Pack-level fields

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Pack id. Kit-bundled packs (e.g. `governance-kit/core`) use a flat id that matches the directory name. Community packs — whether monorepo-hosted under `extensions/packs/` or out-of-tree — use a scoped id of the form `<author>/<slug>` (e.g. `duaility/agent-governance`); the validator accepts these when the slug half matches the directory name. The scoped form prevents collisions across the community catalog. |
| `name` | yes | Human label shown in the pack-selection screen. |
| `version` | yes | SemVer-ish string, e.g. `"0.1"`. Stamped into hook ownership markers. |
| `min_governance_kit` | yes | Minimum `governance-kit` version the pack depends on. Validated against the kit's built-in `KIT_VERSION` constant (`governance/assets/packs/lib/packctl.py`). Packs declaring a minimum newer than the installed kit are rejected at install. |
| `description` | yes | One-line summary of what this pack covers. |
| `author` | yes | Pack author / org. |
| `presets` | yes | See below. |

### Presets

Every pack declares three presets — `minimal`, `standard`, `strict` — even if two of them are identical. Each preset lists the directive ids it pulls in.

```yaml
presets:
  minimal:
    directives: [directive-a, directive-b]
  standard:
    extends: minimal            # union with the preset named here
    directives: [directive-c]
  strict:
    extends: standard
    directives: [directive-d, directive-e]
```

When the user picks a preset at install time, the bootstrap skill takes the **union** of that preset across every selected pack. A directive listed in a preset still respects its own `always_install` flag.

## `directive.yaml` schema

Each directive folder has a `directive.yaml` with flat scalar keys:

```yaml
category: <category-label>
recommended: true | false
summary: <one-line menu description>
surface: repo-state | change-set
hook: pre-commit | commit-msg | prepare-commit-msg | post-commit | pre-push | none
always_install: true            # optional; reserved to core
requires_hook_strategy: githooks # optional; githooks | husky | pre-commit
reads:                          # optional capability declaration
  - .github/workflows/**
  - .governance/**
writes: []                      # optional; most directives are read-only
```

| Field | Notes |
|---|---|
| `category` | Menu grouping. Canonical values: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`. Packs may introduce new categories (`duaility/agent-governance` adds `AgentDiscipline`); the skill renders each category as its own menu screen. |
| `recommended` | Pre-ticks the directive in the category menu. Presets override this per-preset. |
| `summary` | Shown next to the id in the multi-select picker. Keep it to one line. |
| `surface` | `repo-state` for directives that inspect the tree at rest; `change-set` for directives that inspect a specific commit or diff. Documented for the authoring guardrail (see DIRECTIVES_CATALOG.md). |
| `hook` | Hook kind the directive wants to run in. Drives dispatcher generation. Use `none` only if the directive runs exclusively in CI. |
| `always_install` | Reserved to `governance-kit/core`. Skips the menu. If you need an unconditionally installed directive in a third-party pack, file an issue first — the guarantee only holds for `governance-kit/core`. |
| `requires_hook_strategy` | Optional environment filter. Use this for directives whose check is only meaningful under one hook strategy — e.g. a directive asserting `.githooks/` scaffolding would declare `requires_hook_strategy: githooks` so it is skipped for husky/pre-commit.com repos. |
| `reads` / `writes` | Optional capability declaration. List of path globs the directive's `check.sh` inspects (`reads`) or mutates (`writes`) relative to the target repo root. Most directives declare a short `reads:` list and an empty `writes:` — governance directives are overwhelmingly read-only. The schema is validated at install time (each entry must be a non-empty string); semantic enforcement (refusing install when a directive reaches outside its declared bounds) is scheduled for the `governance pack add` verb. Declare capabilities now so community packs are forward-compatible. |

There is no `id`, `script`, or `constitution` field — the id is the folder name, the script is always `check.sh`, and the snippet is always `constitution.md`. Keeping the shape rigid means a new directive folder can be dropped in without editing any index.

## Directive check conventions

`check.sh` sources the shared lib and uses the standard lifecycle helpers:

```bash
#!/usr/bin/env bash
# Directive: <one-line statement>
# Rationale: <why — link an incident if there is one>
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "<directive-id>"
require_git

# ... checks ...
#   violation "path:line — message"
#   has_waiver "$file" "$line" "<directive-id>" && continue

directive_end
```

- The directive id in `directive_start` must match the folder name.
- Exit status is owned by `lib.sh`; do not call `exit` manually.
- Prefer `git grep -InE` with pathspec excludes over `find | xargs grep` — it skips binaries, respects `.gitignore`, and is portable.
- Avoid GNU-only regex features. `\b` is not portable across BSD `git grep`; use `--word-regexp` (`-w`) instead.
- When a directive's own script contains the pattern it hunts for, self-exempt via pathspec: `:!.governance/packs/<pack-id>/directives/<directive-id>/**`.
- Self-exempt the pack eval directory: `:!governance/assets/packs/*/directives/*/evals/**`. Eval fixtures deliberately contain the patterns directives look for.

## Constitution snippet

Each directive ships a markdown fragment (`constitution.md`) that becomes a `Directives` subsection in the target repo's `CONSTITUTION.md`. Four sections, in order:

```markdown
### <directive-id>

**Directive.** <one-sentence statement>

**Rationale.** <why this directive exists — ideally a specific incident or constraint>

**Enforced by.** `.governance/packs/<pack-id>/directives/<directive-id>/check.sh` (runs in `pre-commit` / `commit-msg` / `prepare-commit-msg` / `post-commit` / `pre-push` / CI only). Note that `post-commit` is **advisory-only locally** — the dispatcher prints violations but cannot reject the commit (post-commit fires after `git commit` has already succeeded). CI (`.governance/run.sh`) is the hard gate for `hook: post-commit` directives. `pre-push` blocks the push and receives the remote name as `$1`, the remote URL as `$2`, and the ref-update lines (`<local-ref> <local-sha> <remote-ref> <remote-sha>`) on stdin.

**Exceptions.** <how to waive — `governance: allow-<directive-id>` comment / env-var override / docs-only carve-out>. If none, write "None."
```

The bootstrap skill splices these in at install. Do not write a top-level `#` heading — the skill wraps them under its own section.

## Evals

Every directive ships a pass+fail eval at `directives/<directive-id>/evals/test.sh`. Evals run via `scripts/test-packs.sh` and exercise the directive end-to-end in a throwaway git fixture. The same script validates `pack.yaml` and each `directive.yaml` with PyYAML through `uv run`, so quote strings that contain YAML comment or mapping characters such as `#` and `:`.

```bash
#!/usr/bin/env bash
set -u
EVAL_ID="<directive-id>"
# directives/<directive-id>/evals/test.sh → repo root is seven levels up.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance/assets/packs/<pack>"
DIRECTIVE=".governance/packs/<pack-id>/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Pass case — fixture satisfies the directive as-is.
expect_pass "$DIRECTIVE"

# Fail case — introduce a violation.
echo "something that violates the directive" >> some-file
stage_all
EVAL_LABEL="$EVAL_ID violation" expect_fail "$DIRECTIVE"

fixture_cleanup
eval_done
```

Helpers provided by `eval-lib.sh`:

- `fixture_init` — creates a temp repo with `README.md`, `LICENSE`, `CONSTITUTION.md`, `AGENTS.md`, `ARCHITECTURE.md`, `SECURITY.md`, `.gitignore`, `.env.example`, `.github/workflows/ci.yml`, `.githooks/pre-commit`, all sized to pass the default repo-state directives.
- `install_directive <pack-dir> <directive-id>` — copies the full directive folder (everything except `evals/`) into the fixture's `.governance/packs/<pack-id>/directives/<directive-id>/`, plus the shared `lib.sh`. This picks up any sibling `lib/`, `hooks/`, or `runtimes/` the directive ships with, so atomic directives install as a unit.
- `stage_all`, `commit_quiet "<msg>"` — git helpers.
- `expect_pass <directive-path>` — runs the directive and asserts clean exit.
- `expect_fail <directive-path>` — asserts the directive reports a violation.
- `fixture_cleanup`, `eval_done` — teardown + report.

Directives with external dependencies (Python libraries, per-runtime helpers, hook side-effect scripts) should ship those files under the directive folder itself — in sibling `lib/`, `hooks/`, or `runtimes/` directories. `install_directive` copies the whole folder, so the eval picks them up automatically. This is how `agent-token-accounting` is laid out; see that directive's directory for a reference example.

## Installation flow

At activation the bootstrap skill:

1. Discovers every `pack.yaml` under its asset tree (and optional external paths).
2. Offers pack selection (`governance-kit/core` is pre-selected and locked).
3. Offers a preset (`minimal` / `standard` / `strict`) and per-category multi-selects for the remaining directives.
4. Computes `always_install ∪ preset_rules ∪ user_selections` across the selected packs.
5. Applies environment filters such as `requires_hook_strategy`.
6. Copies each selected `directives/<id>/` folder (minus `evals/`) into the target's `.governance/packs/<pack-id>/directives/<id>/`, so `check.sh`, `lib/`, `hooks/`, and `runtimes/` all land as a unit.
7. Copies optional directive-owned `install-assets/` files into the target repo without overwriting existing files in augment mode.
8. Splices each selected `directives/<id>/constitution.md` into the target's `CONSTITUTION.md`.
9. Writes `.governance/installed-packs.yaml` as an audit/debug manifest. Installed directives are still user-owned copies; the manifest is not an auto-upgrade contract.
10. Generates hook dispatchers (`pre-commit`, `commit-msg`, `prepare-commit-msg`, `post-commit`, `pre-push`) that discover installed `directive.yaml` files at runtime. Each hook carries an ownership marker (`# governance-kit:managed pack-version=<v> generated=<date>`). Pre-existing unmarked hooks trigger a collision prompt. The `post-commit` dispatcher is advisory-only — it surfaces violations to stderr but always exits 0, since `git commit` has already succeeded by the time post-commit fires. The `pre-push` dispatcher blocks the push when any wired check fails.
11. Appends an evolution-log entry in `CONSTITUTION.md`.

Re-running bootstrap is idempotent: marked hooks get overwritten silently, directive folders are copied fresh in overwrite mode or preserved in augment mode, and the evolution log records deltas.

## Versioning

Bump `version` in `pack.yaml` whenever directive semantics, ids, or the preset graph change. The hook marker only says the file is managed/regeneratable; the installed pack/directive details live in `.governance/installed-packs.yaml`. `min_governance_kit` guards against installing into an older bootstrap skill than the pack was built for.

## Testing a pack

From the `governance-kit` root:

```sh
bash scripts/test-packs.sh
```

This walks every pack, validates each directive folder, bootstraps `governance-kit/governance-kit/core.standard` into a fresh repo and runs its installed governance suite, runs every `directives/<directive>/evals/test.sh`, and smoke-tests hook generation for the union of all directives. Every directive must have at least one pass and one fail fixture; test-packs fails if an eval is missing.

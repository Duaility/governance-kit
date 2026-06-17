# Authoring a governance pack

A **pack** is a self-contained bundle of governance directives that `governance-bootstrap` can discover, offer, and install into a target repo. This doc covers the layout, manifest schema, and conventions for writing one — whether you ship it in-tree under `packs/` (kit-bundled) or distribute it out-of-tree as a community pack hosted in its own repo.

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
        ├── defaults.conf      # optional: pack-owned live defaults + their docs (refreshed on update)
        └── evals/
            └── test.sh        # pass + fail fixtures using eval-lib.sh
```

Adding, moving, deleting, or shipping a directive to another pack is a single `git mv` of its folder. The folder name **is** the directive id — there is no separate registry to update.

### Per-directive configuration

Configuration is exactly **two artifacts, one writer each** (issue #210):

- **`defaults.conf`** (pack writes) — one optional file in the directive folder carrying the live defaults **and** their documentation: `KEY=value` rows for scalar knobs, bare rows for list items (commit types, protected patterns, integrity rules), all explained by adjacent comments. It is refreshed by `pack update` / `reset`, so consumers keep receiving improved defaults *and* their docs — value and documentation can never drift apart because they ride the same file. A directive that reads any config ships one; an opt-in directive ships an all-comment `defaults.conf` (docs + examples, zero live rows).
- **the user overlay** (user writes) — `.governance/conf/<owner>/<pack>/<id>.conf`, seeded once at install (`init`, `pack add`, `directive add`) from a single generic kit stub that names the directive and points at its `defaults.conf`. Augment-only — an existing file is never overwritten, and no lifecycle verb rewrites it afterward. Nothing directive-specific is copied into user space, so nothing seeded can go stale.

The effective config is `defaults.conf` layered with the overlay: a bare line **adds** an item, `!<item>` **removes** a default (gitignore-style negation), `KEY=value` **overrides** a scalar. Read scalars with `conf_get <id> <KEY> "$(dirname "$0")/defaults.conf"` (precedence env `GOVERNANCE_<KEY>` > overlay > `defaults.conf` row — a read knob with no `defaults.conf` row fails loud) and lists with `conf_list <id> "$(dirname "$0")/defaults.conf"`; both resolve the qualified overlay path from the directive's installed location automatically. Other helpers: `conf_file`, `conf_rule_lines`. A directive that declares capabilities must list `.governance/conf/**` under `reads:`.

Kit-bundled packs are the three concern packs `governance-kit/{foundation,commits,audit}`, each under `packs/<concern>/`; the shared loader/install lib lives at `kit/assets/packs/lib/`. Out-of-tree community packs live in their own repos and are pulled in via `governance pack add gh:<owner>/<repo>`.

### Directive identity (homonyms)

A directive's identity is `<owner>/<pack>/<id>`. The short id is a *given name*, not a global claim: once a second pack exists, two packs may ship same-named directives that check different things — **they coexist and both run**. A cross-pack short-id collision is an informational notice (surfaced by `governance pack add`), not an error. To suppress another pack's directive, declare `replaces: <owner>/<pack>/<id>` (already 3-segment qualified) in your directive's `directive.yaml` — never rely on name coincidence or install order. Waiver tokens stay flat: `allow-<id>` waives the concern (every homonym of that id).

## `pack.yaml` schema

`pack.yaml` carries pack-level identity and the preset graph. Per-directive data lives in each directive's `directive.yaml`, not here.

### Pack-level fields

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Pack id. Scoped form `<author>/<slug>` (e.g. `governance-kit/foundation`, `acme/widgets`) — the slug half must match the directory name. The scoped form prevents collisions across the community catalog. |
| `name` | yes | Human label shown in the pack-selection screen. |
| `version` | yes | SemVer-ish string, e.g. `"0.1"`. Stamped into hook ownership markers. |
| `min_governance_kit` | yes | Minimum `governance-kit` version the pack depends on. Validated against the kit's built-in `KIT_VERSION` constant (`kit/assets/packs/lib/packctl.py`). Packs declaring a minimum newer than the installed kit are rejected at install. |
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
surface: repo-state | change-set | sweep
hook: pre-commit | commit-msg | prepare-commit-msg | post-commit | pre-push | none
engine: llm                     # required for (and reserved to) surface: sweep
model_tier: low | high          # required for surface: sweep — a capability tier, not a model id
standards:                      # optional; advisory standard-coverage metadata
  - "OpenSSF Scorecard: Token-Permissions"
  - "CWE-798"
always_install: true            # optional; reserved to governance-kit/* bundled packs
requires_hook_strategy: githooks # optional; githooks | husky | pre-commit
reads:                          # optional capability declaration
  - .github/workflows/**
  - .governance/**
writes: []                      # optional; most directives are read-only
```

| Field | Notes |
|---|---|
| `category` | Menu grouping. Canonical values: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`, `AgentDiscipline`. Packs may introduce new categories; the skill renders each category as its own menu screen. |
| `recommended` | Pre-ticks the directive in the category menu. Presets override this per-preset. |
| `summary` | Shown next to the id in the multi-select picker. Keep it to one line. |
| `surface` | `repo-state` for directives that inspect the tree at rest; `change-set` for directives that inspect a specific commit or diff; `sweep` for off-commit-path, LLM-adjudicated directives (issue #142). A `sweep` directive ships `triage.sh` instead of `check.sh`, sets `hook: none`, and is never run by `run.sh` or any git hook — only by the scheduled sweep engine. See [SWEEP_FLOW.md](SWEEP_FLOW.md). |
| `hook` | Hook kind the directive wants to run in. Drives dispatcher generation. Use `none` only if the directive runs exclusively in CI (or, for `surface: sweep`, off the commit path entirely). |
| `engine` | Adjudication engine. Omit for grep directives (their `check.sh` is the engine). `llm` is required for — and reserved to — `surface: sweep`. |
| `model_tier` | Required for `surface: sweep`: the *capability tier* (`low` / `high`) the judge needs, not a model id. Pinning the tier means a model upgrade within it doesn't silently rewrite the directive's verdicts. |
| `standards` | Optional advisory list of external standards the directive implements (e.g. `"OpenSSF Scorecard: Token-Permissions"`, `"CWE-798"`). Rendered as a Standards column in DIRECTIVES_CATALOG.md so coverage and gaps are visible. Not validated and never affects pass/fail. |
| `always_install` | Reserved to the `governance-kit/*` bundled packs. Skips the menu. If you need an unconditionally installed directive in a third-party pack, file an issue first — the guarantee only holds for the bundled packs. |
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

The snippet above shows only the lifecycle trio. `lib.sh` ships 14 author-facing helpers in all — file iteration (`tracked_files`), per-line and whole-file waivers (`has_waiver`, `has_file_waiver`), sub-agent attestation (`require_attestation` and friends, for correspondence-to-reality checks), and configuration (`conf_get`, `conf_list`, …). The **[helper API reference](LIB_API.md)** is the canonical list — every signature and the kit version each landed in. Call a shipped helper before hand-rolling its logic.

- The directive id in `directive_start` must match the folder name.
- Exit status is owned by `lib.sh`; do not call `exit` manually.
- Prefer `git grep -InE` with pathspec excludes over `find | xargs grep` — it skips binaries, respects `.gitignore`, and is portable.
- Avoid GNU-only regex features. `\b` is not portable across BSD `git grep`; use `--word-regexp` (`-w`) instead.
- When a directive's own script contains the pattern it hunts for, self-exempt via pathspec: `:!.governance/packs/<pack-id>/directives/<directive-id>/**`.
- Self-exempt the pack eval directory: `:!kit/assets/packs/*/directives/*/evals/**`. Eval fixtures deliberately contain the patterns directives look for.

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
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/kit/assets/packs/<pack>"
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
2. Offers pack selection (`the three bundled `governance-kit/*` packs are pre-selected and locked).
3. Offers a preset (`minimal` / `standard` / `strict`) and per-category multi-selects for the remaining directives.
4. Computes `always_install ∪ preset_rules ∪ user_selections` across the selected packs.
5. Applies environment filters such as `requires_hook_strategy`.
6. Copies each selected `directives/<id>/` folder (minus `evals/`) into the target's `.governance/packs/<pack-id>/directives/<id>/`, so `check.sh`, `lib/`, `hooks/`, and `runtimes/` all land as a unit.
7. Copies optional directive-owned `install-assets/` files into the target repo without overwriting existing files in augment mode, and seeds `.governance/conf/<id>.conf` from the generic conf stub for any directive shipping a `defaults.conf` (augment-only — an existing overlay is preserved).
8. Splices each selected `directives/<id>/constitution.md` into the target's `CONSTITUTION.md`.
9. Writes `.governance/install.yaml` (init choices + side-effect ledger) and `.governance/packs.lock` (one entry per installed pack, with `version` + `source` + optional ref/sha). Installed directives are still user-owned copies; neither file is an auto-upgrade contract.
10. Generates hook dispatchers (`pre-commit`, `commit-msg`, `prepare-commit-msg`, `post-commit`, `pre-push`) that discover installed `directive.yaml` files at runtime. Each hook carries an ownership marker (`# governance-kit:managed kit-version=<v>`) — the same shape runtime templates use. Pre-existing unmarked hooks trigger a collision prompt. The `post-commit` dispatcher is advisory-only — it surfaces violations to stderr but always exits 0, since `git commit` has already succeeded by the time post-commit fires. The `pre-push` dispatcher blocks the push when any wired check fails.
11. Appends an evolution-log entry in `CONSTITUTION.md`.

Re-running bootstrap is idempotent: marked hooks get overwritten silently, directive folders are copied fresh in overwrite mode or preserved in augment mode, and the evolution log records deltas.

## Versioning

Bump `version` in `pack.yaml` whenever directive semantics, ids, or the preset graph change. The hook marker only says the file is managed/regeneratable; the installed pack/directive details live in `.governance/packs.lock`. `min_governance_kit` guards against installing into an older bootstrap skill than the pack was built for.

**Floor `min_governance_kit` at the newest `lib.sh` helper any directive calls.** The helpers live in kit-owned `lib.sh`, so a directive that calls one is only correct on a kit new enough to define it. Read each helper's landed-in version from the **Since** column of the [helper API reference](LIB_API.md#version-floor-obligation) and set `min_governance_kit` to the highest one your pack uses. This is harmless to ignore for the kit's own bundled packs (the dogfood always runs the latest kit) but a **silent breakage for a community pack** shipped to arbitrary kit versions: e.g. a directive calling `require_attestation` (kit `0.9`) while flooring at `0.5` installs cleanly into a `0.5`–`0.8` kit, then fails at commit time with `require_attestation: command not found`. The `governance-kit/audit` pack floors at `0.9.0` for exactly this reason.

## Testing a pack

From the `governance-kit` root:

```sh
bash scripts/test-packs.sh
```

This walks every pack, validates each directive folder, bootstraps the unioned `standard` preset into a fresh repo and runs its installed governance suite, runs every `directives/<directive>/evals/test.sh`, and smoke-tests hook generation for the union of all directives. Every directive must have at least one pass and one fail fixture; test-packs fails if an eval is missing.

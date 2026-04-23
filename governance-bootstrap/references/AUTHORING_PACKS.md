# Authoring a governance pack

A **pack** is a self-contained bundle of governance rules that `governance-bootstrap` can discover, offer, and install into a target repo. This doc covers the layout, manifest schema, and conventions for writing one — whether you ship it in-tree alongside `core` / `agent-governance` or distribute it out-of-tree.

Read [RULES_CATALOG.md](RULES_CATALOG.md) first for what each existing rule does and what the surface distinction means.

## Layout

```
<pack>/
├── pack.yaml                  # manifest — fields below
├── rules/
│   └── <rule-id>.sh           # rule scripts; filename == rule id
├── constitution-snippets/
│   └── <rule-id>.md           # Invariant subsection (Rule / Rationale / Enforced by / Exceptions)
└── evals/
    └── <rule-id>/
        └── test.sh            # pass + fail fixtures using eval-lib.sh
```

One rule script ↔ one constitution snippet ↔ one eval directory, all sharing the same `<rule-id>`. The id must match the filename without `.sh`.

In-tree packs live under `governance-bootstrap/assets/packs/<pack>/`. Out-of-tree packs live anywhere the bootstrap skill is pointed at.

## `pack.yaml` schema

### Pack-level fields

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Pack slug. Must match the directory name. Unique across all packs installed into a single target repo. |
| `name` | yes | Human label shown in the pack-selection screen. |
| `version` | yes | SemVer-ish string, e.g. `"0.1"`. Stamped into hook ownership markers. |
| `min_governance_kit` | yes | Minimum `governance-kit` version the pack depends on. |
| `description` | yes | One-line summary of what this pack covers. |
| `author` | yes | Pack author / org. |
| `presets` | yes | See below. |
| `rules` | yes | Array of rule entries. |

### Presets

Every pack declares three presets — `minimal`, `standard`, `strict` — even if two of them are identical. Each preset lists the rule ids it pulls in.

```yaml
presets:
  minimal:
    rules: [rule-a, rule-b]
  standard:
    extends: minimal            # union with the preset named here
    rules: [rule-c]
  strict:
    extends: standard
    rules: [rule-d, rule-e]
```

When the user picks a preset at install time, the bootstrap skill takes the **union** of that preset across every selected pack. A rule listed in a preset still respects its own `always_install` flag.

### Rule entries

```yaml
rules:
  - id: <rule-id>
    category: <category-label>
    recommended: true | false
    summary: <one-line menu description>
    script: rules/<rule-id>.sh
    constitution: constitution-snippets/<rule-id>.md
    surface: repo-state | change-set
    hook: pre-commit | commit-msg | prepare-commit-msg | none
    always_install: true        # optional; see below
```

| Field | Notes |
|---|---|
| `id` | Filename of the rule script without `.sh`. Must be unique across all packs installed into the same target. |
| `category` | Menu grouping. Canonical values: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`. Packs may introduce new categories (`agent-governance` adds `AgentDiscipline`); the skill renders each category as its own menu screen. |
| `recommended` | Pre-ticks the rule in the category menu. Presets override this per-preset. |
| `summary` | Shown next to the id in the multi-select picker. Keep it to one line. |
| `script` | Relative path inside the pack. |
| `constitution` | Relative path to the Invariant snippet spliced into `CONSTITUTION.md` at install. |
| `surface` | `repo-state` for rules that inspect the tree at rest; `change-set` for rules that inspect a specific commit or diff. Documented for the authoring guardrail (see RULES_CATALOG.md). |
| `hook` | Hook kind the rule wants to run in. Drives dispatcher generation. Use `none` only if the rule runs exclusively in CI. |
| `always_install` | Reserved to `core`. Skips the menu. If you need an unconditionally installed rule in a third-party pack, file an issue first — the guarantee only holds for `core`. |

## Rule script conventions

Every rule sources the shared lib and uses the standard lifecycle helpers:

```bash
#!/usr/bin/env bash
# Rule: <one-line statement>
# Rationale: <why — link an incident if there is one>
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "<rule-id>"
require_git

# ... checks ...
#   violation "path:line — message"
#   has_waiver "$file" "$line" "<rule-id>" && continue

rule_end
```

- The rule id in `rule_start` must match the filename.
- Exit status is owned by `lib.sh`; do not call `exit` manually.
- Prefer `git grep -InE` with pathspec excludes over `find | xargs grep` — it skips binaries, respects `.gitignore`, and is portable.
- Avoid GNU-only regex features. `\b` is not portable across BSD `git grep`; use `--word-regexp` (`-w`) instead.
- When a rule's own script contains the pattern it hunts for, self-exempt via pathspec: `:!tests/governance/rules/<rule-id>.sh`.
- Self-exempt the pack eval directory: `:!governance-bootstrap/assets/packs/*/evals/**`. Eval fixtures deliberately contain the patterns rules look for.

## Constitution snippets

Each rule ships a markdown fragment that becomes an `Invariants` subsection in the target repo's `CONSTITUTION.md`. Four sections, in order:

```markdown
### <rule-id>

**Rule.** <one-sentence statement>

**Rationale.** <why this rule exists — ideally a specific incident or constraint>

**Enforced by.** `tests/governance/rules/<rule-id>.sh` (runs in `pre-commit` / `commit-msg` / `prepare-commit-msg` / CI only).

**Exceptions.** <how to waive — `governance: allow-<rule-id>` comment / env-var override / docs-only carve-out>. If none, write "None."
```

The bootstrap skill splices these in at install. Do not write a top-level `#` heading — the skill wraps them under its own section.

## Evals

Every rule ships a pass+fail eval under `evals/<rule-id>/test.sh`. Evals run via `scripts/test-packs.sh` and exercise the rule end-to-end in a throwaway git fixture.

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib/eval-lib.sh" && pwd)/eval-lib.sh"

fixture_init                                # temp git repo with baseline docs + empty governance harness
install_rule core <rule-id>                 # copies rules/<rule-id>.sh + lib.sh into tests/governance/rules/

# Pass case — fixture satisfies the rule as-is.
expect_pass

# Fail case — introduce a violation.
echo "something that violates the rule" >> some-file
stage_all
expect_fail <rule-id>

fixture_cleanup
eval_done
```

Helpers provided by `eval-lib.sh`:

- `fixture_init` — creates a temp repo with `README.md`, `LICENSE`, `CONSTITUTION.md`, `AGENTS.md`, `ARCHITECTURE.md`, `SECURITY.md`, `.gitignore`, `.env.example`, `.github/workflows/ci.yml`, `.githooks/pre-commit`, all sized to pass the default repo-state rules.
- `install_rule <pack> <rule-id>` — copies the rule script and `lib.sh` into the fixture's `tests/governance/rules/`.
- `stage_all`, `commit_quiet "<msg>"` — git helpers.
- `expect_pass` — runs `tests/governance/run.sh` and asserts clean exit.
- `expect_fail <rule-id>` — asserts the named rule reports a violation.
- `fixture_cleanup`, `eval_done` — teardown + report.

Fixtures that need baseline files differ from the default — e.g. a rule that requires Python libraries under `scripts/governance/lib/` — should copy what they need from the pack asset tree rather than inlining content.

## Installation flow

At activation the bootstrap skill:

1. Discovers every `pack.yaml` under its asset tree (and optional external paths).
2. Offers pack selection (`core` is pre-selected and locked).
3. Offers a preset (`minimal` / `standard` / `strict`) and per-category multi-selects for the remaining rules.
4. Computes `always_install ∪ preset_rules ∪ user_selections` across the selected packs.
5. Copies each selected `rules/<id>.sh` into the target's `tests/governance/rules/`.
6. Splices each selected `constitution-snippets/<id>.md` into the target's `CONSTITUTION.md`.
7. Generates hook dispatchers (`pre-commit`, `commit-msg`, `prepare-commit-msg`) containing only the selected rules, keyed off their `hook:` declarations. Each hook carries an ownership marker (`# governance-kit:managed pack-version=<v> generated=<date>`). Pre-existing unmarked hooks trigger a collision prompt.
8. Appends an evolution-log entry in `CONSTITUTION.md`.

Re-running bootstrap is idempotent: marked hooks get overwritten silently, rule scripts are copied fresh, and the evolution log records deltas.

## Versioning

Bump `version` in `pack.yaml` whenever rule semantics, ids, or the preset graph change. The version gets stamped into the hook ownership marker so operators can audit which pack version is live in a given repo. `min_governance_kit` guards against installing into an older bootstrap skill than the pack was built for.

## Testing a pack

From the `governance-kit` root:

```sh
bash scripts/test-packs.sh
```

This walks every pack, validates manifests, runs every `evals/<rule>/test.sh`, and smoke-tests hook generation for the union of all rules. Every rule must have at least one pass and one fail fixture; test-packs fails if an eval is missing.

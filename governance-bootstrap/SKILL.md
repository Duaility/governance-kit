---
name: governance-bootstrap
description: Bootstraps governance-driven development in a repository that does not yet have the kit installed — scaffolds an initial CONSTITUTION.md, a test suite under tests/governance/ that enforces it, tracked git hooks, and a GitHub Actions workflow. Ships with rule packs — `core` (Conventional Commits, secret scanning, .env hygiene, GitHub Actions hardening, AGENTS.md / ARCHITECTURE.md / SECURITY.md checks, broken-link detection, doc freshness, merge-conflict-marker detection) and `agent-governance` (plan-per-issue, commit-issue-plan-match, issues-tracked, agent-token-accounting for repos under agent-driven development). Users pick packs, a preset (minimal/standard/strict/custom), and then customize per-category. Use when the user wants initial governance setup, says "bootstrap governance", "set up governance tests", or wants to install this governance kit into a repo. Do not use for amending an existing rule set; use governance-amend for that.
license: MIT
metadata:
  author: governance-kit
  version: "0.2"
---

# governance-bootstrap

This skill sets up **governance-driven development** in the current repository:

1. A `CONSTITUTION.md` at the repo root — the evolving source of truth for rules, guidelines, and invariants.
2. Machine-enforced tests under `tests/governance/` — every rule in the constitution has a corresponding test.
3. A pre-commit hook (and commit-msg / prepare-commit-msg dispatchers when the selected rules need them) — runs `tests/governance/` before commits, with `SKIP_GOVERNANCE=1` and `git commit --no-verify` as escape hatches.
4. A GitHub Actions workflow at `.github/workflows/governance.yml` — same tests, enforced in CI on every PR.

Rules are grouped into **packs** — self-contained directories under `assets/packs/` that bundle rules, their constitution snippets, and hook declarations. Two packs ship in-tree today:

- **`core`** — the baseline rules every repo gets by default.
- **`agent-governance`** — the agent-driven-development rules this kit dogfoods (opt-in for other repos).

Governance evolves: new rules get added to `CONSTITUTION.md` *and* to `tests/governance/` together. The constitution without the tests is just a wishlist.

## Negative triggers

Do **not** use this skill for these requests:

- "Review our constitution" or "is this governance any good?" — answer the question directly or use `governance-gardener`.
- "Add one new rule" or "change the file-size limit" — use `governance-amend`.
- "Run a governance health check" or "find dead rules" — use `governance-gardener`.
- "What does this invariant mean?" — explain the current setup; do not bootstrap.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop and tell the user bootstrap requires git. |
| Repo already has governance artifacts and the user asked for setup | Continue in augment/overwrite mode; default to augment. |
| Repo already has governance artifacts and the user asked for review, explanation, or one targeted change | Do not bootstrap. Answer directly or redirect to `governance-amend` / `governance-gardener`. |
| Multiple plausible primary stacks exist | Ask once. If no answer is available, fall back to bash-first generic setup and label it as an assumption. |
| Hook framework is unclear | Infer from tracked files. If still unclear, assume `.githooks/` and label that as an assumption. |
| Structured question tools are unavailable | Ask concise free-text questions, then proceed with defaults if the user does not provide more detail. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Survey the repository

Before touching anything, run these in parallel:

- `git rev-parse --show-toplevel` to confirm this is a git repo and find the root.
- `ls -la` at the root.
- Check for stack markers: `package.json`, `pyproject.toml`, `setup.py`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`.
- Check for existing `CONSTITUTION.md`, `tests/governance/`, `.github/workflows/governance.yml`, `.githooks/`, and `.git/hooks/pre-commit` (legacy location — flag if present).

If this is not a git repo, stop and tell the user — governance-bootstrap requires git.

If artifacts already exist, report what's there and ask whether to **augment** (add missing pieces, preserve existing) or **overwrite** (fresh start). Default to augment.

Also detect hook strategy before you offer or install hook-related rules:
- If `.husky/` exists, `package.json` references husky, or `.pre-commit-config.yaml` exists, treat the repo as using an existing hook framework.
- Otherwise, use the repo-local `.githooks/` strategy described below.

This choice affects whether `hooks-configured` is installed. Do not present `.githooks/` as universal if the repo already has a tracked hook framework.

**Hook-collision survey.** As part of the survey, inspect existing hook files at:

| Location | What to look for |
|---|---|
| `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/prepare-commit-msg` | grep for the ownership marker `governance-kit:managed` |
| `.git/hooks/*` | same marker (legacy path — flag even if marker is found) |
| `.husky/*`, `.pre-commit-config.yaml` | signals Path B below, not a collision |

Record findings for use at Step 6.

### Step 2 — Classify the project stack

Pick exactly one primary stack from the markers:

| Marker                              | Stack     | Test runner                  |
| ----------------------------------- | --------- | ---------------------------- |
| `pyproject.toml` / `requirements.txt` | python    | pytest                       |
| `package.json`                      | node      | detect jest / vitest / node  |
| `go.mod`                            | go        | `go test`                    |
| `Cargo.toml`                        | rust      | `cargo test`                 |
| none of the above                   | generic   | bash                         |

Multiple markers → pick the one the user points to. If unclear, ask once.

**Default** for every stack: also install the universal **bash** test runner from `assets/tests-bash/`. Bash tests are language-agnostic (grep/find/wc based) and work anywhere. The native test runner is a second, stack-idiomatic copy that lets governance rules integrate with the project's normal test command. The user picks in Step 3 whether to install native tests, bash tests, or both.

### Step 2.5 — Discover rule packs

Source the loader and enumerate packs:

```sh
source governance-bootstrap/assets/packs/lib/packs.sh
list_packs governance-bootstrap/assets/packs
```

The loader is a bash wrapper around `uv run --isolated --with PyYAML`, so pack
manifests are parsed as real YAML. If `uv` is unavailable, stop and tell the
user pack discovery requires `uv` (or install it before continuing).

Every `assets/packs/<pack-id>/pack.yaml` is a pack. Rule metadata lives inside each rule's folder (`assets/packs/<pack-id>/rules/<rule-id>/rule.yaml`) — the loader surfaces it via `rules_for` and `rule_field`. For each pack, build an in-memory catalog of:

- pack id, name, description, version (from `pack.yaml`)
- declared presets (`minimal`, `standard`, `strict`, plus any pack-specific ones — from `pack.yaml`)
- rule list; for each rule read `category`, `recommended`, `summary`, `surface`, `hook`, `always_install` from `rules/<rule-id>/rule.yaml`. The check script is at `rules/<rule-id>/check.sh` and the Invariant snippet at `rules/<rule-id>/constitution.md` — paths are implied by the folder shape, not declared.

No env var or CLI flag controls pack selection in v1 — discovery is in-tree only.

### Step 3 — Choose packs, preset, and customize

Three nested questions. Each subsequent question's option list is computed from the prior answer.

**Q0 — "Which rule packs do you want?"** — multiselect.

- `core` (always included, non-deselectable — present it as pre-checked with a note).
- Every other pack discovered in Step 2.5, with its description from the manifest.

**Q1 — "Which preset?"** — single-select.

| Preset | Intent |
|---|---|
| `minimal` | Smallest credible governance baseline. |
| `standard` | Recommended default for most repos. |
| `strict` | Broad governance coverage for teams that want more structure. |
| `custom` | Start from a blank slate — no preselected rules beyond the always-installed set. |

**Semantics across packs: union.** The preset resolves as the union of the preset's rule ids across the selected packs:

```
preset_rules = ⋃ { union_preset(<preset>, <pack-dir>) : pack-dir in selected-packs }
```

A pack that does not declare the chosen preset (for example, `agent-governance` has no `strict` preset that adds new rules) contributes nothing for that preset — **no fallback to `recommended`**. This is deliberate: "my pack has no strict" means "strict adds nothing beyond what I already offer", not "give me everything".

Use `standard` as the recommended preset. If the user does not answer and you must proceed, assume `standard` and label it in the final summary as a material assumption.

**Q2..Qn — Category menus.** For each category present across the union of selected packs' rules (canonical: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`; `agent-governance` adds `AgentDiscipline`; third-party packs may add more), present one `AskUserQuestion` with:

- Header: the category name.
- Options: every rule in that category from any selected pack. Pre-check based on the preset union from Q1. Each option's description is the rule's `summary` field from its manifest.
- `multiSelect: true`.

Split into multiple `AskUserQuestion` calls — the tool caps at four questions per call. Follow the same pattern today's flow does: first call for Foundation / Security / SystemOfRecord / CommitHygiene; second call for Quality / AgentDiscipline / any additional categories. Category menus with only a single rule are fine — do not pad with filler.

If the user picks "Other" and describes a new rule, generate a new rule folder under `tests/governance/rules/<id>/` with `rule.yaml`, `check.sh`, and `constitution.md`, following the template in `references/RULES_CATALOG.md`, and add a matching Invariants subsection to `CONSTITUTION.md`. The rule joins the target repo directly; it is not retrofitted into a pack (that is a pack-authoring activity, covered in `references/AUTHORING_PACKS.md`).

**Always installed — bypass the menu.** Walk every selected pack's `always_install: true` rules and queue them for install regardless of user picks. This flag is **reserved to the `core` pack**; third-party packs declaring it are rejected at install. Today only `no-merge-conflict-markers` carries the flag. Apply each rule's optional `requires_hook_strategy:` filter after preset resolution; `hooks-configured` declares `requires_hook_strategy: githooks`, so it is installed only when the repo is using the `.githooks/` strategy.

**Install resolution.** The final install list is:

```
install = always_install_core
       ∪ preset_rules (from Q1)
       ∪ user_selected_rules (from Q2..Qn, which may add or remove items)
```

If two selected packs list the same rule `id`, reject with a clear error before touching the filesystem. The target repo's rule namespace is flat by folder name (`tests/governance/rules/<id>/`), so collisions there would be silent overwrites.

Before installing, classify any user-described custom rule by surface:

| Policy surface | Use when the intent is | Preferred enforcement shape |
|---|---|---|
| `repo-state` | "the repo must contain / must not contain X" | Existence, content, pattern, metric, or structural check over tracked files |
| `change-set obligation` | "every substantive change must also do X" | Staged-diff check locally plus branch-diff check in CI |

Ask this explicitly whenever the user requests a custom rule or a rule whose rationale sounds per-change:

> What bad merge are we trying to block: a repo missing something at rest, or a substantive change landing without its required companion update?

Do not accept a repo-exists proxy for a change-set obligation unless you explicitly tell the user it is only a weak approximation and they approve that tradeoff.

For each rule in the final install list, use `assets/packs/lib/install.sh`:

- `install_rule_folder <pack-dir> <rule> <repo-root>` copies `<pack-dir>/rules/<rule>/` into `tests/governance/rules/<rule>/`, excluding `evals/`, and marks `check.sh` plus rule-owned hooks/runtimes executable.
- `install_rule_assets <pack-dir> <rule> <repo-root>` copies optional `install-assets/` files into the target repo without overwriting existing files in augment mode. This is how rules such as `issues-tracked` seed `QUALITY.md` and `agent-token-accounting` seeds `COSTS.md`.
- If the user selects `doc-freshness`, also copy `assets/freshness.conf` to `tests/governance/freshness.conf` (the seed file is commented — every path is opt-in by uncommenting; `governance-gardener` complements it with a built-in baseline).

After all rules are installed, write `.governance-kit/installed-packs.yaml` via `write_installed_manifest`. Pass every flag that applies to the install — `governance-reset` treats this file as the authoritative record of what the kit owns and will key off every field:

```sh
write_installed_manifest "$repo_root" \
    --hook-strategy githooks \
    --stack bash \
    --ci-workflow .github/workflows/governance.yml \
    --tests-dir tests/governance \
    --agents-md-directive \                # add --agents-md-created if Step 4b Case 2 fired
    --install-asset QUALITY.md \           # repeat per seeded install-asset
    --install-asset COSTS.md \
    --collision .githooks/pre-commit:wrap:.githooks/pre-commit.userhook \  # only if Step 6 hit collisions
    -- \
    "$core_pack_dir" constitution-exists \
    "$core_pack_dir" no-secrets \
    "$agent_pack_dir" agent-token-accounting
```

`--install-asset` is repeatable (once per seeded file — `install_rule_assets` copied it). `--collision` is `path:resolution[:extra]` where `resolution` ∈ `wrap | skip | overwrite-with-backup` and `extra` is the userhook or `.bak` path. `--path-b-framework` + `--path-b-entry <file>:<fingerprint>` replace `--hook-strategy githooks` when bootstrap took Path B. Omit `--no-constitution` unless the user explicitly asked to skip the constitution (nonstandard). The manifest is `version: "1"`; installed rule folders are still user-owned copies and this file is not an auto-upgrade contract.

### Step 4 — Write the constitution

Copy `assets/CONSTITUTION.template.md` to `<repo-root>/CONSTITUTION.md`. Then tailor it:

- The template ships with a **Compliance** section directly under the cardinal-rule callout — leave it intact. Every bootstrapped repo gets it.
- Fill the **Principles** section with 3-5 high-level principles inferred from the rules the user picked, plus a generic starter like "Changes to the constitution require changes to the enforcing tests."
- Under **Invariants**, for each rule in the final install list, read the rule's Invariant subsection snippet (`<pack-dir>/rules/<rule>/constitution.md`) and splice it verbatim into the **Invariants** section. Every snippet is already in the standard Rule / Rationale / Enforced by / Exceptions shape — do not rewrite.
- Leave the **Evolution Log** section with a template entry and a note that each amendment needs a commit.

Do not invent principles the user did not pick. It is better to ship a short constitution than a bloated one. If you had to infer anything material — stack, preset, or hook strategy — record it under `Assumptions:` in the final summary. If you install any custom or change-set-aware rule, make sure the invariant text says what merge it blocks, not just what file shape it checks.

### Step 4b — Inject the Compliance directive into AGENTS.md

The constitution's **Compliance** section is the rule; the AGENTS.md directive is the routing pointer that tells agents to *read* the rule. Without it, agents may never reach the constitution. Inject `assets/AGENTS.directive.md` into the target repo's `AGENTS.md`.

The snippet is bounded by a pair of HTML marker comments — opening `<!-- governance: rules-to-follow -->` on its first line and closing `<!-- /governance: rules-to-follow -->` on its last. Both markers ship together in the template and **both** must be preserved on insert. Idempotency: grep for the opening marker before inserting; if it is already present, skip silently. Do not insert the opening without the closing or vice versa — `governance-reset` relies on the pair to locate the exact block to strip.

Three cases:

1. **`AGENTS.md` exists and lacks the marker.** Insert the snippet near the top of the file. The right insertion point is **after the H1 heading and the first intro paragraph (or any frontmatter), and before the first `##` heading**. Use `Edit` — preserve everything else verbatim.

2. **`AGENTS.md` is missing AND the user picked the `agents-md-exists` rule.** Create a stub at `<repo-root>/AGENTS.md` containing: `# AGENTS.md`, a one-line intro, the directive snippet, and a `## What this repo is` placeholder. Tell the user the stub is intentionally minimal — they need to flesh it out (the rule requires 30–250 lines and ≥ 3 internal doc links).

3. **`AGENTS.md` is missing AND the user did NOT pick `agents-md-exists`.** Skip silently. Do not nag — the user opted out of the rule, and creating a file they didn't ask for is presumptuous.

After injecting, run `bash tests/governance/rules/agents-md-exists/check.sh` once if the rule is installed, so the user knows whether the file still needs more content.

### Step 5 — Install the test runner

Copy `assets/tests-bash/run.sh` to `tests/governance/run.sh` and mark it executable (`chmod +x`). This is the entrypoint — it discovers and runs every `rules/<id>/check.sh`, prints a summary, and exits non-zero on any failure.

Copy `assets/tests-bash/lib.sh` to `tests/governance/lib.sh` — shared helpers (pass/fail/skip output, `tracked_files` helper that respects `.gitignore`).

If the user wants **native** tests in addition to bash, read `references/NATIVE_TESTS.md` for the port pattern for their stack (pytest / jest / go test). Generate the native test file(s) inline — do not invent a separate `run.sh` for the native side; the project's existing test runner (`pytest tests/governance`, `npx jest tests/governance`, `go test ./tests/governance/...`) is the entrypoint.

### Step 6 — Install the git hooks

Hooks are **generated**, not copied. Use `assets/packs/lib/install.sh` to build a hook spec from the installed rule folders, then pass that spec to `assets/packs/lib/hooks.sh`:

```sh
build_hook_spec_from_installed_rules <repo-root> /tmp/governance-hook-spec.tsv
generate_hooks <repo-root>/.githooks <pack-version-label> /tmp/governance-hook-spec.tsv
```

The generator:

1. Emits all three dispatchers — `pre-commit`, `commit-msg`, `prepare-commit-msg` — so future user-owned amendments that add a compatible `hook:` declaration are discovered without regenerating hooks.
2. Each dispatcher scans installed `tests/governance/rules/<id>/rule.yaml` at runtime, runs rule-owned `hooks/<kind>.sh` helpers first, then runs `check.sh` for rules whose `hook:` matches the dispatcher. Dispatchers honor `SKIP_GOVERNANCE=1`.
3. Stamps each dispatcher with a **line-2 ownership marker**:
   ```sh
   #!/usr/bin/env bash
   # governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>
   ```
   The `pack-version` marker is an ownership/regeneration marker, not an upgrade promise; installed pack/rule details live in `.governance-kit/installed-packs.yaml`.

Path choice:

**Path A — repo-local `.githooks/`** (default when no other framework is present).

1. Generate `.githooks/pre-commit`, `.githooks/commit-msg`, and `.githooks/prepare-commit-msg`.
2. `chmod +x` every generated hook.
3. Install `hooks-configured` (copy `<core-pack-dir>/rules/hooks-configured/` into `tests/governance/rules/hooks-configured/`, excluding `evals/`).
4. Run `git config core.hooksPath .githooks`. **Tell the user explicitly** that this config is per-clone — every other contributor must run the same command after their first clone. The `hooks-configured` rule will surface that requirement on every commit until they do.
5. **Do not** create files under `.git/hooks/`. If `.git/hooks/pre-commit` (or `commit-msg`) already exists from a previous bootstrap or another tool, ask the user before deleting — it could be a husky or pre-commit.com hook (see Path B).

**Pre-existing hook collision (unmarked).** If the survey in Step 1 found a target hook that exists and lacks the ownership marker, STOP before writing. Show the user the existing hook and offer three options:

1. **Wrap** (default) — write the generated hook, rename the existing one to `<name>.userhook`, and exec it at the end of the generated hook. Keeps both behaviors.
2. **Merge by hand** — print both scripts, skip hook install, rely on CI.
3. **Overwrite + backup** — back up the existing hook to `<path>.pre-governance.bak`, then write ours. Warn in the final summary.

If the existing hook **has** the marker, overwrite silently — `governance-amend` relies on this. (The marker is a contract: "this file is regeneratable.")

**Path B — existing hook framework.** If the project uses `husky` or the `pre-commit` framework, *do not* set `core.hooksPath` and do not copy into `.githooks/` — those frameworks already have their own tracked hook-config mechanism. Instead, add a hook entry to the existing config (ask the user which framework they use, or infer it from the files you found). See `references/NATIVE_TESTS.md` for the husky / pre-commit.com snippets.

In this path:
- Do not install the `hooks-configured` rule folder.
- Do not describe `hooks-configured` as part of the constitution.
- Tell the user explicitly that the repo is using its existing tracked hook framework instead of `.githooks/`.

### Step 7 — Install the CI workflow

Copy `assets/governance.yml` to `.github/workflows/governance.yml`. Adjust the test-runner step based on the stack chosen in Step 2. The workflow runs on `push` to `main` and on every `pull_request`, and it never skips — CI is the backstop the pre-commit hook can be bypassed around.

### Step 8 — Report to the user

Print a concise summary:
- Packs selected.
- Preset chosen and whether it was explicit or assumed.
- Hook strategy chosen (`.githooks/`, husky, or `pre-commit`).
- Stack detected.
- Rules installed (with file paths, grouped by pack if multiple packs were selected).
- Rules deliberately skipped (with reasons) when that matters.
- Any pre-existing hook collisions encountered and how they were resolved.
- How to run locally: `bash tests/governance/run.sh`.
- How to skip the hook: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`.
- Assumptions made. If none, say `Assumptions: none`.
- Reminder: **constitution amendments must land with their test.** Point to `references/RULES_CATALOG.md` and (if multiple packs were selected) `references/AUTHORING_PACKS.md` for the templates.

Do **not** commit the new files. Leave that to the user — the first commit of their governance system should be intentional, and the pre-commit hook is now active.

## Required final output

Every successful run should leave the user with a summary that includes:

- `Packs:` the list of selected packs.
- `Preset:` chosen preset and whether it was explicit or assumed.
- `Hook strategy:` `.githooks/`, husky, or `pre-commit`.
- `Rules installed:` file-backed list or grouped summary.
- `Rules skipped:` only when the omission is meaningful.
- `Hook collisions:` the resolution chosen for each pre-existing unmarked hook, or `none`.
- `Assumptions:` any material assumptions, or `none`.
- `Next command:` `bash tests/governance/run.sh`

---

## Key design rules for this skill

- **The constitution and the tests evolve together.** Never add a rule to the constitution without a test. Never add a test without a rule. If the user asks to add one in isolation, push back and do both.
- **Packs are the extension point.** Adding a rule to a pack is a two-file edit (the `.sh` + the manifest entry); every menu, hook dispatcher, and constitution snippet flows from the manifest. Do not shadow the manifest with hand-written lists in SKILL.md.
- **`core` is non-optional.** Users can select additional packs but cannot deselect `core`. The `always_install: true` flag is reserved to `core` — third-party packs cannot force-install rules.
- **Preset semantics are union, not fallback.** If a pack lacks the selected preset, it contributes nothing for that preset.
- **Escape hatches are a feature, not a bug.** `SKIP_GOVERNANCE=1` exists because governance that blocks emergency hotfixes will get ripped out. CI enforces the rule even when the hook is skipped, which is the right layering.
- **Bash-first, native as enhancement.** Bash tests work in any repo, in any CI, without install steps. Native tests (pytest etc.) are nicer DX but add friction. Default to bash; offer native.
- **Respect the repo's existing hook framework.** `.githooks/` is the default only when no tracked hook framework already exists. Do not force repos off husky or `pre-commit`.
- **Hook ownership is explicit.** Every generated hook carries the `governance-kit:managed` marker on line 2. An unmarked hook at a target path is somebody else's file — prompt before touching it.
- **Match the enforcement surface to the real intent.** If a rule is meant to govern each substantive change, do not implement it as a repo-exists or file-count check.
- **Reject weak proxies when they create false confidence.** A rule that says "every change must do X" but only checks "the repo contains one X somewhere" is a bad bootstrap output, not a partial success.
- **State material assumptions explicitly.** If you had to infer the preset, stack, or hook strategy, surface that in the summary.
- **No invented rules.** When writing the constitution, only include rules the user selected. Governance loses authority the moment it contains rules nobody signed off on.

## References

- `../GOVERNANCE_VOCABULARY.md` — shared terms used across the three governance skills.
- `references/RULES_CATALOG.md` — full list of ready-made rules with descriptions, and the template for adding new ones. Notes pack membership per rule.
- `references/AUTHORING_PACKS.md` — how to write a third-party pack.
- `references/NATIVE_TESTS.md` — how to port bash rules to pytest / jest / go test, and husky / pre-commit-framework snippets.
- `references/AGENT_TOKEN_ACCOUNTING.md` — wiring instructions for the `agent-token-accounting` rule shipped by the `agent-governance` pack.

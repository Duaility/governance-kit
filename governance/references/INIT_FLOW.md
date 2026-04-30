# `governance init` — activation flow

The 8-step recipe `governance init` runs. Dispatched from
[`../SKILL.md`](../SKILL.md).

`init` sets up governance-driven development in the current repository:

1. A `CONSTITUTION.md` at the repo root — the evolving source of truth for directives, guidelines, and directives.
2. Machine-enforced tests under `.governance/` — every directive in the constitution has a corresponding test.
3. A pre-commit hook (and commit-msg / prepare-commit-msg / post-commit / pre-push dispatchers when the selected directives need them) — runs `.governance/` before commits and pushes, with `SKIP_GOVERNANCE=1` and `git commit --no-verify` / `git push --no-verify` as escape hatches.
4. A GitHub Actions workflow at `.github/workflows/governance.yml` — same tests, enforced in CI on every PR.

Directives are grouped into **packs** — self-contained directories that bundle directives, their constitution snippets, and hook declarations. One pack ships in-tree today:

- **`governance-kit/core`** at `governance/assets/packs/core/` — the baseline directives plus the agent audit chain (`receipt-per-issue` → `commit-issue-receipt-match` → `issue-templates` → `issues-tracked` → `agent-token-accounting`) and the opt-in `agent-steering-accounting`.

Governance evolves: new directives get added to `CONSTITUTION.md` *and* to `.governance/` together. The constitution without the tests is just a wishlist.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop and tell the user `governance init` requires git. |
| Repo already has governance artifacts and the user asked for setup | Continue in augment/overwrite mode; default to augment. |
| Repo already has governance artifacts and the user asked for review, explanation, or one targeted change | Do not run `init`. Answer directly or route to `governance directive *`. |
| Hook framework is unclear | Infer from tracked files. If still unclear, assume `.githooks/` and label that as an assumption. |
| Structured question tools are unavailable | Ask concise free-text questions, then proceed with defaults if the user does not provide more detail. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Survey the repository

Before touching anything, run these in parallel:

- `git rev-parse --show-toplevel` to confirm this is a git repo and find the root.
- `ls -la` at the root.
- Check for existing `CONSTITUTION.md`, `.governance/`, `.github/workflows/governance.yml`, `.githooks/`, and `.git/hooks/pre-commit` (legacy location — flag if present).

If this is not a git repo, stop and tell the user — `governance init` requires git.

If artifacts already exist, report what's there and ask whether to **augment** (add missing pieces, preserve existing) or **overwrite** (fresh start). Default to augment.

Also detect hook strategy before you offer or install hook-related directives:
- If `.husky/` exists, `package.json` references husky, or `.pre-commit-config.yaml` exists, treat the repo as using an existing hook framework.
- Otherwise, use the repo-local `.githooks/` strategy described below.

This choice is recorded as `hook_strategy:` in `.governance/install.yaml` (`githooks` | `husky` | `pre-commit`). The `required-docs` directive's `hooks` sub-check inspects that value and only enforces the `.githooks/` scaffolding when `hook_strategy` is `githooks`. Do not present `.githooks/` as universal if the repo already has a tracked hook framework.

**Hook-collision survey.** As part of the survey, inspect existing hook files at:

| Location | What to look for |
|---|---|
| `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/prepare-commit-msg`, `.githooks/post-commit`, `.githooks/pre-push` | grep for the ownership marker `governance-kit:managed` |
| `.git/hooks/*` | same marker (legacy path — flag even if marker is found) |
| `.husky/*`, `.pre-commit-config.yaml` | signals Path B below, not a collision |

Record findings for use at Step 6.

### Step 2 — Discover directive packs

Source the loader and enumerate packs from the kit's pack root
(today: `governance/assets/packs/` for `governance-kit/core`):

```sh
source governance/assets/packs/lib/packs.sh
list_packs governance/assets/packs
```

The loader is a bash wrapper around
`uv run --isolated --with PyYAML`, so pack manifests are parsed as real
YAML. If `uv` is unavailable, stop and tell the user pack discovery
requires `uv` (or install it before continuing).

Every `<root>/<pack-dir>/pack.yaml` is a pack. Pack ids are scoped (`<author>/<slug>` — e.g. `governance-kit/core`, `acme/widgets`); the directory name is the slug half. Directive metadata lives inside each directive's folder (`<pack-dir>/directives/<directive-id>/directive.yaml`) — the loader surfaces it via `directives_for` and `directive_field`. For each pack, build an in-memory catalog of:

- pack id, name, description, version (from `pack.yaml`)
- declared presets (`minimal`, `standard`, `strict`, plus any pack-specific ones — from `pack.yaml`)
- directive list; for each directive read `category`, `recommended`, `summary`, `surface`, `hook`, `always_install` from `directives/<directive-id>/directive.yaml`. The check script is at `directives/<directive-id>/check.sh` and the Directive snippet at `directives/<directive-id>/constitution.md` — paths are implied by the folder shape, not declared.

Pack manifests are validated against the built-in `KIT_VERSION` constant in `governance/assets/packs/lib/packctl.py`. Packs whose `min_governance_kit` is newer than `KIT_VERSION` are rejected during discovery with a clear error.

No env var or CLI flag controls pack selection in v1 — discovery is in-tree only.

### Step 3 — Choose packs, preset, and customize

Three nested questions. Each subsequent question's option list is computed from the prior answer.

**Q0 — "Which directive packs do you want?"** — multiselect.

- `governance-kit/core` (always included, non-deselectable — present it as pre-checked with a note).
- Every other pack discovered in Step 2, with its description from the manifest.

**Q1 — "Which preset?"** — single-select.

| Preset | Intent |
|---|---|
| `minimal` | Smallest credible governance baseline. |
| `standard` | Recommended default for most repos. |
| `strict` | Broad governance coverage for teams that want more structure. |
| `custom` | Start from a blank slate — no preselected directives beyond the always-installed set. |

**Semantics across packs: union.** The preset resolves as the union of the preset's directive ids across the selected packs:

```
preset_rules = ⋃ { union_preset(<preset>, <pack-dir>) : pack-dir in selected-packs }
```

A pack that does not declare the chosen preset contributes nothing for that preset — **no fallback to `recommended`**. This is deliberate: "my pack has no strict" means "strict adds nothing beyond what I already offer", not "give me everything".

Use `standard` as the recommended preset. If the user does not answer and you must proceed, assume `standard` and label it in the final summary as a material assumption.

**Q2..Qn — Category menus.** For each category present across the union of selected packs' directives (canonical: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`, `AgentDiscipline`; third-party packs may add more), present one `AskUserQuestion` with:

- Header: the category name.
- Options: every directive in that category from any selected pack. Pre-check based on the preset union from Q1. Each option's description is the directive's `summary` field from its manifest.
- `multiSelect: true`.

Split into multiple `AskUserQuestion` calls — the tool caps at four questions per call. Follow the same pattern today's flow does: first call for Foundation / Security / SystemOfRecord / CommitHygiene; second call for Quality / AgentDiscipline / any additional categories. Category menus with only a single directive are fine — do not pad with filler.

If the user picks "Other" and describes a new directive, generate a new directive folder under `.governance/packs/<owner>/<repo>/directives/<id>/` with `directive.yaml`, `check.sh`, and `constitution.md`, following the template in [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md), and add a matching Directives subsection to `CONSTITUTION.md`. The directive joins the target repo directly; it is not retrofitted into a pack (that is a pack-authoring activity, covered in [AUTHORING_PACKS.md](AUTHORING_PACKS.md)).

**Always installed — bypass the menu.** Walk every selected pack's `always_install: true` directives and queue them for install regardless of user picks. This flag is **reserved to the `governance-kit/core` pack**; third-party packs declaring it are rejected at install.

**Install resolution.** The final install list is:

```
install = always_install_core
       ∪ preset_rules (from Q1)
       ∪ user_selected_rules (from Q2..Qn, which may add or remove items)
```

If two selected packs list the same directive `id`, reject with a clear error before touching the filesystem. The target repo.s directive id namespace is still flat even though pack-installed files live under `.governance/packs/<pack-id>/directives/<id>/`, so collisions there would be silent overwrites.

Before installing, classify any user-described custom directive by surface:

| Policy surface | Use when the intent is | Preferred enforcement shape |
|---|---|---|
| `repo-state` | "the repo must contain / must not contain X" | Existence, content, pattern, metric, or structural check over tracked files |
| `change-set obligation` | "every substantive change must also do X" | Staged-diff check locally plus branch-diff check in CI |

Ask this explicitly whenever the user requests a custom directive or a directive whose rationale sounds per-change:

> What bad merge are we trying to block: a repo missing something at rest, or a substantive change landing without its required companion update?

Do not accept a repo-exists proxy for a change-set obligation unless you explicitly tell the user it is only a weak approximation and they approve that tradeoff.

For each directive in the final install list, use `../assets/packs/lib/install.sh`:

- `install_directive_folder <pack-dir> <directive> <repo-root>` copies `<pack-dir>/directives/<directive>/` into `.governance/packs/<pack-id>/directives/<directive>/`, excluding `evals/`, and marks `check.sh` plus directive-owned hooks/runtimes executable.
- `install_directive_assets <pack-dir> <directive> <repo-root>` copies optional `install-assets/` files into the target repo without overwriting existing files in augment mode. This is how directives such as `issues-tracked` seed `QUALITY.md` and `agent-token-accounting` seeds `COSTS.md`.
- If the user selects `doc-freshness`, also copy `../assets/freshness.conf` to `.governance/freshness.conf` (the seed file is commented — every path is opt-in by uncommenting).

After all directives are installed, write the install state pair:

```sh
# 1) write the install receipt — init choices + side-effect ledger
write_installed_manifest "$repo_root" \
    --owner "$repo_owner" --repo "$repo_name" \
    --hook-strategy githooks \
    --ci-workflow .github/workflows/governance.yml \
    --tests-dir .governance \
    --agents-md-directive \                # add --agents-md-created if Step 4b Case 2 fired
    --install-asset QUALITY.md \           # repeat per seeded install-asset
    --install-asset COSTS.md \
    --collision .githooks/pre-commit:wrap:.githooks/pre-commit.userhook   # only if Step 6 hit collisions

# 2) record governance-kit/core in the lockfile (source: builtin)
packverb lock-add "$repo_root/.governance/packs.lock" governance-kit/core \
    --source builtin --version "$core_pack_version" \
    --directive required-docs \
    --directive secrets-hygiene \
    --directive agent-token-accounting     # ... one --directive per installed core directive
```

`--owner` and `--repo` are required — they carry the `<owner>/<name>` identity surveyed in Step 1 and define the default repo-local pack at `.governance/packs/<owner>/<repo>/`. `--install-asset` is repeatable (once per seeded file — `install_directive_assets` copied it). `--collision` is `path:resolution[:extra]` where `resolution` ∈ `wrap | skip | overwrite-with-backup` and `extra` is the userhook or `.bak` path. `--path-b-framework` + `--path-b-entry <file>:<fingerprint>` replace `--hook-strategy githooks` when `init` took Path B. Omit `--no-constitution` unless the user explicitly asked to skip the constitution (nonstandard).

The install pair is `install.yaml` v3 + `packs.lock` v2; installed directive folders are still user-owned copies and the pair is not an auto-upgrade contract. `governance uninstall` treats both files as the authoritative record of what the kit owns. See [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) and [LOCK_SCHEMA.md](LOCK_SCHEMA.md).

### Step 4 — Write the constitution

Copy `../assets/CONSTITUTION.template.md` to `<repo-root>/CONSTITUTION.md`. Then tailor it:

- The template ships with a **Compliance** section directly under the cardinal-directive callout — leave it intact. Every bootstrapped repo gets it.
- Fill the **Principles** section with 3-5 high-level principles inferred from the directives the user picked, plus a generic starter like "Changes to the constitution require changes to the enforcing tests."
- Under **Directives**, for each directive in the final install list, read the directive's subsection snippet (`<pack-dir>/directives/<directive>/constitution.md`) and splice it verbatim into the **Directives** section. Every snippet is already in the standard Directive / Rationale / Enforced by / Exceptions shape — do not rewrite.
- Leave the **Evolution Log** section with a template entry and a note that each amendment needs a commit.

Do not invent principles the user did not pick. It is better to ship a short constitution than a bloated one. If you had to infer anything material — preset or hook strategy — record it under `Assumptions:` in the final summary. If you install any custom or change-set-aware directive, make sure the directive text says what merge it blocks, not just what file shape it checks.

### Step 4b — Inject the Compliance directive into AGENTS.md

The constitution's **Compliance** section is the directive; the AGENTS.md directive is the routing pointer that tells agents to *read* the directive. Without it, agents may never reach the constitution. Inject `../assets/AGENTS.directive.md` into the target repo's `AGENTS.md`.

The snippet is bounded by a pair of HTML marker comments — opening `<!-- governance: directives-to-follow -->` on its first line and closing `<!-- /governance: directives-to-follow -->` on its last. Both markers ship together in the template and **both** must be preserved on insert. Idempotency: grep for the opening marker before inserting; if it is already present, skip silently. Do not insert the opening without the closing or vice versa — `governance uninstall` relies on the pair to locate the exact block to strip.

Three cases:

1. **`AGENTS.md` exists and lacks the marker.** Insert the snippet near the top of the file. The right insertion point is **after the H1 heading and the first intro paragraph (or any frontmatter), and before the first `##` heading**. Use `Edit` — preserve everything else verbatim.

2. **`AGENTS.md` is missing AND the `required-docs` directive is installed.** Create a stub at `<repo-root>/AGENTS.md` containing: `# AGENTS.md`, a one-line intro, the directive snippet, and a `## What this repo is` placeholder. Tell the user the stub is intentionally minimal — they need to flesh it out (`required-docs` enforces 30–250 lines and ≥ 3 internal doc links for AGENTS.md).

3. **`AGENTS.md` is missing AND `required-docs` was not installed.** Skip silently. Do not nag — the user opted out, and creating a file they didn't ask for is presumptuous.

After injecting, run `bash .governance/run.sh` once so the user sees whether the newly-seeded AGENTS.md still needs more content.

### Step 5 — Install the test runner

Copy `../assets/dot-governance/run.sh` to `.governance/run.sh` and mark it executable (`chmod +x`). This is the entrypoint — it discovers and runs every `directives/<id>/check.sh`, prints a summary, and exits non-zero on any failure.

Copy `../assets/dot-governance/lib.sh` to `.governance/lib.sh` — shared helpers (pass/fail/skip output, `tracked_files` helper that respects `.gitignore`).

`init` only installs the bash runner. Governance is a meta-layer that sits on top of the project's code — coupling the directive suite to the project's own test runner (pytest / jest / go test) inverts the dependency. Bash works in any repo, in any CI, without install steps. Users who want governance failures to surface alongside their normal test report can add native test wrappers post-init by following [NATIVE_TESTS.md](NATIVE_TESTS.md) — that is an opt-in enhancement, not part of bootstrap.

### Step 6 — Install the git hooks

Hooks are **generated**, not copied. Use `../assets/packs/lib/install.sh` to build a hook spec from the installed directive folders, then pass that spec to `../assets/packs/lib/hooks.sh`. Always invoke `generate_hooks_for_strategy` rather than `generate_hooks` directly — the strategy-aware wrapper is the single entry point that enforces parity across host hook frameworks:

```sh
build_hook_spec_from_installed_rules <repo-root> /tmp/governance-hook-spec.tsv
generate_hooks_for_strategy <repo-root> <strategy> <pack-version-label> /tmp/governance-hook-spec.tsv
```

`<strategy>` is `githooks`, `husky`, or `pre-commit` — the same value you record as `hook_strategy:` in the manifest. The wrapper picks the install dir per strategy (`.githooks/`, `.husky/`, `.governance/hooks/`) and emits identical dispatcher bodies, so directive-owned populator hooks (`directives/<id>/hooks/<kind>.sh`) are wired in every path. **Do not** hand-roll a `bash .governance/run.sh` shim into the host framework's hook file — `.governance/run.sh` is a flat `check.sh` runner that ignores `hook:` filtering and skips populators, which is exactly the gap closed by going through the generator.

The generator:

1. Emits all five dispatchers — `pre-commit`, `commit-msg`, `prepare-commit-msg`, `post-commit`, `pre-push` — so future user-owned amendments that add a compatible `hook:` declaration are discovered without regenerating hooks.
2. Each dispatcher scans installed directive `directive.yaml` files under `.governance/packs/<owner>/<name>/directives/` at runtime, runs directive-owned `hooks/<kind>.sh` helpers first, then runs `check.sh` for directives whose `hook:` matches the dispatcher. Dispatchers honor `SKIP_GOVERNANCE=1`.
3. Stamps each dispatcher with a **line-2 ownership marker**:
   ```sh
   #!/usr/bin/env bash
   # governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>
   ```
   The `pack-version` marker is an ownership/regeneration marker, not an upgrade promise; installed pack/directive details live in `.governance/packs.lock`.

Path choice:

**Path A — repo-local `.githooks/`** (default when no other framework is present).

1. Generate `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/prepare-commit-msg`, `.githooks/post-commit`, and `.githooks/pre-push`.
2. `chmod +x` every generated hook.
3. Record `hook_strategy: githooks` in `.governance/install.yaml` so `required-docs`' `hooks` sub-check enforces the `.githooks/` scaffolding.
4. Run `git config core.hooksPath .githooks` in the bootstrapping clone.
5. Copy `../assets/setup-clone.sh` to `<repo-root>/scripts/setup-clone.sh` (create `scripts/` if missing) and `chmod +x` it. This is the one-command onboarding for every other contributor: they run `./scripts/setup-clone.sh` once per fresh clone and `core.hooksPath` is set. Worktrees inherit `.git/config` from their parent, so the script does not need to run per worktree. In the final report, tell the user to point new contributors at this script (mentioning it in `README.md` or `AGENTS.md` is a good place). Until a contributor runs it, `required-docs` nags on every commit with the exact command.
6. **Do not** create files under `.git/hooks/`. If `.git/hooks/pre-commit` (or `commit-msg`) already exists from a previous bootstrap or another tool, ask the user before deleting — it could be a husky or pre-commit.com hook (see Path B).

**Pre-existing hook collision (unmarked).** If the survey in Step 1 found a target hook that exists and lacks the ownership marker, STOP before writing. Show the user the existing hook and offer three options:

1. **Wrap** (default) — write the generated hook, rename the existing one to `<name>.userhook`, and exec it at the end of the generated hook. Keeps both behaviors.
2. **Merge by hand** — print both scripts, skip hook install, rely on CI.
3. **Overwrite + backup** — back up the existing hook to `<path>.pre-governance.bak`, then write ours. Warn in the final summary.

If the existing hook **has** the marker, overwrite silently — `governance directive *` relies on this. (The marker is a contract: "this file is regeneratable.")

**Path B — existing hook framework.** If the project uses `husky` or the `pre-commit` framework, *do not* set `core.hooksPath` and do not copy into `.githooks/` — those frameworks already have their own tracked hook-config mechanism. Generate dispatchers via the same strategy-aware entry point used in Path A — only the strategy and the resulting install dir change.

In this path:
- For husky: call `generate_hooks_for_strategy <repo-root> husky <version> <spec>`. The wrapper writes all five dispatchers into `.husky/` so directive-owned populator hooks (`directives/<id>/hooks/<kind>.sh`) are wired uniformly. Each generated file carries the line-2 ownership marker; existing unmarked hooks trigger the same collision flow as Path A.
- For pre-commit.com: call `generate_hooks_for_strategy <repo-root> pre-commit <version> <spec>` to materialize dispatchers under `.governance/hooks/`, then add a `.pre-commit-config.yaml` hook block per stage that shells out to `bash .governance/hooks/<kind>`. See [NATIVE_TESTS.md](NATIVE_TESTS.md) for the per-framework snippets.
- Record `hook_strategy: husky` or `hook_strategy: pre-commit` in `.governance/install.yaml` so `required-docs`' `hooks` sub-check transparently skips (it only enforces `.githooks/` scaffolding when `hook_strategy` is `githooks`).
- Record each materialized hook file under `path_b.entries` with its fingerprint so `governance uninstall` and `governance reset` can recognize the kit's output.
- Tell the user explicitly that the repo is using its existing tracked hook framework instead of `.githooks/`, and that populator coverage (token-accounting, steering-accounting) now matches Path A.

### Step 7 — Install the CI workflow

Copy `../assets/governance.yml` to `.github/workflows/governance.yml`. The workflow runs `bash .governance/run.sh` on `push` to `main` and on every `pull_request`, and it never skips — CI is the backstop the pre-commit hook can be bypassed around. If the user later opts into native tests via [NATIVE_TESTS.md](NATIVE_TESTS.md), they extend the workflow at that point.

### Step 8 — Report to the user

Print a concise summary:
- Packs selected.
- Preset chosen and whether it was explicit or assumed.
- Hook strategy chosen (`.githooks/`, husky, or `pre-commit`).
- Directives installed (with file paths, grouped by pack if multiple packs were selected).
- Directives deliberately skipped (with reasons) when that matters.
- Any pre-existing hook collisions encountered and how they were resolved.
- How to run locally: `bash .governance/run.sh`.
- How to skip the hook: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`.
- Assumptions made. If none, say `Assumptions: none`.
- Reminder: **constitution amendments must land with their test.** Point to [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) and (if multiple packs were selected) [AUTHORING_PACKS.md](AUTHORING_PACKS.md) for the templates.

Do **not** commit the new files. Leave that to the user — the first commit of their governance system should be intentional, and the pre-commit hook is now active.

## Required final output

Every successful `init` run should leave the user with a summary that includes:

- `Packs:` the list of selected packs.
- `Preset:` chosen preset and whether it was explicit or assumed.
- `Hook strategy:` `.githooks/`, husky, or `pre-commit`.
- `Directives installed:` file-backed list or grouped summary.
- `Directives skipped:` only when the omission is meaningful.
- `Hook collisions:` the resolution chosen for each pre-existing unmarked hook, or `none`.
- `Assumptions:` any material assumptions, or `none`.
- `Next command:` `bash .governance/run.sh`

---

## Key design principles

- **The constitution and the tests evolve together.** Never add a directive to the constitution without a test. Never add a test without a directive. If the user asks to add one in isolation, push back and do both.
- **Packs are the extension point.** Adding a directive to a pack is a two-file edit (the `.sh` + the manifest entry); every menu, hook dispatcher, and constitution snippet flows from the manifest. Do not shadow the manifest with hand-written lists in SKILL.md.
- **`governance-kit/core` is non-optional.** Users can select additional packs but cannot deselect `governance-kit/core`. The `always_install: true` flag is reserved to `governance-kit/core` — third-party packs cannot force-install directives.
- **Preset semantics are union, not fallback.** If a pack lacks the selected preset, it contributes nothing for that preset.
- **Escape hatches are a feature, not a bug.** `SKIP_GOVERNANCE=1` exists because governance that blocks emergency hotfixes will get ripped out. CI enforces the directive even when the hook is skipped, which is the right layering.
- **Bash-only at bootstrap; native is post-init.** Governance is a meta-layer over the project's code, so the directive suite must not depend on the project's own toolchain. `init` only installs the bash runner. Native test wrappers (pytest / jest / go test) are an opt-in users add later via [NATIVE_TESTS.md](NATIVE_TESTS.md) — never asked at bootstrap.
- **Respect the repo's existing hook framework.** `.githooks/` is the default only when no tracked hook framework already exists. Do not force repos off husky or `pre-commit`.
- **Hook ownership is explicit.** Every generated hook carries the `governance-kit:managed` marker on line 2. An unmarked hook at a target path is somebody else's file — prompt before touching it.
- **Match the enforcement surface to the real intent.** If a directive is meant to govern each substantive change, do not implement it as a repo-exists or file-count check.
- **Reject weak proxies when they create false confidence.** A directive that says "every change must do X" but only checks "the repo contains one X somewhere" is a bad bootstrap output, not a partial success.
- **State material assumptions explicitly.** If you had to infer the preset or hook strategy, surface that in the summary.
- **No invented directives.** When writing the constitution, only include directives the user selected. Governance loses authority the moment it contains directives nobody signed off on.

## References

- [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) — full list of ready-made directives with descriptions, and the template for adding new ones. Notes pack membership per directive.
- [AUTHORING_PACKS.md](AUTHORING_PACKS.md) — how to write a third-party pack.
- [NATIVE_TESTS.md](NATIVE_TESTS.md) — how to port bash directives to pytest / jest / go test, and husky / pre-commit-framework snippets.
- [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) — wiring instructions for the `agent-token-accounting` directive shipped by the `governance-kit/core` pack.

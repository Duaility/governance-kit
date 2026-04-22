---
name: governance-bootstrap
description: Bootstraps governance-driven development in a repository that does not yet have the kit installed — scaffolds an initial CONSTITUTION.md, a test suite under tests/governance/ that enforces it, tracked git hooks, and a GitHub Actions workflow. Offers a menu of ready-made rules across five categories (Foundation, Security, System of record, Commit hygiene, Quality) including Conventional Commits, secret scanning, .env hygiene, GitHub Actions hardening, AGENTS.md / ARCHITECTURE.md / SECURITY.md checks, broken-link detection, doc freshness, and merge-conflict-marker detection. Use when the user wants initial governance setup, says "bootstrap governance", "set up governance tests", or wants to install this governance kit into a repo. Do not use for amending an existing rule set; use governance-amend for that.
license: MIT
metadata:
  author: governance-kit
  version: "0.1"
---

# governance-bootstrap

This skill sets up **governance-driven development** in the current repository:

1. A `CONSTITUTION.md` at the repo root — the evolving source of truth for rules, guidelines, and invariants.
2. Machine-enforced tests under `tests/governance/` — every rule in the constitution has a corresponding test.
3. A pre-commit hook — runs `tests/governance/` before commits, with `SKIP_GOVERNANCE=1` and `git commit --no-verify` as escape hatches.
4. A GitHub Actions workflow at `.github/workflows/governance.yml` — same tests, enforced in CI on every PR.

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

### Step 3 — Choose a preset, then customize

Before presenting the full rule menu, ask the user for a starting preset. The preset is a starting point, not a lock-in. The user can always add or remove rules in the next step.

Preset choices:

| Preset | Intent | Default starting rules |
|---|---|---|
| `minimal` | Smallest credible governance baseline | `constitution-exists`, `no-secrets`, `dotenv-gitignored`, `workflows-hardened`, `no-broken-internal-doc-links`, `no-large-files`, `no-committed-build-artifacts`, `no-merge-conflict-markers`, and `hooks-configured` when using `.githooks/` |
| `standard` | Recommended default for most repos | `minimal` plus `agents-md-exists`, `conventional-commits`, `doc-freshness` |
| `strict` | Broad governance coverage for teams that want more structure | `standard` plus `readme-exists`, `security-md-exists`, `architecture-doc-exists`, `ci-workflow-exists`, `no-orphan-todos`, `file-size-limit`, `no-debug-statements` |
| `custom` | Start from a blank slate | no preselected rules beyond the always-installed set |

Use `standard` as the recommended preset. If the user does not answer and you must proceed, assume `standard` and label it in the final summary as a material assumption.

After the preset choice, present the rule catalog across **two `AskUserQuestion` calls** (the tool caps at four questions per call). Use `multiSelect: true` for every question. If structured question tools are unavailable, ask concise free-text questions in the same category order and proceed with the user's answers. "Other" appears automatically — if the user picks it and describes a rule, generate a new `.sh` file under `tests/governance/rules/` following the template in `references/RULES_CATALOG.md` and add a matching Invariants subsection to `CONSTITUTION.md`.

**Always installed — do not put in the menu:**
- `no-merge-conflict-markers` — no `<<<<<<<` / `=======` / `>>>>>>>` in any tracked file. Zero false positives, zero config. Install unconditionally.
- `hooks-configured` — `.githooks/pre-commit` (and `.githooks/commit-msg`, if `conventional-commits` is installed) are tracked and executable, and `core.hooksPath` is set to `.githooks`. Install this only when the repo is using the `.githooks/` strategy. If the repo uses husky or `pre-commit`, skip this rule entirely.

**First `AskUserQuestion` call — four questions:**

**Q1 — "Which foundation rules should the constitution enforce?"** (header: `Foundation`)
- `constitution-exists` — CONSTITUTION.md exists, non-empty, ≥ 10 lines. *(Recommended — the meta-rule)*
- `readme-exists` — README.md exists with a heading and ≥ 30 words.
- `license-exists` — A LICENSE (or variant) exists at the repo root.
- `agents-md-exists` — AGENTS.md exists at the repo root, 30–250 lines, with ≥ 3 links to other docs. *(Recommended — the harness-engineering agent entry point)*

**Q2 — "Which security rules should the constitution enforce?"** (header: `Security`)
- `no-secrets` — Heuristic scan for AWS / GCP / GitHub / Slack / Stripe / private-key patterns. *(Recommended)*
- `dotenv-gitignored` — `.env` is listed in `.gitignore` and not tracked. *(Recommended)*
- `security-md-exists` — `SECURITY.md` (root, `docs/`, or `.github/`) with a contact email or URL.
- `workflows-hardened` — GitHub Actions workflows declare a `permissions:` block and pin third-party actions to a commit SHA. *(Recommended)*

**Q3 — "Which system-of-record rules should the constitution enforce?"** (header: `SystemOfRecord`)
- `architecture-doc-exists` — `ARCHITECTURE.md` (root or `docs/`) exists, ≥ 20 lines.
- `no-broken-internal-doc-links` — Markdown links to local paths resolve. *(Recommended)*
- `doc-freshness` — Docs opted into `tests/governance/freshness.conf` carry a `<!-- last-verified: YYYY-MM-DD -->` marker within the last 90 days.
- `ci-workflow-exists` — At least one non-governance workflow exists under `.github/workflows/`.

**Q4 — "Which commit-hygiene rules should the constitution enforce?"** (header: `CommitHygiene`)
- `conventional-commits` — Commit messages match `<type>(scope)?!?: subject`. *(Recommended — installs a `commit-msg` hook)*
- `no-orphan-todos` — Every `TODO` / `FIXME` references `#123` or `ABC-123`.

*(This question has only 2 options; that's valid. Do not pad with filler.)*

**Second `AskUserQuestion` call — one question:**

**Q5 — "Which quality rules should the constitution enforce?"** (header: `Quality`)
- `no-debug-statements` — No stray `console.log`, `debugger`, `breakpoint()`, `pdb`, `dbg!`.
- `file-size-limit` — No source file exceeds 500 lines (configurable).
- `no-large-files` — No tracked file exceeds 5 MB (configurable). *(Recommended)*
- `no-committed-build-artifacts` — No `__pycache__`, `*.pyc`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store` etc. are tracked. *(Recommended)*

For each selected rule, copy `assets/tests-bash/rules/<rule>.sh` into `tests/governance/rules/` in the target repo. Also copy `assets/tests-bash/rules/no-merge-conflict-markers.sh` regardless of what the user picked. Copy `assets/tests-bash/rules/hooks-configured.sh` only when using the `.githooks/` strategy.

If the user selects `conventional-commits`, remember that `commit-msg` will also be installed in Step 6.

If the user selects `doc-freshness`, also copy `assets/freshness.conf` to `tests/governance/freshness.conf`. The seed file is commented — every path is opt-in by uncommenting. The companion `governance-gardener` skill also checks a built-in baseline set of well-known docs (AGENTS.md, README.md, SECURITY.md, docs/**, plans/**) on top of this config when it walks the Alignment axis, so the seed only lists paths the baseline might miss.

If the user asks for rules that exist in `references/RULES_CATALOG.md` under "Also available" (e.g. `env-example-current`, `no-curl-bash-pipe`, `docs-dir-minimum`), copy those too — they are supported, just not in the default menu.

### Step 4 — Write the constitution

Copy `assets/CONSTITUTION.template.md` to `<repo-root>/CONSTITUTION.md`. Then tailor it:

- The template ships with a **Compliance** section directly under the cardinal-rule callout — leave it intact. It is the prescriptive directive that tells humans, agents, and automation they must satisfy every principle, guideline, and invariant in the document (not just the mechanically enforced ones). Every bootstrapped repo gets it; do not edit unless the user asks.
- Fill the **Principles** section with 3-5 high-level principles inferred from the rules the user picked, plus a generic starter like "Changes to the constitution require changes to the enforcing tests."
- Under **Invariants**, list one subsection per selected rule. Each subsection must have:
  - **Rule** (one-sentence statement)
  - **Rationale** (why this matters)
  - **Enforced by** (path to the test file, e.g. `tests/governance/rules/no-secrets.sh`)
  - **Exceptions** (how to document approved deviations)
- Leave the **Evolution Log** section with a template entry and a note that each amendment needs a commit.

Do not invent principles the user did not pick. It is better to ship a short constitution than a bloated one.
If you had to infer anything material — stack, preset, or hook strategy — record it under `Assumptions:` in the final summary.

### Step 4b — Inject the Compliance directive into AGENTS.md

The constitution's **Compliance** section is the rule; the AGENTS.md directive is the routing pointer that tells agents to *read* the rule. Without it, agents may never reach the constitution. Inject `assets/AGENTS.directive.md` into the target repo's `AGENTS.md`.

The snippet leads with an HTML marker comment `<!-- governance: rules-to-follow -->` so this step is **idempotent** — always grep for the marker before inserting. If it's already present, skip silently.

Three cases:

1. **`AGENTS.md` exists and lacks the marker.** Insert the snippet near the top of the file. The right insertion point is **after the H1 heading and the first intro paragraph (or any frontmatter), and before the first `##` heading**. Use `Edit` — preserve everything else verbatim.

2. **`AGENTS.md` is missing AND the user picked the `agents-md-exists` rule.** Create a stub at `<repo-root>/AGENTS.md` containing: `# AGENTS.md`, a one-line intro, the directive snippet, and a `## What this repo is` placeholder. Tell the user the stub is intentionally minimal — they need to flesh it out (the rule requires 30–250 lines and ≥ 3 internal doc links).

3. **`AGENTS.md` is missing AND the user did NOT pick `agents-md-exists`.** Skip silently. Do not nag — the user opted out of the rule, and creating a file they didn't ask for is presumptuous.

After injecting, run `bash tests/governance/rules/agents-md-exists.sh` once if the rule is installed, so the user knows whether the file still needs more content.

### Step 5 — Install the test runner

Copy `assets/tests-bash/run.sh` to `tests/governance/run.sh` and mark it executable (`chmod +x`). This is the entrypoint — it discovers and runs every `*.sh` in `tests/governance/rules/`, prints a summary, and exits non-zero on any failure.

Copy `assets/tests-bash/lib.sh` to `tests/governance/lib.sh` — shared helpers (pass/fail/skip output, `tracked_files` helper that respects `.gitignore`).

If the user wants **native** tests in addition to bash, read `references/NATIVE_TESTS.md` for the port pattern for their stack (pytest / jest / go test). Generate the native test file(s) inline — do not invent a separate `run.sh` for the native side; the project's existing test runner (`pytest tests/governance`, `npx jest tests/governance`, `go test ./tests/governance/...`) is the entrypoint.

### Step 6 — Install the git hooks

Choose one path based on the hook strategy detected in Step 1.

**Path A — repo-local `.githooks/`**

Hook scripts live in a **tracked** directory `.githooks/` — not in `.git/hooks/`, which is per-clone and untracked. This way every contributor's clone gets the same hooks, and the `hooks-configured` rule catches anyone whose `core.hooksPath` is unset.

Do this:

1. Copy `assets/githooks/pre-commit` to `.githooks/pre-commit` in the target repo and `chmod +x` it. The hook:
   - Skips if `SKIP_GOVERNANCE=1` is set.
   - Runs `tests/governance/run.sh` (bash mode) and/or the native command (if native tests are installed — detect and run both if present).
   - On failure, prints the failing rule, the `SKIP_GOVERNANCE=1 git commit` escape hatch, and `git commit --no-verify` as the nuclear option.
2. **If, and only if, the user selected `conventional-commits`**, also copy `assets/githooks/commit-msg` to `.githooks/commit-msg` and `chmod +x` it. Honors the same escape hatches.
3. Also install `assets/tests-bash/rules/hooks-configured.sh` to `tests/governance/rules/hooks-configured.sh`.
4. Run `git config core.hooksPath .githooks` in the target repo. **Tell the user explicitly** that this config is per-clone — every other contributor must run the same command after their first clone. The `hooks-configured` rule will surface that requirement on every commit until they do.
5. **Do not** create files under `.git/hooks/`. If `.git/hooks/pre-commit` (or `commit-msg`) already exists from a previous bootstrap or another tool, ask the user before deleting — it could be a husky or pre-commit.com hook (see the framework branch below).

**Path B — existing hook framework**

If the project uses `husky` or the `pre-commit` framework, *do not* set `core.hooksPath` and do not copy into `.githooks/` — those frameworks already have their own tracked hook-config mechanism. Instead, add a hook entry to the existing config (ask the user which framework they use, or infer it from the files you found). See `references/NATIVE_TESTS.md` for the husky / pre-commit.com snippets.

In this path:
- Do not install `hooks-configured.sh`.
- Do not describe `hooks-configured` as part of the constitution.
- Tell the user explicitly that the repo is using its existing tracked hook framework instead of `.githooks/`.

### Step 7 — Install the CI workflow

Copy `assets/governance.yml` to `.github/workflows/governance.yml`. Adjust the test-runner step based on the stack chosen in Step 2. The workflow runs on `push` to `main` and on every `pull_request`, and it never skips — CI is the backstop the pre-commit hook can be bypassed around.

### Step 8 — Report to the user

Print a concise summary:
- Preset chosen and whether it was explicit or assumed.
- Hook strategy chosen (`.githooks/`, husky, or `pre-commit`).
- Stack detected.
- Rules installed (with file paths).
- Rules deliberately skipped (with reasons) when that matters.
- How to run locally: `bash tests/governance/run.sh`.
- How to skip the hook: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`.
- Assumptions made. If none, say `Assumptions: none`.
- Reminder: **constitution amendments must land with their test.** Point to `references/RULES_CATALOG.md` for the template.

Do **not** commit the new files. Leave that to the user — the first commit of their governance system should be intentional, and the pre-commit hook is now active.

## Required final output

Every successful run should leave the user with a summary that includes:

- `Preset:` chosen preset and whether it was explicit or assumed.
- `Hook strategy:` `.githooks/`, husky, or `pre-commit`.
- `Rules installed:` file-backed list or grouped summary.
- `Rules skipped:` only when the omission is meaningful.
- `Assumptions:` any material assumptions, or `none`.
- `Next command:` `bash tests/governance/run.sh`

---

## Key design rules for this skill

- **The constitution and the tests evolve together.** Never add a rule to the constitution without a test. Never add a test without a rule. If the user asks to add one in isolation, push back and do both.
- **Escape hatches are a feature, not a bug.** `SKIP_GOVERNANCE=1` exists because governance that blocks emergency hotfixes will get ripped out. CI enforces the rule even when the hook is skipped, which is the right layering.
- **Bash-first, native as enhancement.** Bash tests work in any repo, in any CI, without install steps. Native tests (pytest etc.) are nicer DX but add friction. Default to bash; offer native.
- **Respect the repo's existing hook framework.** `.githooks/` is the default only when no tracked hook framework already exists. Do not force repos off husky or `pre-commit`.
- **Start with a preset, then let the user customize.** Presets reduce setup fatigue; the category menu keeps the result intentional.
- **State material assumptions explicitly.** If you had to infer the preset, stack, or hook strategy, surface that in the summary.
- **No invented rules.** When writing the constitution, only include rules the user selected. Governance loses authority the moment it contains rules nobody signed off on.

## References

- `../GOVERNANCE_VOCABULARY.md` — shared terms used across the three governance skills.
- `references/RULES_CATALOG.md` — full list of ready-made rules with descriptions, and the template for adding new ones.
- `references/NATIVE_TESTS.md` — how to port bash rules to pytest / jest / go test, and husky / pre-commit-framework snippets.

---
name: governance-bootstrap
description: Bootstraps governance-driven development in a repository — scaffolds a CONSTITUTION.md, a test suite under tests/governance/ that enforces the constitution, pre-commit and commit-msg hooks (skippable), and a GitHub Actions workflow. Offers a menu of ready-made rules across five categories (Foundation, Security, System of record, Commit hygiene, Quality) including Conventional Commits, secret scanning, .env hygiene, GitHub Actions hardening, AGENTS.md / ARCHITECTURE.md / SECURITY.md checks, broken-link detection, doc freshness, and merge-conflict-marker detection. Use when the user wants to set up governance, add a constitution, enforce invariants, install conventional commits, harden workflows, or when they say "bootstrap governance", "set up governance tests", "governance-driven development", or reference a constitution document.
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

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Survey the repository

Before touching anything, run these in parallel:

- `git rev-parse --show-toplevel` to confirm this is a git repo and find the root.
- `ls -la` at the root.
- Check for stack markers: `package.json`, `pyproject.toml`, `setup.py`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`.
- Check for existing `CONSTITUTION.md`, `tests/governance/`, `.github/workflows/governance.yml`, `.git/hooks/pre-commit`.

If this is not a git repo, stop and tell the user — governance-bootstrap requires git.

If artifacts already exist, report what's there and ask whether to **augment** (add missing pieces, preserve existing) or **overwrite** (fresh start). Default to augment.

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

### Step 3 — Offer the rule menu

The rule catalog is five categories, presented across **two `AskUserQuestion` calls** (the tool caps at four questions per call). Use `multiSelect: true` for every question. "Other" appears automatically — if the user picks it and describes a rule, generate a new `.sh` file under `tests/governance/rules/` following the template in `references/RULES_CATALOG.md` and add a matching Invariants subsection to `CONSTITUTION.md`.

**Always installed — do not put in the menu:**
- `no-merge-conflict-markers` — no `<<<<<<<` / `=======` / `>>>>>>>` in any tracked file. Zero false positives, zero config. Install unconditionally.

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

For each selected rule, copy `assets/tests-bash/rules/<rule>.sh` into `tests/governance/rules/` in the target repo. Also copy `assets/tests-bash/rules/no-merge-conflict-markers.sh` regardless of what the user picked.

If the user selects `conventional-commits`, remember that `commit-msg` will also be installed in Step 6.

If the user selects `doc-freshness`, also copy `assets/freshness.conf` to `tests/governance/freshness.conf`. The seed file is commented — every path is opt-in by uncommenting. The companion `doc-gardener` skill also checks a built-in baseline set of well-known docs (AGENTS.md, README.md, SECURITY.md, docs/**, plans/**, adrs/**) on top of this config, so the seed only lists paths the baseline might miss.

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

Copy `assets/pre-commit` to `.git/hooks/pre-commit` and `chmod +x` it. The hook:
- Skips if `SKIP_GOVERNANCE=1` is set.
- Runs `tests/governance/run.sh` (bash mode) and/or the native command (if native tests are installed — detect and run both if present).
- On failure, prints the rule that failed, the `SKIP_GOVERNANCE=1 git commit` escape hatch, and `git commit --no-verify` as the nuclear option.

**If, and only if, the user selected `conventional-commits`**, also copy `assets/commit-msg` to `.git/hooks/commit-msg` and `chmod +x` it. This hook validates the pending commit message against the Conventional Commits regex before the commit is finalized. It honors the same `SKIP_GOVERNANCE=1` / `--no-verify` escape hatches.

If the project uses `husky` or the `pre-commit` framework, *do not* overwrite `.git/hooks/pre-commit`. Instead, add a hook entry to the existing config (ask the user which framework they use). See `references/NATIVE_TESTS.md` for the husky / pre-commit.com snippets. The `commit-msg` hook registers analogously (`npx husky add .husky/commit-msg '...'` for husky).

### Step 7 — Install the CI workflow

Copy `assets/governance.yml` to `.github/workflows/governance.yml`. Adjust the test-runner step based on the stack chosen in Step 2. The workflow runs on `push` to `main` and on every `pull_request`, and it never skips — CI is the backstop the pre-commit hook can be bypassed around.

### Step 8 — Report to the user

Print a concise summary:
- Stack detected.
- Rules installed (with file paths).
- How to run locally: `bash tests/governance/run.sh`.
- How to skip the hook: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`.
- Reminder: **constitution amendments must land with their test.** Point to `references/RULES_CATALOG.md` for the template.

Do **not** commit the new files. Leave that to the user — the first commit of their governance system should be intentional, and the pre-commit hook is now active.

---

## Key design rules for this skill

- **The constitution and the tests evolve together.** Never add a rule to the constitution without a test. Never add a test without a rule. If the user asks to add one in isolation, push back and do both.
- **Escape hatches are a feature, not a bug.** `SKIP_GOVERNANCE=1` exists because governance that blocks emergency hotfixes will get ripped out. CI enforces the rule even when the hook is skipped, which is the right layering.
- **Bash-first, native as enhancement.** Bash tests work in any repo, in any CI, without install steps. Native tests (pytest etc.) are nicer DX but add friction. Default to bash; offer native.
- **No invented rules.** When writing the constitution, only include rules the user selected. Governance loses authority the moment it contains rules nobody signed off on.

## References

- `references/RULES_CATALOG.md` — full list of ready-made rules with descriptions, and the template for adding new ones.
- `references/NATIVE_TESTS.md` — how to port bash rules to pytest / jest / go test, and husky / pre-commit-framework snippets.

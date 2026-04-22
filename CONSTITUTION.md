# Constitution

This document is the source of truth for the rules, guidelines, and invariants that govern development in this repository. Every rule here is enforced by an executable test under `tests/governance/`. A rule with no enforcing test is not a rule — it is a wish.

> **The cardinal rule:** Amendments to this constitution must land in the same commit as the change to its enforcing test. No exceptions.

## Principles

- Changes to this constitution must land with a corresponding change to the enforcing tests.
- Escape hatches exist (`SKIP_GOVERNANCE=1`, `git commit --no-verify`) — but every skipped commit is still checked in CI.
- Governance rules should fail loudly and cheaply. If a rule cannot be mechanically checked, it does not belong here.
- This repo ships governance tooling; we dogfood what we ship — the skills here enforce themselves on themselves.
- Documentation is a system of record. Broken internal links and untracked secrets are the same class of bug: stale state pretending to be current.

## Invariants

### constitution-exists

- **Rule**: A `CONSTITUTION.md` exists at the repo root, is non-empty, and has at least 10 lines.
- **Rationale**: Governance without a discoverable source of truth is tribal knowledge. The meta-rule keeps the system honest.
- **Enforced by**: `tests/governance/rules/constitution-exists.sh`
- **Exceptions**: none.

### agents-md-exists

- **Rule**: `AGENTS.md` exists at the repo root, is 30–250 lines, and links to at least 3 other docs.
- **Rationale**: Agents and new contributors need a single, compact entry point that routes them to the rest of the system of record.
- **Enforced by**: `tests/governance/rules/agents-md-exists.sh`
- **Exceptions**: none.

### no-secrets

- **Rule**: No tracked file contains AWS / GCP / GitHub / Slack / Stripe / private-key patterns.
- **Rationale**: A committed secret is a compromised secret. Rotation is expensive; prevention is free.
- **Enforced by**: `tests/governance/rules/no-secrets.sh`
- **Exceptions**: Annotate intentional fixture strings with `# governance: allow-secret <reason>` on the same line.

### dotenv-gitignored

- **Rule**: `.env` is listed in `.gitignore` and not tracked.
- **Rationale**: `.env` is the default landing spot for local credentials; it must never make it to origin.
- **Enforced by**: `tests/governance/rules/dotenv-gitignored.sh`
- **Exceptions**: none. Use `.env.example` for shareable templates.

### workflows-hardened

- **Rule**: Every GitHub Actions workflow declares a top-level `permissions:` block, and third-party actions are pinned to a commit SHA.
- **Rationale**: Default `GITHUB_TOKEN` permissions are write-all; unpinned tags are a supply-chain hole.
- **Enforced by**: `tests/governance/rules/workflows-hardened.sh`
- **Exceptions**: First-party `actions/*` may be pinned to a major tag (enforced by the test).

### no-broken-internal-doc-links

- **Rule**: Markdown links to local paths resolve to a file that exists in the repo.
- **Rationale**: Broken links silently rot the system of record. Readers lose trust in the docs that remain.
- **Enforced by**: `tests/governance/rules/no-broken-internal-doc-links.sh`
- **Exceptions**: none — fix the link or delete it.

### conventional-commits

- **Rule**: Commit messages match `<type>(scope)?!?: subject` per the Conventional Commits spec.
- **Rationale**: A parseable commit log feeds changelog generation, semver decisions, and future rule enforcement.
- **Enforced by**: `tests/governance/rules/conventional-commits.sh` (checks history) and `.git/hooks/commit-msg` (checks the pending commit).
- **Exceptions**: Merge commits and revert commits are exempt.

### no-large-files

- **Rule**: No tracked file exceeds 5 MB.
- **Rationale**: Large binaries bloat clones and hide in diffs; use Git LFS or an asset CDN instead.
- **Enforced by**: `tests/governance/rules/no-large-files.sh`
- **Exceptions**: Raise the limit in the test if the project has a legitimate reason — document it in a PR.

### no-committed-build-artifacts

- **Rule**: Build/cache artifacts (`__pycache__`, `*.pyc`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, etc.) are not tracked.
- **Rationale**: Committed artifacts break reproducibility and create spurious diffs.
- **Enforced by**: `tests/governance/rules/no-committed-build-artifacts.sh`
- **Exceptions**: none — extend `.gitignore` instead.

### no-merge-conflict-markers

- **Rule**: No tracked file contains `<<<<<<<`, `=======`, or `>>>>>>>` conflict markers.
- **Rationale**: A conflict marker in `main` means an unfinished merge shipped.
- **Enforced by**: `tests/governance/rules/no-merge-conflict-markers.sh`
- **Exceptions**: none.

## Amendment process

1. Open a PR that modifies this file **and** `tests/governance/rules/` in the same commit.
2. The PR description states *what* changed and *why* — link the incident, RFC, or discussion that motivated it.
3. Add an entry to the **Evolution Log** below.
4. At least one reviewer with governance authority approves.

## Evolution Log

<!-- Append, do not rewrite history. Format: YYYY-MM-DD — <author> — <one-line summary>. Link the PR. -->

- 2026-04-22 — @srikanth — Initial constitution bootstrapped via governance-bootstrap.

## Escape hatches

Governance is enforced at two layers:

1. **Pre-commit hook** — runs `tests/governance/run.sh` before each commit. Skip with `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` when a hotfix cannot wait.
2. **CI workflow** — `.github/workflows/governance.yml` runs the same tests on every PR and push to the default branch. CI cannot be skipped from a developer machine.

The hook is for speed; CI is for enforcement. If a commit lands with the hook skipped, CI will catch it.

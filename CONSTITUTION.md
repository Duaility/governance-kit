<!-- last-verified: 2026-04-22 -->

# Constitution

This document is the source of truth for the rules, guidelines, and invariants that govern development in this repository. Every rule here is enforced by an executable test under `tests/governance/`. A rule with no enforcing test is not a rule — it is a wish.

> **The cardinal rule:** Amendments to this constitution must land in the same commit as the change to its enforcing test. No exceptions.

## Compliance

Anyone working in this repo — humans, agents, scripted automation — must satisfy every principle, guideline, and invariant in this document.

- **Mechanical rules** (the **Invariants** section below) are enforced by `tests/governance/` via the pre-commit hook and CI. A violating commit is blocked locally and re-blocked in CI if the hook is bypassed.
- **Principles and guidelines** (the **Principles** section above the Invariants) cannot be checked mechanically. They depend on judgment and reviewer discipline. A change that defies a principle without explanation is grounds to block the PR.

If a specific change cannot satisfy a rule, document the deviation in the PR description and use the rule's stated waiver mechanism if one exists. Drive-by violations without explanation will block the merge.

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

- **Rule**: Commit messages match `<type>(scope)?!?: subject (#123)` per the Conventional Commits spec, with a trailing GitHub issue reference in parentheses.
- **Rationale**: A parseable commit log feeds changelog generation, semver decisions, and future rule enforcement; the linked GitHub issue keeps every commit tied to a durable discussion or work item.
- **Enforced by**: `tests/governance/rules/conventional-commits.sh` (checks history) and `.githooks/commit-msg` (checks the pending commit).
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

### plan-captured

- **Rule**: The repo maintains a `plans/` directory with at least one tracked `.md` file, every `plans/*.md` has a top-level `# ` heading, a `## Goal` section, and a `## Steps` section, and every substantive tracked change outside `plans/` or `governance-health/` adds or modifies at least one `plans/*.md` file in the same change set.
- **Rationale**: The diff shows *what* changed; the plan shows *why it took this shape*. Without the plan on disk, reviewers and future agents reconstruct intent from code and get it wrong.
- **Enforced by**: `tests/governance/rules/plan-captured.sh`
- **Exceptions**: Per-file waiver — a line matching `governance: allow-plan-captured` (bare or inside an HTML comment) anywhere in the file exempts that plan from the structure check. Changes limited to `plans/` or `governance-health/` are exempt from the same-change requirement.

### issues-tracked

- **Rule**: `QUALITY.md` exists at the repo root with a top-level `# ` heading and contains `## Open` and `## Resolved` sections.
- **Rationale**: Bugs and quality observations discovered between releases rot in Slack and memory. Tracking them in a file keeps them in the system of record, diff-auditable, and greppable by agents and humans alike.
- **Enforced by**: `tests/governance/rules/issues-tracked.sh`
- **Exceptions**: none. Empty sections are allowed; the file itself is the contract.

### agent-token-accounting

- **Rule**: Every commit carrying an `Agent:` trailer also carries the full trailer set (`Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Token-Total = Token-Input + Token-Output`, and has exactly one matching append-only row in `COSTS.md` whose numbers agree with the trailers (`Token-Input == row.input + row.cache_create`, `Token-Output == row.output`, `Token-Total == row.total`). `COSTS.md` rows are well-formed — 10 columns (`cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note`) with `total == input + cache_create + output` (cache_read is tracked but deliberately excluded from total) — and `Cost-Key` is unique within the file. Legacy 8-column rows (pre-cache-split) are accepted with cache fields defaulted to 0.
- **Rationale**: Agent-authored work should be accountable to the same system-of-record discipline as any other change. Token trailers give branch-time provenance reviewers can read; `COSTS.md` is the durable ledger that survives squash merges and keeps the audit trail in the repo rather than on a contributor's laptop. Splitting cache traffic into its own columns keeps the ledger lossless — billing dollars and cache-hit-rate are recoverable from `cache_create` and `cache_read` — but the headline `total` deliberately excludes `cache_read` so a ledger row's total represents new work, not cache rent. The same reasoning drives the trailer shape: `Token-Input = input + cache_create`, `Token-Total = Token-Input + Token-Output`, and by construction `Token-Total == row.total`. The rule is a no-op on human commits, so adoption has zero friction — `git commit` is the entry point for agents and humans alike; the pre-commit hook auto-detects the runtime and does the accounting.
- **Enforced by**: `tests/governance/rules/agent-token-accounting.sh` (validates history, shells out to `scripts/governance/lib/ledger.py` for ledger shape + `scripts/governance/lib/trailers.py` for trailer shape and cross-check math), `scripts/governance/agent-accounting.sh` invoked from `.githooks/pre-commit` (detects the runtime, reads the transcript, and appends the `COSTS.md` row in-tree via `lib/ledger.py`), and `.githooks/prepare-commit-msg` (stamps matching trailers from the pre-commit handoff).
- **Exceptions**: none. The rule only activates on commits that declare `Agent:`; commits without that trailer are not in scope.

### hooks-configured

- **Rule**: `.githooks/pre-commit` is tracked and executable, `.githooks/commit-msg` is tracked and executable when `conventional-commits` is installed, and `git config core.hooksPath` returns `.githooks`.
- **Rationale**: Hook scripts under `.git/hooks/` are per-clone and untracked — a fresh clone has zero local enforcement until someone re-runs bootstrap. Shipping them in `.githooks/` and requiring `core.hooksPath` makes the local layer reproducible across clones; the rule itself catches anyone whose config drift would silently disable the hook.
- **Enforced by**: `tests/governance/rules/hooks-configured.sh`
- **Exceptions**: Projects using `husky` or the `pre-commit` framework should remove this rule and rely on the framework's tracked hook config instead.

## Amendment process

1. Open a PR that modifies this file **and** `tests/governance/rules/` in the same commit.
2. The PR description states *what* changed and *why* — link the incident, RFC, or discussion that motivated it.
3. Add an entry to the **Evolution Log** below.
4. At least one reviewer with governance authority approves.

## Evolution Log

<!-- Append, do not rewrite history. Format: YYYY-MM-DD — <author> — <one-line summary>. Link the PR. -->

- 2026-04-22 — @srikanth — Initial constitution bootstrapped via governance-bootstrap.
- 2026-04-22 — @srikanth — Add `plan-captured`: require `plans/*.md` with Goal/Steps sections so intent is captured alongside the diff.
- 2026-04-22 — @srikanth — Add `issues-tracked`: require `QUALITY.md` with Open + Resolved sections so bugs live in the system of record, not Slack.
- 2026-04-22 — @srikanth — Add **Compliance** section: explicit directive that humans, agents, and automation must satisfy every principle, guideline, and invariant — not just the mechanically enforced ones. Mirrored into the bootstrap template.
- 2026-04-22 — @srikanth — Add `hooks-configured`: move local hook scripts to tracked `.githooks/` and require `core.hooksPath=.githooks`, so a fresh clone gets the same local enforcement as every other contributor. Bootstrap skill updated to install hooks under `.githooks/` (not `.git/hooks/`).
- 2026-04-22 — @srikanth — Strengthen `plan-captured`: require substantive tracked changes to touch `plans/*.md` in the same change set, so missing plans fail mechanically instead of relying on repo memory.
- 2026-04-22 — @srikanth — Strengthen `conventional-commits`: require a trailing GitHub issue suffix like `(#123)` so every commit is traceable to a durable work item.
- 2026-04-22 — @srikanth — Add `agent-token-accounting`: agent-authored commits must carry token trailers and a matching row in `COSTS.md`, so the repo becomes the system-of-record for agent cost rather than per-contributor session transcripts. Dogfoods the opt-in rule shipped in [#14](https://github.com/Duaility/governance-kit/pull/14).
- 2026-04-22 — @srikanth — Refactor `agent-token-accounting` plumbing: move runtime detection, transcript reading, and `COSTS.md` append out of runtime-specific wrappers and into `scripts/governance/agent-accounting.sh` invoked from pre-commit, so `git commit` is the single entry point for agents and humans. Per-runtime readers live under `scripts/governance/runtimes/`. The pre-commit layer is load-bearing: staging `COSTS.md` there lands it in the commit's tree, which `prepare-commit-msg` cannot do.
- 2026-04-23 — @srikanth — Strengthen `agent-token-accounting` ledger: split prompt-cache traffic into its own `cache-create` and `cache-read` columns so the ledger is lossless (billing dollars and cache-hit-rate recoverable). Move ledger parse / sum / append / validate and trailer parse / cross-check into stdlib-only Python libs at `scripts/governance/lib/ledger.py` and `lib/trailers.py` — bash stays in charge of git plumbing, env detection, and argv walking, but schema-sensitive work uses named dataclass fields instead of positional `awk -F'\|'`. Trailer `Token-Input = input + cache_create` (excludes `cache_read`) to surface new work rather than cache rent. Legacy 8-column rows are accepted by the parser, so the migration is a one-time textual edit.
- 2026-04-23 — @srikanth — Tighten `agent-token-accounting` total invariant: `COSTS.md` `total` now equals `input + cache_create + output` (cache_read is tracked but excluded from total), so the ledger's headline number represents new work rather than cache rent. This makes `row.total == Token-Total` in the trailer by construction; `trailers.py` gained a matching cross-check to catch any future drift between the two. One live row was recomputed in place; zero-cache-read rows are unaffected.

## Escape hatches

Governance is enforced at two layers:

1. **Pre-commit hook** — `.githooks/pre-commit` runs `tests/governance/run.sh` before each commit (activated per-clone via `git config core.hooksPath .githooks`; the `hooks-configured` rule nags until you set it). Skip with `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` when a hotfix cannot wait.
2. **CI workflow** — `.github/workflows/governance.yml` runs the same tests on every PR and push to the default branch. CI cannot be skipped from a developer machine.

The hook is for speed; CI is for enforcement. If a commit lands with the hook skipped, CI will catch it.

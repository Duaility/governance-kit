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

### plan-per-issue

- **Rule**: Every tracked `plans/*.md` filename includes an `issue-<N>` token identifying the GitHub issue it plans for, and no two plan files share the same issue number.
- **Rationale**: Plans are the durable record of intent behind a change set. A one-to-one binding between plan and issue keeps the system of record unambiguous — reviewers jump from an issue to its single plan, and agents can detect whether an issue already has a plan before drafting a duplicate.
- **Enforced by**: `tests/governance/rules/plan-per-issue.sh`
- **Exceptions**: Per-file waiver — a line matching `governance: allow-plan-per-issue` (bare or inside an HTML comment) anywhere in the file exempts that plan. Used to grandfather plans that predate this rule.

### commit-issue-plan-match

- **Rule**: For every non-merge, non-revert commit in scope, the issue number in the commit subject's trailing `(#N)` matches an `issue-<N>` token on at least one `plans/*.md` file the commit adds or modifies. A commit that touches no `plans/*.md` fails this rule.
- **Rationale**: `conventional-commits` pins each commit to an issue and `plan-per-issue` pins each plan to an issue, but nothing cross-checks the two — a commit claiming `(#15)` while touching only issue #42's plan passes both rules in isolation. This rule closes that hole and, in doing so, subsumes the former `plan-captured` "substantive change must touch a plan" obligation under a stricter check (the plan must also be the *right* one for the commit's issue).
- **Enforced by**: `tests/governance/rules/commit-issue-plan-match.sh` (Mode B — CI walks merge-base → HEAD) and `.githooks/commit-msg` (Mode A — validates the pending commit against its staged diff).
- **Exceptions**: Merge commits and revert commits are exempt (mirrors `conventional-commits`). Per-commit waiver — a line `governance: allow-commit-issue-plan-match <reason>` in the commit body exempts that commit (reason required; a bare token does not waive).

### issues-tracked

- **Rule**: `QUALITY.md` exists at the repo root with a top-level `# ` heading and contains `## Open` and `## Resolved` sections.
- **Rationale**: Bugs and quality observations discovered between releases rot in Slack and memory. Tracking them in a file keeps them in the system of record, diff-auditable, and greppable by agents and humans alike.
- **Enforced by**: `tests/governance/rules/issues-tracked.sh`
- **Exceptions**: none. Empty sections are allowed; the file itself is the contract.

### agent-token-accounting

- **Rule**: Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Token-Total = Token-Input + Token-Output`, and has exactly one matching append-only row in `COSTS.md` whose numbers agree with the trailers (`Token-Input == row.input + row.cache_create`, `Token-Output == row.output`, `Token-Total == row.new_work`). `COSTS.md` rows are well-formed — 12 columns (`cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note`) with `new-work == input + cache_create + output` (cache_read is tracked but deliberately excluded from new-work) and `cost-usd` either empty or a non-negative float — and `Cost-Key` is unique within the file. Legacy rows are accepted: v2 (10 cols, pre-model/cost-usd) and v1 (8 cols, pre-cache-split), validated under the same `new-work` invariant.
- **Rationale**: This repo is agent-driven only — every change to the tree is produced through an agent runtime, so an untrailered commit is a bug, not an allowed mode. Mandatory trailers turn `COSTS.md` from a best-effort opt-in into the single system-of-record for agent cost and provenance. Token trailers give branch-time provenance reviewers can read; `COSTS.md` is the durable ledger that survives squash merges and keeps the audit trail in the repo rather than on a contributor's laptop. Splitting cache traffic into its own columns keeps the ledger lossless — billing dollars and cache-hit-rate are recoverable from `cache_create` and `cache_read` — but `new-work` deliberately excludes `cache_read` so the token headline represents new work, not cache rent. Raw token sums across columns with a 50× price ratio (output vs cache-read) don't compare across commits, so the ledger carries a model-priced `cost-usd` column computed from `scripts/governance/lib/rates.py` — that is the only single-number headline that makes sense to line up across commits with different cache mixes. The trailer stays token-only: `Token-Input = input + cache_create`, `Token-Total = Token-Input + Token-Output`, and by construction `Token-Total == row.new_work`. Friction is absorbed by the runtime-aware pre-commit hook: `git commit` is the entry point for every contributor; the hook detects the runtime, reads the transcript, appends the `COSTS.md` row, and `prepare-commit-msg` stamps matching trailers.
- **Enforced by**: `tests/governance/rules/agent-token-accounting.sh` (validates history, shells out to `scripts/governance/lib/ledger.py` for ledger shape + `scripts/governance/lib/trailers.py` for trailer shape and cross-check math), `scripts/governance/agent-accounting.sh` invoked from `.githooks/pre-commit` (detects the runtime, reads the transcript, and appends the `COSTS.md` row in-tree via `lib/ledger.py`), and `.githooks/prepare-commit-msg` (stamps matching trailers from the pre-commit handoff).
- **Exceptions**: Merge commits and revert commits are exempt (mirrors `conventional-commits` semantics — merges detected via `git log --format=%P` showing >1 parent, reverts via subject starting with `Revert "`).

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
- 2026-04-23 — @srikanth — Evolve `agent-token-accounting` schema to v3 (12 columns): add a `model` column (runtime-reported, e.g. `claude-sonnet-4-5`) and a `cost-usd` column computed from `scripts/governance/lib/rates.py` using **all four** token columns (cache_read included — that's where cache rent shows up). Rename `total` to `new-work` to stop pretending the raw token sum is a single comparable headline; the dollar column is the only number that lines up across commits with different cache mixes. Runtime readers now emit 6 values (add `<model>`); `agent-accounting.sh` passes model into the ledger; `lib/ledger.py` recomputes `new_work` and looks up `cost_usd` at append time. Legacy v2 (10 cols) and v1 (8 cols) rows are still parsed under the same `new_work` invariant; existing rows in `COSTS.md` were migrated in place by inserting empty `model`/`cost-usd` cells (token values unchanged since v2 `total` already matched the `new_work` semantic).
- 2026-04-23 — @srikanth — Add `plan-per-issue`: require each `plans/*.md` filename to carry an `issue-<N>` token and forbid duplicate plans for the same issue, so the plan↔issue binding is one-to-one. Closes [#15](https://github.com/Duaility/governance-kit/issues/15).
- 2026-04-23 — @srikanth — Flip `agent-token-accounting` from opt-in to mandatory: every non-merge, non-revert commit must now carry the full token-trailer set and a matching `COSTS.md` row, instead of only those declaring `Agent:`. This repo is agent-driven only — an untrailered commit was a silent hole in the ledger; now it's a CI failure. Merge and revert commits are exempt (mirrors `conventional-commits`). Also fixed a latent subshell bug in the per-commit walk: violations from `validate_commit_message` were being swallowed by a pipe (`printf | fn`); switched to a here-string so `violation` calls bubble up. Removed the `merge-base == HEAD` fallback that re-validated HEAD alone — it was a smoke-test convenience under opt-in semantics; under mandatory semantics it would re-flag historical commits already on `main`. In-flight branches without trailers will fail CI after this lands and need to be re-committed through the runtime-aware pre-commit hook. Closes [#17](https://github.com/Duaility/governance-kit/issues/17).
- 2026-04-23 — @srikanth — Replace `plan-captured` with `commit-issue-plan-match`: the new rule cross-validates each commit's trailing `(#N)` against the `issue-<N>` tokens on the `plans/*.md` files it actually touched, closing the hole where `conventional-commits`, `plan-per-issue`, and `plan-captured` each checked one link in isolation and let a commit claim `(#15)` while touching only issue #42's plan. `plan-captured`'s three checks collapse: "`plans/` exists with ≥1 `.md`" is trivially implied once every commit must touch a plan; "substantive change must touch a plan" is subsumed and strengthened (the plan must also carry the *matching* issue number); the `## Goal` / `## Steps` structure check was stylistic and is dropped. Landed in a single amendment — the rule that subsumes and the rule that retires travel together, or the intervening state is a lie. Existing `governance: allow-plan-captured` waiver lines are left as harmless comments. Closes [#19](https://github.com/Duaility/governance-kit/issues/19).
- 2026-04-23 — @srikanth — Tighten the pack shape so each rule is an **atom**: every rule is now a self-contained folder `rules/<rule-id>/` carrying `rule.yaml` (scalar metadata — category / recommended / summary / surface / hook / optional `always_install`), `check.sh` (the executable test), `constitution.md` (the Invariant subsection), and `evals/test.sh`. `pack.yaml` keeps only pack identity and the preset graph — the flat `rules:` block is gone, as are the sibling `constitution-snippets/` and `evals/` directories. Adding, moving, or deleting a rule is now a single directory operation; the loader discovers rules by listing folders rather than walking a YAML index. Loader (`packs.sh`) validates the folder shape; `install_rule` in the eval harness, `scripts/test-packs.sh`, `governance-bootstrap/SKILL.md`, and the pack-authoring reference all updated to match. Still under [#23](https://github.com/Duaility/governance-kit/issues/23).
- 2026-04-23 — @srikanth — Restructure `governance-bootstrap` around extensible **rule packs**. Rule scripts, Invariant snippets, manifests (`pack.yaml`), and pass/fail evals now live together under `governance-bootstrap/assets/packs/<pack>/`. Two packs ship in-tree: `core` (general-purpose rules, always selected) and `agent-governance` (promoted from this repo's `tests/governance/rules/` — `plan-per-issue`, `commit-issue-plan-match`, `issues-tracked`, `agent-token-accounting`). Bootstrap activation now discovers packs, unions their menus, applies a per-pack preset (`minimal` / `standard` / `strict`), and generates dispatcher hooks from manifest `hook:` declarations carrying an ownership marker (`# governance-kit:managed pack-version=<v>`) so re-runs are idempotent but unmarked pre-existing hooks still trip the collision detector. Introduces `scripts/test-packs.sh` (validates manifests, runs every eval, smoke-tests hook generation) and wires it into CI. Flat `assets/tests-bash/rules/` is gone. New reference `governance-bootstrap/references/AUTHORING_PACKS.md` documents pack schema, eval harness, and versioning for third-party packs. Also fixes a portability bug in `no-orphan-todos` discovered while authoring evals — `\b(TODO|FIXME)\b` is a silent no-op under BSD `git grep` on macOS; switched to portable `git grep -nwE '(TODO|FIXME)'`. Closes [#23](https://github.com/Duaility/governance-kit/issues/23).

## Escape hatches

Governance is enforced at two layers:

1. **Pre-commit hook** — `.githooks/pre-commit` runs `tests/governance/run.sh` before each commit (activated per-clone via `git config core.hooksPath .githooks`; the `hooks-configured` rule nags until you set it). Skip with `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` when a hotfix cannot wait.
2. **CI workflow** — `.github/workflows/governance.yml` runs the same tests on every PR and push to the default branch. CI cannot be skipped from a developer machine.

The hook is for speed; CI is for enforcement. If a commit lands with the hook skipped, CI will catch it.

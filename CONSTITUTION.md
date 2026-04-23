<!-- last-verified: 2026-04-23 -->

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

- **Rule**: `CONSTITUTION.md` exists at the repo root, is non-empty, and is at least 10 lines long.
- **Rationale**: Governance without a discoverable source of truth is tribal knowledge. Every other invariant points back to this file.
- **Enforced by**: `tests/governance/rules/constitution-exists/check.sh`
- **Exceptions**: none.

### no-secrets

- **Rule**: No tracked file contains a plaintext AWS / GCP / GitHub / Slack / Stripe token or a private-key block matching the rule's patterns.
- **Rationale**: A leaked credential in git history is a credential compromised — rotation is the only recourse. The cheapest moment to catch it is before the commit lands.
- **Enforced by**: `tests/governance/rules/no-secrets/check.sh`
- **Exceptions**: For intentional fixtures or lab credentials, append `# governance: allow-no-secrets <reason>` to the line. The waiver is visible in `git blame`.

### dotenv-gitignored

- **Rule**: `.env` is listed in `.gitignore` and is not tracked.
- **Rationale**: `.env` is where local secrets live. If it is not in `.gitignore`, one careless `git add .` leaks production credentials.
- **Enforced by**: `tests/governance/rules/dotenv-gitignored/check.sh`
- **Exceptions**: none.

### workflows-hardened

- **Rule**: Every `.github/workflows/*.yml` declares a `permissions:` block and pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-character commit SHA.
- **Rationale**: A compromised third-party action with write access is a supply-chain vulnerability. Tag pins are mutable; SHA pins are not. A missing `permissions:` block inherits a broad default that most jobs do not actually need.
- **Enforced by**: `tests/governance/rules/workflows-hardened/check.sh`
- **Exceptions**: Append `# governance: allow-workflows-hardened <reason>` to the offending line for documented exceptions.

### no-broken-internal-doc-links

- **Rule**: Every relative-path markdown link in a tracked `.md` file resolves to an existing file.
- **Rationale**: Broken links rot silently — the doc still renders, just incorrectly. A link that once pointed at a real file and now doesn't signals that the doc has drifted from the code it describes.
- **Enforced by**: `tests/governance/rules/no-broken-internal-doc-links/check.sh`
- **Exceptions**: none.

### no-large-files

- **Rule**: No tracked file exceeds 5 MB. Override via `GOVERNANCE_MAX_FILE_SIZE_MB`.
- **Rationale**: Binary blobs in git are a one-way street — history retains them forever, clone times swell, and mirroring slows. Keep large assets in object storage and track the pointer.
- **Enforced by**: `tests/governance/rules/no-large-files/check.sh`
- **Exceptions**: Raise the threshold via `GOVERNANCE_MAX_FILE_SIZE_MB` for repo-wide tuning.

### no-committed-build-artifacts

- **Rule**: No tracked file matches the build-artifact denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files.
- **Rationale**: Build output in git is noise — it rots fast, conflicts often, and obscures real changes in diffs. If a build artifact must ship, publish it as a release asset, not a tracked file.
- **Enforced by**: `tests/governance/rules/no-committed-build-artifacts/check.sh`
- **Exceptions**: none.

### no-merge-conflict-markers

- **Rule**: No tracked file contains a merge-conflict marker (`<<<<<<<`, `=======`, or `>>>>>>>` at line start).
- **Rationale**: Merge markers committed to the tree are almost always an accident — the author ran `git add .` before finishing the conflict resolution. Zero-false-positive check, installed unconditionally.
- **Enforced by**: `tests/governance/rules/no-merge-conflict-markers/check.sh`
- **Exceptions**: none.

### hooks-configured

- **Rule**: `.githooks/pre-commit` is tracked and executable. If `conventional-commits` is installed, `.githooks/commit-msg` likewise. `core.hooksPath` is set to `.githooks` in the repo's local git config.
- **Rationale**: Hooks that live under `.git/hooks/` are per-clone and never shared. Tracking them under `.githooks/` and pointing `core.hooksPath` at that directory is what makes every other local check actually fire on a fresh clone.
- **Enforced by**: `tests/governance/rules/hooks-configured/check.sh`
- **Exceptions**: Not installed when the repo uses an existing hook framework (husky, pre-commit.com) — that framework has its own tracked hook-config mechanism.

### agents-md-exists

- **Rule**: `AGENTS.md` exists at the repo root, is between 30 and 250 lines long, and contains at least three markdown links to other documents in the repo.
- **Rationale**: Agents (and humans arriving cold) need a single discoverable entry point that routes them to the rest of the system of record. Too short → useless stub; too long → nobody reads it.
- **Enforced by**: `tests/governance/rules/agents-md-exists/check.sh`
- **Exceptions**: none.

### conventional-commits

- **Rule**: Commit messages match `<type>(scope)?!?: subject (#123)`. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`.
- **Rationale**: A trailing `(#123)` anchors every commit to a GitHub issue; the typed prefix keeps changelogs scannable. Together they make `git log` a readable audit trail instead of a stream of "fix stuff".
- **Enforced by**: `tests/governance/rules/conventional-commits/check.sh` (also wired into the `.githooks/commit-msg` dispatcher).
- **Exceptions**: Merge and revert commits are skipped automatically.

### doc-freshness

- **Rule**: Docs opted into `tests/governance/freshness.conf` carry a `<!-- last-verified: YYYY-MM-DD -->` marker dated within the last 90 days (configurable). No-op if the config file is absent.
- **Rationale**: Critical runbooks and onboarding docs decay. A periodic "someone re-read this" checkpoint keeps them honest — if the deadline passes, either the doc still reflects reality (bump the date) or it doesn't (fix it).
- **Enforced by**: `tests/governance/rules/doc-freshness/check.sh`
- **Exceptions**: Remove a doc from `freshness.conf` to opt it out entirely.

### plan-per-issue

- **Rule**: Every tracked `plans/*.md` filename includes an `issue-<N>` token identifying the GitHub issue it plans for, and no two plan files share the same issue number.
- **Rationale**: Plans are the durable record of intent behind a change set. A one-to-one binding between plan and issue keeps the system of record unambiguous — reviewers jump from an issue to its single plan, and agents can detect whether an issue already has a plan before drafting a duplicate.
- **Enforced by**: `tests/governance/rules/plan-per-issue/check.sh`
- **Exceptions**: Per-file waiver — a line matching `governance: allow-plan-per-issue` (bare or inside an HTML comment) anywhere in the file exempts that plan. Used to grandfather plans that predate this rule.

### commit-issue-plan-match

- **Rule**: For every non-merge, non-revert commit in scope, the issue number in the commit subject's trailing `(#N)` matches an `issue-<N>` token on at least one `plans/*.md` file the commit adds or modifies. A commit that touches no `plans/*.md` fails this rule.
- **Rationale**: `conventional-commits` pins each commit to an issue and `plan-per-issue` pins each plan to an issue, but nothing cross-checks the two — a commit claiming `(#15)` while touching only issue #42's plan passes both rules in isolation. This rule closes that hole and, in doing so, subsumes the former `plan-captured` "substantive change must touch a plan" obligation under a stricter check (the plan must also be the *right* one for the commit's issue).
- **Enforced by**: `tests/governance/rules/commit-issue-plan-match/check.sh` (Mode B — CI walks merge-base → HEAD) and `.githooks/commit-msg` (Mode A — validates the pending commit against its staged diff).
- **Exceptions**: Merge commits and revert commits are exempt (mirrors `conventional-commits`). Per-commit waiver — a line `governance: allow-commit-issue-plan-match <reason>` in the commit body exempts that commit (reason required; a bare token does not waive).

### issues-tracked

- **Rule**: `QUALITY.md` exists at the repo root with a top-level `# ` heading and contains `## Open` and `## Resolved` sections.
- **Rationale**: Bugs and quality observations discovered between releases rot in Slack and memory. Tracking them in a file keeps them in the system of record, diff-auditable, and greppable by agents and humans alike.
- **Enforced by**: `tests/governance/rules/issues-tracked/check.sh`
- **Exceptions**: none. Empty sections are allowed; the file itself is the contract.

### agent-token-accounting

- **Rule**: Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Token-Total = Token-Input + Token-Output`, and has exactly one matching append-only row in `COSTS.md` whose numbers agree with the trailers (`Token-Input == row.input + row.cache_create`, `Token-Output == row.output`, `Token-Total == row.new_work`). `COSTS.md` rows are well-formed — 12 columns (`cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note`) with `new-work == input + cache_create + output` (cache_read is tracked but deliberately excluded from new-work) and `cost-usd` either empty or a non-negative float — and `Cost-Key` is unique within the file. Legacy rows are accepted: v2 (10 cols, pre-model/cost-usd) and v1 (8 cols, pre-cache-split), validated under the same `new-work` invariant.
- **Rationale**: A repo that opts into agent-governance is committing to "every change to the tree is produced through an agent runtime", so an untrailered commit is a bug, not an allowed mode. Mandatory trailers turn `COSTS.md` from a best-effort opt-in into the single system-of-record for agent cost and provenance. Token trailers give branch-time provenance reviewers can read; `COSTS.md` is the durable ledger that survives squash merges. Splitting cache traffic into its own columns keeps the ledger lossless; `new-work` deliberately excludes `cache_read` so the token headline represents new work, not cache rent. The `cost-usd` column (computed from the sibling `lib/rates.py`) is the only single-number headline that compares across commits with different cache mixes.
- **Enforced by**: `tests/governance/rules/agent-token-accounting/check.sh`, plus sibling helpers in the agent-token-accounting rule folder — `hooks/pre-commit.sh` writes the matching ledger row (using `runtimes/<runtime>.sh` to read the agent's transcript), and `hooks/prepare-commit-msg.sh` stamps matching trailers from the pre-commit handoff. The bootstrap hook generator wires all three into `.githooks/pre-commit`, `.githooks/commit-msg`, and `.githooks/prepare-commit-msg` respectively.
- **Exceptions**: Merge commits and revert commits are exempt (merges detected via `git log --format=%P` showing >1 parent, reverts via subject starting with `Revert "`).

> **Installation note.** The rule folder is self-contained — `lib/` (ledger, trailers, rates), `hooks/` (pre-commit side effects, prepare-commit-msg stamping), and `runtimes/` (per-runtime transcript readers) all live inside the rule folder and are installed as a unit. See `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md` for runtime wiring.

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
- 2026-04-23 — @srikanth — Make each rule a true self-contained atom. Everything a rule needs — the `check.sh`, the Invariant snippet, the eval, plus any `lib/` (shared Python libs), `hooks/` (per-hook side-effect scripts), and `runtimes/` (per-runtime helpers) — now lives inside `rules/<id>/`. Install shape changed from flat `tests/governance/rules/<id>.sh` to folder-per-rule `tests/governance/rules/<id>/check.sh`, and `install_rule` copies the whole rule folder (minus `evals/`). The hook generator is now generic: it discovers rule-owned helpers by looking for `rules/<id>/hooks/<kind>.sh` and wires them in alongside `check.sh`, with no hardcoded references to any specific rule. Migrated `agent-token-accounting` in place — `scripts/governance/{lib,runtimes,agent-accounting.sh}` moved into the rule folder as `lib/`, `runtimes/`, and `hooks/pre-commit.sh`; the old `assets/scripts/` and `assets/githooks/pre-commit`+`commit-msg` are gone (the generator owns the dispatchers, and `prepare-commit-msg` relocated into the rule's `hooks/`). Adding, moving, or deleting a rule is now a single directory operation; a rule with Python libs no longer leaks into a top-level `scripts/` tree shared across unrelated rules. Still under [#23](https://github.com/Duaility/governance-kit/issues/23).
- 2026-04-23 — @srikanth — Restructure `governance-bootstrap` around extensible **rule packs**. Rule scripts, Invariant snippets, manifests (`pack.yaml`), and pass/fail evals now live together under `governance-bootstrap/assets/packs/<pack>/`. Two packs ship in-tree: `core` (general-purpose rules, always selected) and `agent-governance` (promoted from this repo's `tests/governance/rules/` — `plan-per-issue`, `commit-issue-plan-match`, `issues-tracked`, `agent-token-accounting`). Bootstrap activation now discovers packs, unions their menus, applies a per-pack preset (`minimal` / `standard` / `strict`), and generates dispatcher hooks from manifest `hook:` declarations carrying an ownership marker (`# governance-kit:managed pack-version=<v>`) so re-runs are idempotent but unmarked pre-existing hooks still trip the collision detector. Introduces `scripts/test-packs.sh` (validates manifests, runs every eval, smoke-tests hook generation) and wires it into CI. Flat `assets/tests-bash/rules/` is gone. New reference `governance-bootstrap/references/AUTHORING_PACKS.md` documents pack schema, eval harness, and versioning for third-party packs. Also fixes a portability bug in `no-orphan-todos` discovered while authoring evals — `\b(TODO|FIXME)\b` is a silent no-op under BSD `git grep` on macOS; switched to portable `git grep -nwE '(TODO|FIXME)'`. Closes [#23](https://github.com/Duaility/governance-kit/issues/23).
- 2026-04-23 — @srikanth — Re-bootstrap after `governance-reset`: reinstall `core + agent-governance` at the `standard` preset (16 rules including `doc-freshness`, which prior hand-customization had removed). Clean slate for the constitution text; evolution log and principles preserved.

## Escape hatches

Governance is enforced at two layers:

1. **Pre-commit hook** — runs `tests/governance/run.sh` before each commit. Skip with `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` when a hotfix cannot wait.
2. **CI workflow** — `.github/workflows/governance.yml` runs the same tests on every PR and push to the default branch. CI cannot be skipped from a developer machine.

The hook is for speed; CI is for enforcement. If a commit lands with the hook skipped, CI will catch it.

# Directives Catalog

Every directive lives in a **pack**. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers packs at activation, unions their menus, and installs the selected subset.

One pack ships in-tree:

| Pack | Location | Purpose | Default? |
|---|---|---|---|
| `governance-kit/core` | `governance/assets/packs/core/` | General-purpose directives plus the full agent audit chain (`receipt-per-issue` → `commit-issue-receipt-match` → `issue-templates` → `issues-tracked` → `agent-token-accounting` → `agent-steering-accounting`). | Always selected — cannot be deselected. |

Community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`. For authoring a **third-party pack**, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

---

## `governance-kit/core` pack

Minimum floor of hygiene — required docs exist, secrets aren't committed, workflows are pinned, merge markers are caught. The `minimal` / `standard` / `strict` presets add progressively more commit-time discipline on top of the same baseline.

The three consolidated directives (`required-docs`, `repo-hygiene`, `secrets-hygiene`) each expose a `GOVERNANCE_<NAME>_DISABLE` env var for per-sub-check opt-outs — the catalog below lists the sub-check keys under each entry.

### Foundation
| Directive | What it checks |
|---|---|
| `required-docs` | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links, **and a link to `CONSTITUTION.md`** so the file is a map to the bedrock durable docs rather than a standalone manual); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants at repo root, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). To carve out a sub-check for your repo, use `governance directive modify` (or `governance directive remove`). |
| `version-consistency` | The kit version agrees across the install: every managed-file `# governance-kit:managed kit-version=<v>` marker equals `.governance/install.yaml`'s `kit_version`. Managed set derived from the manifest (`tests_dir`'s `run.sh`/`lib.sh`, `ci_workflow`, `enable_governance_script`, `.githooks/*`). No-op when the manifest or its `kit_version` is absent. Repair path: `governance kit update`. |

### Security
| Directive | What it checks |
|---|---|
| `secrets-hygiene`    | Rolled-up secret-scanning. Sub-checks: `no-secrets` (heuristic scan for AWS / GCP / GitHub / Slack / Stripe / private-key patterns; waiver `# governance: allow-secrets-hygiene <reason>`); `dotenv` (`.env` is not tracked **and** listed in `.gitignore`). To carve out a sub-check, use `governance directive modify`. |
| `workflows-hardened` | Every `.github/workflows/*.yml` declares a `permissions:` block **and** pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-char commit SHA. |

### System of record
| Directive | What it checks |
|---|---|
| `no-broken-internal-doc-links`  | Every relative-path markdown link in tracked `.md` files resolves to an existing file. |
| `doc-freshness`                 | Docs listed in `.governance/freshness.conf` carry `<!-- last-verified: YYYY-MM-DD -->` within 90 days (configurable). No-op if the config file is absent. |

### Commit hygiene
| Directive | What it checks |
|---|---|
| `commit-message-format` | Commit subjects match `<type>(scope)?!?: subject (#123)` — Conventional Commits prefix **plus** a trailing GitHub issue reference. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`. Installs a `commit-msg` git hook. |
| `no-orphan-todos`      | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |

### Quality
| Directive | What it checks |
|---|---|
| `repo-hygiene` | Rolled-up hygiene greps. **`always_install: true`** — bypasses the menu. Sub-checks: `merge-markers` (no `<<<<<<<` / `=======` / `>>>>>>>` at line start); `large-files` (no tracked file > 5 MB, override via `GOVERNANCE_MAX_FILE_SIZE_MB`); `build-artifacts` (denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files); `debug-statements` (no `console.log` / `debugger` / `breakpoint()` / `import pdb` / `dbg!` / `fmt.Println` in non-test source; line-level waiver `# governance: allow-repo-hygiene <reason>`); `file-size-limit` (no source file > 500 lines, override via `GOVERNANCE_FILE_SIZE_LIMIT`; file-level waiver `governance: allow-repo-hygiene file-size-limit <reason>` in the first 10 lines, any comment syntax). To carve out a sub-check, use `governance directive modify`. |

## Agent audit chain

For repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, ...). The directives form a chain: issue creation uses a durable template, issues are tracked, every issue has exactly one receipt, every commit matches its receipt, and every commit carries its cost. Breaking any link makes the chain non-auditable — the `standard` preset bundles the full chain.

### Agent discipline
| Directive | What it checks |
|---|---|
| `receipt-per-issue`        | Every tracked `receipts/*.md` file carries a unique `issue-<N>` token in its filename **and** includes four Markdown sections — `## Checklist`, `## What changed`, `## Out of scope`, `## Verification` — naming the work plan, the surface area touched, the deferred work, and how completion will be judged. The `## Checklist` mirrors the GitHub issue's checklist; each `- [x]` item's text must appear (case-insensitive substring) in `## What changed` or `## Verification` (the local trust boundary that lets a reviewer confirm each claimed-done item maps to described work without leaving the diff). Unchecked items are unconstrained. A fifth section, `## Decisions` (off-spec decisions / forced changes / tradeoffs a reviewer should know about; write "None" when the work followed the spec exactly), is required **only on receipts added in the current change set** — staged additions at pre-commit, `base..HEAD` additions in CI — so pre-existing receipts are grandfathered and never retroactively swept. `## Decisions` is presence-only with no crosswalk. Waiver: `governance: allow-receipt-per-issue <reason>` exempts a whole receipt (stub / WIP) from all shape rules. Receipts are post-implementation audit traces, distinct from agent-runtime plan-mode plans. |
| `commit-issue-receipt-match` | Each commit's anchor — trailing `(#N)` in the subject or any `Issue: #N` body trailer — matches an `issue-<N>` token on a `receipts/*.md` file it touches. Installs a `commit-msg` hook (Mode A) and runs in CI walking merge-base→HEAD (Mode B). Per-commit waiver: `governance: allow-commit-issue-receipt-match <reason>` in the commit body. |
| `doc-integrity`            | **`always_install: true` — bypasses the menu, mandatory in every install; `.governance/integrity.conf` is seeded with all standard rules enabled.** Makes the system-of-record documents listed in `.governance/integrity.conf` append-only relative to the change set's default-branch baseline (a rule is a no-op until its document exists). Three modes: `frozen-files <glob>` (each file immutable once on the trunk; new files OK — e.g. `receipts/*.md`), `append-only <file>` (baseline must be a byte-prefix of current — e.g. `COSTS.md`/`STEERING.md` ledgers), `frozen-section <file> <heading>` (baseline lines under the heading survive verbatim; rest of file free — e.g. `QUALITY.md` Resolved, `CONSTITUTION.md` Evolution Log). Branch-authored content is absent at the baseline, so it stays editable until it merges. Sibling of `commit-issue-receipt-match` — same `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Path-scoped waiver: `governance: allow-doc-integrity <path> <reason>` in the commit body for a coordinated reviewed rewrite. |
| `issue-templates`          | `.github/ISSUE_TEMPLATE/` contains proposal and bug issue forms plus config. Blank issues are disabled, proposal issues require Context / Decision / Scope / Acceptance criteria / Validation / Open questions, and bug issues require the core defect-report fields. Ships the templates under `install-assets/.github/ISSUE_TEMPLATE/`. |
| `issues-tracked`           | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md` so a newly bootstrapped repo starts green. |
| `agent-token-accounting`   | Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Total = Input + Output`, and has exactly one matching append-only row in `COSTS.md`. Ships `install-assets/COSTS.md` plus directive-owned pre-commit and prepare-commit-msg helpers. Runtime-agnostic — see [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) for Codex / Claude Code wiring. |
| `agent-steering-accounting` | **`always_install: true` — bypasses the menu, mandatory in every install.** Every non-merge, non-revert commit stamps the always-on summary triple (`Steer-Count`, `Steer-Types`, `Steer-Tiers`); the numbers tally the rows newly added to append-only `STEERING.md` by the commit, and each newly-added row's `commit |` cell matches the pending subject. Independent of `agent-token-accounting` — installation is the gate, not the presence of an `Agent:` trailer. Detects human-steering events from the active session JSONL: interrupts (`tier: structural`) and semantic corrections classified by shelling out to the active runtime's headless CLI (`tier: classifier`, with regex `tier: lexical` as a silent fallback). Per-event `Steer-Key:` trailers were retired in #66 — the row → commit join uses the `commit |` column. No internal env-var gates — installation is the gate. Ships `install-assets/STEERING.md`, a Claude Code transcript reader, and pre-commit + prepare-commit-msg helpers. Privacy caveat — `user-reason` cells contain verbatim operator text; redact via the directive's classifier hook rather than skipping the directive. See [AGENT_STEERING_ACCOUNTING.md](AGENT_STEERING_ACCOUNTING.md). |

### `governance-kit/core` presets (full)

| Preset | Directives |
|---|---|
| `minimal`  | `required-docs`, `secrets-hygiene`, `repo-hygiene`, `workflows-hardened`, `no-broken-internal-doc-links` |
| `standard` | *minimal* + `commit-message-format`, `version-consistency`, `doc-freshness`, `issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`, `doc-integrity`, `agent-token-accounting`, `agent-steering-accounting` |
| `strict`   | *standard* + `no-orphan-todos` |

`agent-steering-accounting`, `repo-hygiene`, and `doc-integrity` are `always_install: true` — they install regardless of preset selection. The agent audit chain is mandatory in this kit's model because every commit is agent-authored: token-spend without steering coverage hides the human corrections that produced the cost, and `doc-integrity` keeps the chain's own artifacts (receipts, ledgers, logs) append-only so the record can't be quietly rewritten. `doc-integrity` reads `.governance/integrity.conf`, which is seeded with all standard rules enabled and is a no-op for any document not present.

---

## In-source waivers

Line-level directives respect a trailing comment: `governance: allow-<directive-name> <reason>`.

```python
api_key = "AKIA..."  # governance: allow-no-secrets INFRA-1247 — lab fixture
```

Waivers are visible in `git blame` and searchable by design. Only use them for documented, intentional exceptions.

---

## Adding a new directive to an existing pack

1. Create `<pack-root>/<pack>/directives/<id>/` (where `<pack-root>` is `governance/assets/packs/` for the kit-bundled `governance-kit/core` pack, or your own pack's source tree for a community pack hosted in its own repo) and populate it:
   - `check.sh` — the bash test, `chmod +x`.
   - `constitution.md` — four sections: **Directive**, **Rationale**, **Enforced by**, **Exceptions**.
   - `directive.yaml` — scalar fields:
     ```yaml
     category: <Foundation|Security|SystemOfRecord|CommitHygiene|Quality|AgentDiscipline|...>
     recommended: true|false
     summary: <one-line menu description>
     surface: repo-state | change-set
     hook: pre-commit | commit-msg | prepare-commit-msg | none
     # always_install: true   # optional; reserved to the `governance-kit/core` pack
     # requires_hook_strategy: githooks   # optional environment filter
     ```
   - `install-assets/` — optional files copied into the target repo before the first governance run. Use this for required seed files like `QUALITY.md` or `COSTS.md`; do not hide seed files in skill-specific special cases.
   - `evals/test.sh` — pass + fail fixtures using `eval-lib.sh`.
2. If the directive should be part of a preset, add its id to the relevant block (`minimal` / `standard` / `strict`) in the pack's `pack.yaml`. The `directives:` block no longer lives there — directive metadata comes from each directive's `directive.yaml`.
3. Run `bash scripts/test-packs.sh` — it validates every directive folder, installs `governance-kit/governance-kit/core.standard` into a fresh repo and runs it, runs every eval, and smoke-tests hook generation.
4. Document the directive in this file under the pack's category table.

For directives that belong in a new pack, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

### Directive template

```bash
#!/usr/bin/env bash
# Directive: <one-line statement of the directive>
# Rationale: <why it matters — link to an incident if possible>
set -u
source "$(dirname "$0")/../../lib.sh"
directive_start "<directive-id>"    # must match the parent folder name
require_git

# ── your check ───────────────────────────────────────────────
# On every violation: call `violation "<file>:<line> — <message>"`
# Support waivers:     has_waiver "$file" "$line_no" "<directive-id>" && continue
# ─────────────────────────────────────────────────────────────

directive_end
```

Every directive should be:

- **Deterministic** — same repo state, same result.
- **Fast** — every directive runs on every commit. Keep it under a second when possible.
- **Specific** — a violation message should name the file, line, and reason. `"✗ bad code somewhere"` is worthless.
- **Waivable when warranted** — if there are legitimate exceptions, support the `governance: allow-<directive>` waiver comment so they're auditable.
- **Matched to the real policy surface** — if the policy is about each substantive change, prefer a change-set-aware check over a repo-exists proxy.

## Authoring guardrail

Before you ship a new directive, ask this explicitly:

> Is this directive about the state of the repository, or about what each change set must carry?

Use:

- **repo-state checks** (`surface: repo-state`) for things like `README.md exists`, `SECURITY.md exists`, `workflows pin actions`
- **change-set-aware checks** (`surface: change-set`) for things like `this change must update a plan`, `this sensitive code change must update a doc`, or `this path change must touch an approval file`

If you pick a repo-state check for a change-set obligation, the directive will create false confidence. Do not do that.

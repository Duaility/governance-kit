# Directives Catalog

Every directive lives in a **pack**. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers packs at activation, unions their menus, and installs the selected subset.

Two packs ship in-tree, each at its own root:

| Pack | Location | Purpose | Default? |
|---|---|---|---|
| `core` | `governance/assets/packs/core/` | General-purpose directives usable in any repo. | Always selected — cannot be deselected. |
| `duaility/agent-governance` | `extensions/packs/agent-governance/` | Directives for repos operating under agent-driven development (issue anchors, plans, token accounting). | Opt-in per-repo. |

`core` is the kit's bundled-in pack. `extensions/packs/` is the monorepo home for community-shaped packs — authored with scoped `<author>/<slug>` ids and installed through `governance pack add` as if hosted in their own repo.

For authoring a **third-party pack**, see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

---

## `core` pack

Minimum floor of hygiene — required docs exist, secrets aren't committed, workflows are pinned, merge markers are caught. The `minimal` / `standard` / `strict` presets add progressively more commit-time discipline on top of the same baseline.

The three consolidated directives (`required-docs`, `repo-hygiene`, `secrets-hygiene`) each expose a `GOVERNANCE_<NAME>_DISABLE` env var for per-sub-check opt-outs — the catalog below lists the sub-check keys under each entry.

### Foundation
| Directive | What it checks |
|---|---|
| `required-docs` | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links, **and a link to `CONSTITUTION.md`** so the file is a map to the bedrock durable docs rather than a standalone manual); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants at repo root, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). To carve out a sub-check for your repo, use `governance directive modify` (or `governance directive remove`). |

### Security
| Directive | What it checks |
|---|---|
| `secrets-hygiene`    | Rolled-up secret-scanning. Sub-checks: `no-secrets` (heuristic scan for AWS / GCP / GitHub / Slack / Stripe / private-key patterns; waiver `# governance: allow-secrets-hygiene <reason>`); `dotenv` (`.env` is not tracked **and** listed in `.gitignore`). To carve out a sub-check, use `governance directive modify`. |
| `workflows-hardened` | Every `.github/workflows/*.yml` declares a `permissions:` block **and** pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-char commit SHA. |

### System of record
| Directive | What it checks |
|---|---|
| `no-broken-internal-doc-links`  | Every relative-path markdown link in tracked `.md` files resolves to an existing file. |
| `doc-freshness`                 | Docs listed in `tests/governance/freshness.conf` carry `<!-- last-verified: YYYY-MM-DD -->` within 90 days (configurable). No-op if the config file is absent. |

### Commit hygiene
| Directive | What it checks |
|---|---|
| `commit-message-format` | Commit subjects match `<type>(scope)?!?: subject (#123)` — Conventional Commits prefix **plus** a trailing GitHub issue reference. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`. Installs a `commit-msg` git hook. |
| `no-orphan-todos`      | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |

### Quality
| Directive | What it checks |
|---|---|
| `repo-hygiene` | Rolled-up hygiene greps. **`always_install: true`** — bypasses the menu. Sub-checks: `merge-markers` (no `<<<<<<<` / `=======` / `>>>>>>>` at line start); `large-files` (no tracked file > 5 MB, override via `GOVERNANCE_MAX_FILE_SIZE_MB`); `build-artifacts` (denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files); `debug-statements` (no `console.log` / `debugger` / `breakpoint()` / `import pdb` / `dbg!` / `fmt.Println` in non-test source; waiver `# governance: allow-repo-hygiene <reason>`); `file-size-limit` (no source file > 500 lines, override via `GOVERNANCE_FILE_SIZE_LIMIT`). To carve out a sub-check, use `governance directive modify`. |

### `core` presets

| Preset | Directives |
|---|---|
| `minimal`  | `required-docs`, `secrets-hygiene`, `repo-hygiene`, `workflows-hardened`, `no-broken-internal-doc-links` |
| `standard` | *minimal* + `commit-message-format`, `doc-freshness` |
| `strict`   | *standard* + `no-orphan-todos` |

---

## `agent-governance` pack

For repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, ...). The directives form a chain: issue creation uses a durable template, issues are tracked, every issue has exactly one receipt, every commit matches its receipt, and every commit carries its cost. Breaking any link makes the chain non-auditable — the `standard` preset bundles the full chain.

### Agent discipline
| Directive | What it checks |
|---|---|
| `receipt-per-issue`        | Every tracked `receipts/*.md` file carries a unique `issue-<N>` token in its filename **and** includes four Markdown sections — `## Checklist`, `## What changed`, `## Out of scope`, `## Verification` — naming the work plan, the surface area touched, the deferred work, and how completion will be judged. The `## Checklist` mirrors the GitHub issue's checklist; each `- [x]` item's text must appear (case-insensitive substring) in `## What changed` or `## Verification` (the local trust boundary that lets a reviewer confirm each claimed-done item maps to described work without leaving the diff). Unchecked items are unconstrained. No waivers — receipts are a fresh discipline with no legacy corpus to grandfather. Receipts are post-implementation audit traces, distinct from agent-runtime plan-mode plans. |
| `pr-review-required-when-pr-ready` | When the current branch has an open PR that is **not in draft state** (marked ready for review), the PR must carry a codex-authored review (a Pull Request Review whose body contains the marker `<!-- codex-review -->`). Trigger is GitHub's draft → ready transition (`gh pr ready`), the platform's first-class "ready for review" signal — decoupled from receipt checklist state so the agent can finish the checklist, push, and keep iterating in draft without firing a noisy review-mandate. Once the PR is non-draft and missing a codex review, the agent runs `codex exec "review PR #N ..."`. Skips with info when no PR exists or PR is in draft. **Local-only** — runs from `post-commit` as an advisory and is skipped entirely when `CI` is set, since codex is part of the local agent loop, not a merge-gate. Skip-with-warning when `gh` is missing or unauthenticated; fails when `gh` is present but the API call fails. |
| `commit-issue-receipt-match` | Each commit's anchor — trailing `(#N)` in the subject or any `Issue: #N` body trailer — matches an `issue-<N>` token on a `receipts/*.md` file it touches. Installs a `commit-msg` hook (Mode A) and runs in CI walking merge-base→HEAD (Mode B). Per-commit waiver: `governance: allow-commit-issue-receipt-match <reason>` in the commit body. |
| `issue-templates`          | `.github/ISSUE_TEMPLATE/` contains proposal and bug issue forms plus config. Blank issues are disabled, proposal issues require Context / Decision / Scope / Acceptance criteria / Validation / Open questions, and bug issues require the core defect-report fields. Ships the templates under `install-assets/.github/ISSUE_TEMPLATE/`. |
| `issues-tracked`           | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md` so a newly bootstrapped repo starts green. |
| `agent-token-accounting`   | Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Total = Input + Output`, and has exactly one matching append-only row in `COSTS.md`. Ships `install-assets/COSTS.md` plus directive-owned pre-commit and prepare-commit-msg helpers. Runtime-agnostic — see [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) for Codex / Claude Code wiring. |
| `agent-steering-accounting` | **Opt-in, not in any preset.** Every non-merge, non-revert commit stamps the always-on summary triple (`Steer-Count`, `Steer-Types`, `Steer-Tiers`); the numbers tally the rows newly added to append-only `STEERING.md` by the commit, and each newly-added row's `commit |` cell matches the pending subject. Independent of `agent-token-accounting` — installation is the gate, not the presence of an `Agent:` trailer. Detects human-steering events from the active session JSONL: interrupts (`tier: structural`) and semantic corrections classified by shelling out to the active runtime's headless CLI (`tier: classifier`, with regex `tier: lexical` as a silent fallback). Per-event `Steer-Key:` trailers were retired in #66 — the row → commit join uses the `commit |` column. No internal env-var gates — installation is the gate. Ships `install-assets/STEERING.md`, a Claude Code transcript reader, and pre-commit + prepare-commit-msg helpers. Privacy caveat — `user-reason` cells contain verbatim operator text. See [AGENT_STEERING_ACCOUNTING.md](AGENT_STEERING_ACCOUNTING.md). |

### `agent-governance` presets

| Preset | Directives |
|---|---|
| `minimal`  | `receipt-per-issue`, `commit-issue-receipt-match` |
| `standard` | *minimal* + `issue-templates`, `issues-tracked`, `agent-token-accounting`, `pr-review-required-when-pr-ready` |
| `strict`   | same as `standard` |

---

## In-source waivers

Line-level directives respect a trailing comment: `governance: allow-<directive-name> <reason>`.

```python
api_key = "AKIA..."  # governance: allow-no-secrets INFRA-1247 — lab fixture
```

Waivers are visible in `git blame` and searchable by design. Only use them for documented, intentional exceptions.

---

## Adding a new directive to an existing pack

1. Create `<pack-root>/<pack>/directives/<id>/` (where `<pack-root>` is `governance/assets/packs/` for `core`, or `extensions/packs/` for community-shaped packs) and populate it:
   - `check.sh` — the bash test, `chmod +x`.
   - `constitution.md` — four sections: **Directive**, **Rationale**, **Enforced by**, **Exceptions**.
   - `directive.yaml` — scalar fields:
     ```yaml
     category: <Foundation|Security|SystemOfRecord|CommitHygiene|Quality|AgentDiscipline|...>
     recommended: true|false
     summary: <one-line menu description>
     surface: repo-state | change-set
     hook: pre-commit | commit-msg | prepare-commit-msg | none
     # always_install: true   # optional; reserved to the core pack
     # requires_hook_strategy: githooks   # optional environment filter
     ```
   - `install-assets/` — optional files copied into the target repo before the first governance run. Use this for required seed files like `QUALITY.md` or `COSTS.md`; do not hide seed files in skill-specific special cases.
   - `evals/test.sh` — pass + fail fixtures using `eval-lib.sh`.
2. If the directive should be part of a preset, add its id to the relevant block (`minimal` / `standard` / `strict`) in the pack's `pack.yaml`. The `directives:` block no longer lives there — directive metadata comes from each directive's `directive.yaml`.
3. Run `bash scripts/test-packs.sh` — it validates every directive folder, installs `core.standard` into a fresh repo and runs it, runs every eval, and smoke-tests hook generation.
4. Document the directive in this file under the pack's category table.

For directives that belong in a new pack, see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

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

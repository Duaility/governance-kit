# Rules Catalog

Every rule lives in a **pack**. Each rule is a self-contained folder at `rules/<rule-id>/` carrying its metadata (`rule.yaml`), the executable test (`check.sh`), its Invariant snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers packs at activation, unions their menus, and installs the selected subset.

Two packs ship in-tree, each at its own root:

| Pack | Location | Purpose | Default? |
|---|---|---|---|
| `core` | `governance-bootstrap/assets/packs/core/` | General-purpose rules usable in any repo. | Always selected — cannot be deselected. |
| `duaility/agent-governance` | `extensions/packs/agent-governance/` | Rules for repos operating under agent-driven development (issue anchors, plans, token accounting). | Opt-in per-repo. |

`core` is the kit's bundled-in pack. `extensions/packs/` is the monorepo home for community-shaped packs — authored with scoped `<author>/<slug>` ids and installed through `governance pack add` as if hosted in their own repo.

For authoring a **third-party pack**, see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

---

## `core` pack

Minimum floor of hygiene — required docs exist, secrets aren't committed, workflows are pinned, merge markers are caught. The `minimal` / `standard` / `strict` presets add progressively more commit-time discipline on top of the same baseline.

The three consolidated rules (`required-docs`, `repo-hygiene`, `secrets-hygiene`) each expose a `GOVERNANCE_<NAME>_DISABLE` env var for per-sub-check opt-outs — the catalog below lists the sub-check keys under each entry.

### Foundation
| Rule | What it checks |
|---|---|
| `required-docs` | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled by default, keys for `GOVERNANCE_REQUIRED_DOCS_DISABLE`): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants at repo root, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). |

### Security
| Rule | What it checks |
|---|---|
| `secrets-hygiene`    | Rolled-up secret-scanning. Sub-checks (keys for `GOVERNANCE_SECRETS_HYGIENE_DISABLE`): `no-secrets` (heuristic scan for AWS / GCP / GitHub / Slack / Stripe / private-key patterns; waiver `# governance: allow-secrets-hygiene <reason>`); `dotenv` (`.env` is not tracked **and** listed in `.gitignore`). |
| `workflows-hardened` | Every `.github/workflows/*.yml` declares a `permissions:` block **and** pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-char commit SHA. |

### System of record
| Rule | What it checks |
|---|---|
| `no-broken-internal-doc-links`  | Every relative-path markdown link in tracked `.md` files resolves to an existing file. |
| `doc-freshness`                 | Docs listed in `tests/governance/freshness.conf` carry `<!-- last-verified: YYYY-MM-DD -->` within 90 days (configurable). No-op if the config file is absent. |

### Commit hygiene
| Rule | What it checks |
|---|---|
| `conventional-commits` | Commit subjects match `<type>(scope)?!?: subject (#123)`. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`. Installs a `commit-msg` git hook. |
| `no-orphan-todos`      | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |

### Quality
| Rule | What it checks |
|---|---|
| `repo-hygiene` | Rolled-up hygiene greps. **`always_install: true`** — bypasses the menu. Sub-checks (keys for `GOVERNANCE_REPO_HYGIENE_DISABLE`): `merge-markers` (no `<<<<<<<` / `=======` / `>>>>>>>` at line start); `large-files` (no tracked file > 5 MB, override via `GOVERNANCE_MAX_FILE_SIZE_MB`); `build-artifacts` (denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files); `debug-statements` (no `console.log` / `debugger` / `breakpoint()` / `import pdb` / `dbg!` / `fmt.Println` in non-test source; waiver `# governance: allow-repo-hygiene <reason>`); `file-size-limit` (no source file > 500 lines, override via `GOVERNANCE_FILE_SIZE_LIMIT`). |

### `core` presets

| Preset | Rules |
|---|---|
| `minimal`  | `required-docs`, `secrets-hygiene`, `repo-hygiene`, `workflows-hardened`, `no-broken-internal-doc-links` |
| `standard` | *minimal* + `conventional-commits`, `doc-freshness` |
| `strict`   | *standard* + `no-orphan-todos` |

---

## `agent-governance` pack

For repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, ...). The four rules form a chain: issues are tracked, every issue has exactly one plan, every commit matches its plan, and every commit carries its cost. Breaking any link makes the chain non-auditable — the `standard` preset bundles all four.

### Agent discipline
| Rule | What it checks |
|---|---|
| `plan-per-issue`           | Every tracked `plans/*.md` filename carries a unique `issue-<N>` token. |
| `commit-issue-plan-match`  | Each commit's `(#N)` subject anchor matches an `issue-<N>` token on a plan file it touches. Installs a `commit-msg` hook. |
| `issues-tracked`           | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md` so a newly bootstrapped repo starts green. |
| `agent-token-accounting`   | Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Total = Input + Output`, and has exactly one matching append-only row in `COSTS.md`. Ships `install-assets/COSTS.md` plus rule-owned pre-commit and prepare-commit-msg helpers. Runtime-agnostic — see [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) for Codex / Claude Code wiring. |

### `agent-governance` presets

| Preset | Rules |
|---|---|
| `minimal`  | `plan-per-issue`, `commit-issue-plan-match` |
| `standard` | *minimal* + `issues-tracked`, `agent-token-accounting` |
| `strict`   | same as `standard` |

---

## In-source waivers

Line-level rules respect a trailing comment: `governance: allow-<rule-name> <reason>`.

```python
api_key = "AKIA..."  # governance: allow-no-secrets INFRA-1247 — lab fixture
```

Waivers are visible in `git blame` and searchable by design. Only use them for documented, intentional exceptions.

---

## Adding a new rule to an existing pack

1. Create `<pack-root>/<pack>/rules/<id>/` (where `<pack-root>` is `governance-bootstrap/assets/packs/` for `core`, or `extensions/packs/` for community-shaped packs) and populate it:
   - `check.sh` — the bash test, `chmod +x`.
   - `constitution.md` — four sections: **Rule**, **Rationale**, **Enforced by**, **Exceptions**.
   - `rule.yaml` — scalar fields:
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
2. If the rule should be part of a preset, add its id to the relevant block (`minimal` / `standard` / `strict`) in the pack's `pack.yaml`. The `rules:` block no longer lives there — rule metadata comes from each rule's `rule.yaml`.
3. Run `bash scripts/test-packs.sh` — it validates every rule folder, installs `core.standard` into a fresh repo and runs it, runs every eval, and smoke-tests hook generation.
4. Document the rule in this file under the pack's category table.

For rules that belong in a new pack, see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

### Rule template

```bash
#!/usr/bin/env bash
# Rule: <one-line statement of the rule>
# Rationale: <why it matters — link to an incident if possible>
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "<rule-id>"    # must match the parent folder name
require_git

# ── your check ───────────────────────────────────────────────
# On every violation: call `violation "<file>:<line> — <message>"`
# Support waivers:     has_waiver "$file" "$line_no" "<rule-id>" && continue
# ─────────────────────────────────────────────────────────────

rule_end
```

Every rule should be:

- **Deterministic** — same repo state, same result.
- **Fast** — every rule runs on every commit. Keep it under a second when possible.
- **Specific** — a violation message should name the file, line, and reason. `"✗ bad code somewhere"` is worthless.
- **Waivable when warranted** — if there are legitimate exceptions, support the `governance: allow-<rule>` waiver comment so they're auditable.
- **Matched to the real policy surface** — if the policy is about each substantive change, prefer a change-set-aware check over a repo-exists proxy.

## Authoring guardrail

Before you ship a new rule, ask this explicitly:

> Is this rule about the state of the repository, or about what each change set must carry?

Use:

- **repo-state checks** (`surface: repo-state`) for things like `README.md exists`, `SECURITY.md exists`, `workflows pin actions`
- **change-set-aware checks** (`surface: change-set`) for things like `this change must update a plan`, `this sensitive code change must update a doc`, or `this path change must touch an approval file`

If you pick a repo-state check for a change-set obligation, the rule will create false confidence. Do not do that.

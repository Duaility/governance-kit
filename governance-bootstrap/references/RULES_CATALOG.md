# Rules Catalog

Every rule lives in a **pack** under `governance-bootstrap/assets/packs/<pack>/`. A pack bundles rule scripts (`rules/*.sh`), Invariant snippets (`constitution-snippets/*.md`), a YAML manifest (`pack.yaml`), and pass/fail evals (`evals/<rule>/test.sh`). The bootstrap skill discovers packs at activation, unions their menus, and installs the selected subset.

Two packs ship in-tree:

| Pack | Purpose | Default? |
|---|---|---|
| `core` | General-purpose rules usable in any repo. | Always selected — cannot be deselected. |
| `agent-governance` | Rules for repos operating under agent-driven development (issue anchors, plans, token accounting). | Opt-in per-repo. |

For authoring a **third-party pack**, see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

---

## `core` pack

Minimum floor of hygiene — `CONSTITUTION.md` exists, secrets aren't committed, dotenvs aren't tracked, workflows are pinned, merge markers are caught. The `minimal` / `standard` / `strict` presets select progressively larger subsets.

### Foundation
| Rule | What it checks |
|---|---|
| `constitution-exists`  | `CONSTITUTION.md` exists at the repo root, non-empty, ≥ 10 lines. |
| `readme-exists`        | `README.md` (or `README.rst`) exists with a heading and ≥ 30 words. |
| `license-exists`       | `LICENSE` (or variants) exists at the repo root and is non-empty. |
| `agents-md-exists`     | `AGENTS.md` at repo root, 30–250 lines, with ≥ 3 links to other docs. |
| `hooks-configured`     | `.githooks/pre-commit` is tracked + executable, `.githooks/commit-msg` likewise if `conventional-commits` is installed, and `core.hooksPath` is set to `.githooks`. |

### Security
| Rule | What it checks |
|---|---|
| `no-secrets`           | Heuristic scan for AWS / GCP / GitHub / Slack / Stripe / generic API keys and private-key blocks. |
| `dotenv-gitignored`    | `.env` is not tracked **and** is listed in `.gitignore`. |
| `security-md-exists`   | `SECURITY.md` (root / `docs/` / `.github/`) exists and lists a contact email or URL. |
| `workflows-hardened`   | Every `.github/workflows/*.yml` declares a `permissions:` block **and** pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-char commit SHA. |
| `env-example-current`  | Every key in a local `.env` is declared in `.env.example`. Opt-in; niche. |

### System of record
| Rule | What it checks |
|---|---|
| `architecture-doc-exists`       | `ARCHITECTURE.md` (root or `docs/`) exists, non-empty, ≥ 20 lines. |
| `no-broken-internal-doc-links`  | Every relative-path markdown link in tracked `.md` files resolves to an existing file. |
| `doc-freshness`                 | Docs listed in `tests/governance/freshness.conf` carry `<!-- last-verified: YYYY-MM-DD -->` within 90 days (configurable). No-op if the config file is absent. |
| `ci-workflow-exists`            | `.github/workflows/` contains at least one non-governance workflow. |

### Commit hygiene
| Rule | What it checks |
|---|---|
| `conventional-commits` | Commit subjects match `<type>(scope)?!?: subject (#123)`. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`. Installs a `commit-msg` git hook. |
| `no-orphan-todos`      | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |

### Quality
| Rule | What it checks |
|---|---|
| `no-debug-statements`          | No `console.log`, `debugger`, `breakpoint()`, `import pdb`, `dbg!`, or `fmt.Println` left in source (tests excluded). |
| `file-size-limit`              | No source file exceeds 500 lines. Override via `GOVERNANCE_FILE_SIZE_LIMIT`. |
| `no-large-files`               | No tracked file exceeds 5 MB. Override via `GOVERNANCE_MAX_FILE_SIZE_MB`. |
| `no-committed-build-artifacts` | Flags tracked `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files. |
| `no-merge-conflict-markers`    | No tracked file contains `<<<<<<<`, `=======`, or `>>>>>>>` at line-start. **`always_install: true`** — bypasses the menu. |

### `core` presets

| Preset | Rules |
|---|---|
| `minimal`  | `constitution-exists`, `no-secrets`, `dotenv-gitignored`, `workflows-hardened`, `no-broken-internal-doc-links`, `no-large-files`, `no-committed-build-artifacts`, `no-merge-conflict-markers`, `hooks-configured` |
| `standard` | *minimal* + `agents-md-exists`, `conventional-commits`, `doc-freshness` |
| `strict`   | *standard* + `readme-exists`, `security-md-exists`, `architecture-doc-exists`, `ci-workflow-exists`, `no-orphan-todos`, `file-size-limit`, `no-debug-statements` |

---

## `agent-governance` pack

For repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, ...). The four rules form a chain: issues are tracked, every issue has exactly one plan, every commit matches its plan, and every commit carries its cost. Breaking any link makes the chain non-auditable — the `standard` preset bundles all four.

### Agent discipline
| Rule | What it checks |
|---|---|
| `plan-per-issue`           | Every tracked `plans/*.md` filename carries a unique `issue-<N>` token. |
| `commit-issue-plan-match`  | Each commit's `(#N)` subject anchor matches an `issue-<N>` token on a plan file it touches. Installs a `commit-msg` hook. |
| `issues-tracked`           | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. |
| `agent-token-accounting`   | Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`), satisfies `Total = Input + Output`, and has exactly one matching append-only row in `COSTS.md`. Ships a `prepare-commit-msg` hook that stamps trailers when `AGENT_*` env vars are set. Runtime-agnostic — see [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) for Codex / Claude Code wiring. |

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

1. Write the script at `governance-bootstrap/assets/packs/<pack>/rules/<id>.sh`, `chmod +x`.
2. Write the Invariant snippet at `governance-bootstrap/assets/packs/<pack>/constitution-snippets/<id>.md` — four sections: **Rule**, **Rationale**, **Enforced by**, **Exceptions**.
3. Append a rule entry to `governance-bootstrap/assets/packs/<pack>/pack.yaml`:
   ```yaml
   - id: <id>
     category: <Foundation|Security|SystemOfRecord|CommitHygiene|Quality|AgentDiscipline|...>
     recommended: true|false
     summary: <one-line menu description>
     script: rules/<id>.sh
     constitution: constitution-snippets/<id>.md
     surface: repo-state | change-set
     hook: pre-commit | commit-msg | prepare-commit-msg | none
   ```
   Add the `id` to any preset blocks (`minimal` / `standard` / `strict`) it should be part of.
4. Write a pack eval at `governance-bootstrap/assets/packs/<pack>/evals/<id>/test.sh` using `eval-lib.sh`. Exercise a **pass** fixture and at least one **fail** fixture.
5. Run `bash scripts/test-packs.sh` — it validates manifests, runs every eval, and smoke-tests hook generation.
6. Document the rule in this file under the pack's category table.

For rules that belong in a new pack (not `core` or `agent-governance`), see [AUTHORING_PACKS.md](AUTHORING_PACKS.md).

### Rule template

```bash
#!/usr/bin/env bash
# Rule: <one-line statement of the rule>
# Rationale: <why it matters — link to an incident if possible>
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "<rule-id>"    # must match filename without .sh
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

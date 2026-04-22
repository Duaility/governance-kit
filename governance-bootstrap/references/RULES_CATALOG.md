# Rules Catalog

Every rule ships as a standalone bash script under `tests/governance/rules/`. Each script is independent — delete a `.sh` file to drop the rule; copy a new one to add one. The runner (`run.sh`) picks them up automatically.

## Menu (default offer)

The skill presents these via `AskUserQuestion` across two calls (five categories total).

### Foundation
| Rule | What it checks |
|---|---|
| `constitution-exists`  | `CONSTITUTION.md` exists at the repo root, non-empty, ≥ 10 lines. |
| `readme-exists`        | `README.md` (or `README.rst`) exists with a heading and ≥ 30 words. |
| `license-exists`       | `LICENSE` (or variants) exists at the repo root and is non-empty. |
| `agents-md-exists`     | `AGENTS.md` at repo root, 30–250 lines, with ≥ 3 links to other docs. |

### Security
| Rule | What it checks |
|---|---|
| `no-secrets`           | Heuristic scan for AWS / GCP / GitHub / Slack / Stripe / generic API keys and private-key blocks. |
| `dotenv-gitignored`    | `.env` is not tracked **and** is listed in `.gitignore`. |
| `security-md-exists`   | `SECURITY.md` (root / `docs/` / `.github/`) exists and lists a contact email or URL. |
| `workflows-hardened`   | Every `.github/workflows/*.yml` declares a `permissions:` block **and** pins third-party actions (anything outside `actions/*` and `github/*`) to a full 40-char commit SHA. |

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
| `conventional-commits` | Commit subjects match `<type>(scope)?!?: subject (#123)` so every commit carries a GitHub issue reference. Supported types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`. Extend via `GOVERNANCE_CC_EXTRA_TYPES`. Installs a `commit-msg` git hook. |
| `no-orphan-todos`      | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |

### Quality
| Rule | What it checks |
|---|---|
| `no-debug-statements`          | No `console.log`, `debugger`, `breakpoint()`, `import pdb`, `dbg!`, or `fmt.Println` left in source (tests excluded). |
| `file-size-limit`              | No source file exceeds 500 lines. Override via `GOVERNANCE_FILE_SIZE_LIMIT`. |
| `no-large-files`               | No tracked file exceeds 5 MB. Override via `GOVERNANCE_MAX_FILE_SIZE_MB`. |
| `no-committed-build-artifacts` | Flags tracked `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files. |

### Always installed (not in the menu)
| Rule | What it checks |
|---|---|
| `no-merge-conflict-markers` | No tracked file contains `<<<<<<<`, `=======`, or `>>>>>>>` at line-start. Zero false positives; always installed. |
| `hooks-configured`          | `.githooks/pre-commit` is tracked + executable, `.githooks/commit-msg` likewise if `conventional-commits` is installed, and `core.hooksPath` is set to `.githooks`. The meta-rule that makes every other local check actually fire on a fresh clone. |

## Also available — copy on request

Rules we've built but kept out of the default menu. The skill will install any of these if the user asks for them by name.

| Rule | What it checks | Why it's not a default |
|---|---|---|
| `env-example-current` | Every key in a local `.env` is declared in `.env.example`. | Only helps teams that keep a `.env` locally; niche. |
| `docs-dir-minimum`    | A configured list of required docs exists under `docs/`. | The list varies too much per project to default. *(Not yet shipped — write as needed via the template below.)* |
| `no-curl-bash-pipe`   | No `curl … \| bash` or `curl … \| sh` in tracked scripts. | Real attack vector, but niche — opt-in. *(Not yet shipped.)* |
| `no-http-urls-in-source` | Non-localhost `http://` URLs flagged in source. | High false-positive rate in docs and examples. *(Not yet shipped.)* |
| `shell-scripts-safe` | All `*.sh` files have `set -e` / `set -u`. | Defensive but pedantic. *(Not yet shipped.)* |

## In-source waivers

Line-level rules respect a trailing comment: `governance: allow-<rule-name> <reason>`.

```python
api_key = "AKIA..."  # governance: allow-no-secrets INFRA-1247 — lab fixture
```

Waivers are visible in `git blame` and searchable by design. Only use them for documented, intentional exceptions.

## Template for a new rule

```bash
#!/usr/bin/env bash
# Rule: <one-line statement of the rule>
# Rationale: <why it matters — link to an incident if possible>
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "<rule-name>"    # must match filename without .sh
require_git

# ── your check ───────────────────────────────────────────────
# On every violation: call `violation "<file>:<line> — <message>"`
# Support waivers:     has_waiver "$file" "$line_no" "<rule-name>" && continue
# ─────────────────────────────────────────────────────────────

rule_end
```

### Checklist for adding a new rule

1. Drop the script into `tests/governance/rules/<rule-name>.sh`, `chmod +x`.
2. Add an **Invariants** subsection in `CONSTITUTION.md` — Rule / Rationale / Enforced by / Exceptions.
3. Append to the **Evolution Log** in `CONSTITUTION.md` with the PR link.
4. Both changes land in the **same commit**.

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

- **repo-state checks** for things like `README.md exists`, `SECURITY.md exists`, `workflows pin actions`
- **change-set-aware checks** for things like `this change must update a plan`, `this sensitive code change must update a doc`, or `this path change must touch an approval file`

If you pick a repo-state check for a change-set obligation, the rule will create false confidence. Do not do that.

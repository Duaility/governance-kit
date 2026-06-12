# Directives Catalog

Every directive lives in a **pack** — the namespace directives are grouped into. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers every pack at activation, unions their preset menus, and installs the selected subset.

A directive's identity is `<owner>/<pack>/<id>`. The short id is a *given name*, not a global claim: two packs may ship same-named directives that check different things — they coexist and both run (`run.sh <bare-id>` runs every homonym; `run.sh <owner>/<pack>/<id>` runs exactly one). Suppression of another pack's directive is only ever explicit, via `replaces: <owner>/<pack>/<id>`.

Seven concern-scoped packs ship in-tree, each at `packs/<concern>/`:

| Pack | Location | Concern | Default? |
|---|---|---|---|
| `governance-kit/foundation` | `packs/foundation/` | Repo scaffolding, working-tree hygiene + kit coherence. | Always present (bundled). |
| `governance-kit/security`   | `packs/security/`   | Supply-chain and credential hygiene. | Always present (bundled). |
| `governance-kit/docs`       | `packs/docs/`       | Documentation-graph health. | Always present (bundled). |
| `governance-kit/commits`    | `packs/commits/`    | Commit-message & in-source marker hygiene. | Always present (bundled). |
| `governance-kit/audit`      | `packs/audit/`      | A trustworthy record of agent work — issue → receipt → commit traceability, cost + steering accounting, and tamper-proof record integrity. | Always present (bundled). |

Presets are **per-pack** and unioned at init: each pack ships `minimal`/`standard`/`strict` blocks covering its slice, and `governance init` unions the chosen preset across all five (see [the preset table](#presets-per-pack-unioned-at-init)). Community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`. For authoring a **third-party pack**, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

The **Standards** column records the external standard a directive implements (OpenSSF Scorecard checks, CWE entries, …) so coverage and gaps are visible. It is advisory metadata (`standards:` in `directive.yaml`); empty cells are not failures, they are the roadmap.

Several directives are **consolidated** — one directive rolling up multiple sub-checks over a shared surface: `required-docs`, `repo-hygiene`, `secrets-hygiene`, and `internal-doc-links`. Each sub-check is independently waivable, and a whole sub-check can be carved out for your repo with `governance directive modify`.

---

## `governance-kit/foundation`

Repo scaffolding, working-tree hygiene, and kit coherence — the documents a governed repo needs, a clean working tree, and the single kit-version pin agreeing with every managed-file stamp.

| Directive | Standards | What it checks |
|---|---|---|
| `required-docs` | — | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links, **and a link to `CONSTITUTION.md`**); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). Scalars configurable via `.governance/conf/governance-kit/foundation/required-docs.conf`. To carve out a sub-check, use `governance directive modify`. |
| `kit-version-sync` | — | The kit version agrees across the install: every managed-file `# governance-kit:managed kit-version=<v>` marker equals `.governance/install.yaml`'s `kit_version`. Managed set derived from the manifest (`tests_dir`'s `run.sh`/`lib.sh`, `ci_workflow`, `enable_governance_script`, `.githooks/*`). No-op when the manifest or its `kit_version` is absent. Repair path: `governance kit update`. (Renamed from `version-consistency`; waiver token `allow-kit-version-sync`.) |
| `repo-hygiene` | — | **`always_install: true`.** Rolled-up hygiene greps. Sub-checks: `merge-markers` (no `<<<<<<<` / `=======` / `>>>>>>>` at line start); `large-files` (no tracked file > 5 MB, override via `GOVERNANCE_MAX_FILE_SIZE_MB`); `build-artifacts` (denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files); `debug-statements` (no `console.log` / `debugger` / `breakpoint()` / `import pdb` / `dbg!` / `fmt.Println` in non-test source; line-level waiver `# governance: allow-repo-hygiene <reason>`); `file-size-limit` (no source file > 500 lines, override via `GOVERNANCE_FILE_SIZE_LIMIT`; file-level waiver `governance: allow-repo-hygiene file-size-limit <reason>` in the first 10 lines). Scalars configurable via `.governance/conf/governance-kit/foundation/repo-hygiene.conf`. |

## `governance-kit/security`

Supply-chain and credential hygiene. The reference cut for the concern-pack model: `workflows-hardened` is split into the two OpenSSF Scorecard checks it fused.

| Directive | Standards | What it checks |
|---|---|---|
| `secrets-hygiene` | CWE-798 | Rolled-up secret-scanning. Sub-checks: `hardcoded-credentials` (CWE-798) — heuristic scan for AWS / GCP / GitHub / Slack / Stripe / private-key patterns; waiver `# governance: allow-secrets-hygiene <reason>`; `dotenv` — `.env` is not tracked **and** is listed in `.gitignore`. To carve out a sub-check, use `governance directive modify`. |
| `token-permissions` | OpenSSF Scorecard: Token-Permissions | Every `.github/workflows/*.yml` (or `*.yaml`) declares a `permissions:` block (top-level or per-job) so the workflow runs least-privilege rather than inheriting the repo's broad default token. File-level waiver: `# governance: allow-token-permissions <reason>` in the first ten lines of the workflow. |
| `pinned-dependencies` | OpenSSF Scorecard: Pinned-Dependencies | Every third-party GitHub Action (outside `actions/*` and `github/*`) is pinned to a full 40-char commit SHA, not a moving tag. The future home for container-image digest pinning, `curl \| bash` install-command pinning, and manifest/lockfile sync. Line waiver: `# governance: allow-pinned-dependencies <reason>` on the `uses:` line. |

## `governance-kit/docs`

Documentation-graph health: internal links resolve, and docs that must move together stay fresh.

| Directive | Standards | What it checks |
|---|---|---|
| `internal-doc-links` | — | Rolled-up health of the internal markdown link graph. **`resolve`** (always on): every relative-path link target in a tracked `.md` resolves to an existing file. **`reachable`** (opt-in): every tracked `.md` is reachable from an entry-point doc declared in `.governance/conf/governance-kit/docs/internal-doc-links.conf` (`root <path>` / `exclude <glob>` lines) — no-op when that config is absent. Immutable historical ledgers (`receipts/`, `plans/`) are excluded — their links describe a past state and can't be repaired without violating append-only. Waivers: `resolve` — `<!-- governance: allow-internal-doc-links <reason> -->` on the broken-link line; `reachable` — a configured `exclude <glob>`, or `governance: allow-internal-doc-links reachable <reason>` in the orphan's first 10 lines. |
| `doc-freshness` | — | Docs listed in `.governance/conf/governance-kit/docs/doc-freshness.conf` carry `<!-- last-verified: YYYY-MM-DD -->` within 90 days (configurable via a `FRESHNESS_DAYS=` line or the `GOVERNANCE_FRESHNESS_DAYS` env var). No-op if the config file is absent. |

## `governance-kit/commits`

Commit-message and in-source marker hygiene — the rules a repo opts into past bootstrap.

| Directive | Standards | What it checks |
|---|---|---|
| `commit-message-format` | — | Commit subjects match `<type>(scope)?!?: subject (#123)` — Conventional Commits prefix **plus** a trailing GitHub issue reference. Default types ship in the directive's `defaults.conf`; customize via the overlay `.governance/conf/governance-kit/commits/commit-message-format.conf` (bare line adds a type, `!<type>` removes a default). Installs a `commit-msg` git hook. |
| `no-orphan-todos` | — | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |
| `no-unjustified-suppressions` | — | Every lint / type-checker suppression — `eslint-disable*`, `@ts-ignore`, `@ts-expect-error`, `# noqa`, `# type: ignore`, `# pylint: disable`, `# pyright: ignore`, `#[allow(...)]`, `nolint`, `@SuppressWarnings` — references `#123` or `ABC-123` on the same line. Markdown is not scanned. Line waiver: `governance: allow-no-unjustified-suppressions <reason>`. |

## `governance-kit/audit`

A trustworthy record of agent work, for repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, …). Three linked layers — **traceability** (every unit of work is a tracked issue with exactly one receipt, and every commit matches its receipt), **accounting** (every commit carries its token cost and human-steering footprint), and **integrity** (those records stay tamper-proof — receipts immutable, ledgers append-only, frozen sections verbatim, toolchain config un-gameable). The `standard` preset bundles the full chain; `agent-steering-accounting` and `doc-integrity` are mandatory.

| Directive | Standards | What it checks |
|---|---|---|
| `receipt-per-issue` | — | Every tracked `receipts/*.md` carries a unique `issue-<N>` token in its filename (the slug is optional — `issue-<N>.md` is valid, not just `issue-<N>-<slug>.md`) **and** includes `## Checklist`, `## What changed`, `## Out of scope`, `## Verification`. The `## Checklist` mirrors the GitHub issue's checklist; each `- [x]` item's text must appear (case-insensitive substring) in `## What changed` or `## Verification`. A fifth `## Decisions` section (write "None" when the work followed the spec) is required **only on receipts added in the current change set**. Accounting-only stubs (a receipt whose only `## ` heading is `## Accounting` — created on demand by the accounting hooks) are exempt from the four-section / crosswalk / Decisions / Verification rules until the agent adds narrative. Waiver: `governance: allow-receipt-per-issue <reason>` exempts a whole receipt. |
| `commit-issue-receipt-match` | — | Each commit's anchor — trailing `(#N)` in the subject or any `Issue: #N` body trailer — matches an `issue-<N>` token on a `receipts/*.md` it touches. `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Per-commit waiver: `governance: allow-commit-issue-receipt-match <reason>`. |
| `issue-templates` | — | `.github/ISSUE_TEMPLATE/` contains proposal + bug issue forms plus config; blank issues disabled; proposal requires Context / Decision / Scope / Acceptance criteria / Validation / Open questions; bug requires the core defect-report fields. Ships the templates under `install-assets/`. |
| `issues-tracked` | — | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md`. |
| `agent-token-accounting` | — | Every non-merge, non-revert commit carries the full trailer set (`Agent`, `Issue`, `Session`, `Token-Input`, `Token-Output`, `Token-Total`, `Cost-Key`, `Cost-USD`), satisfies `Total = Input + Output`, and has exactly one matching cost row in the commit's per-issue receipt `receipts/issue-<N>.md` (under `## Accounting` → `### Costs`). `Cost-Key` is an opaque, globally-unique join token (across all `receipts/*.md`). The hook creates an accounting-only stub receipt on demand if none exists. `lib/report.py` aggregates the Accounting sections for per-issue + grand totals. Price overrides via `rate <model> …` rows in `.governance/conf/governance-kit/audit/agent-token-accounting.conf`. |
| `agent-steering-accounting` | — | **`always_install: true`.** Every non-merge, non-revert commit stamps the summary triple (`Steer-Count`, `Steer-Types`, `Steer-Tiers`); the numbers tally steering rows newly added to the commit's per-issue receipt `receipts/issue-<N>.md` (under `## Accounting` → `### Steering`). Every accounted event must resolve to an issue — the hook refuses to write events it can't attribute. Detects human-steering events (interrupts → `tier: structural`; corrections → `tier: classifier`, regex `tier: lexical` fallback). Knobs in `.governance/conf/governance-kit/audit/agent-steering-accounting.conf`. Privacy caveat — `user-reason` cells contain verbatim operator text; redact via the classifier hook rather than skipping the directive. |
| `doc-integrity` | — | **`always_install: true` — the standard rules ship active in the directive's `defaults.conf`.** Makes system-of-record documents append-only relative to the change set's default-branch baseline (a rule is a no-op until its document exists). Layered with the overlay `.governance/conf/governance-kit/audit/doc-integrity.conf` (bare line adds, `!<rule>` drops a default). Three modes: `frozen-files <glob>` (each file immutable once on the trunk; new files OK — e.g. `receipts/*.md`, which now also seals each merged per-issue receipt's `## Accounting` rows), `append-only <file>` (baseline must be a byte-prefix of current), `frozen-section <file> <heading>` (baseline lines under the heading survive verbatim — e.g. `QUALITY.md` Resolved, `CONSTITUTION.md` Evolution Log). The legacy `COSTS.md` / `STEERING.md` ledgers are now sealed as `frozen-files` (no longer append-only): they are frozen history that stops receiving writes. `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Path-scoped waiver: `governance: allow-doc-integrity <path> <reason>`. |
| `toolchain-config-protection` | — | A commit modifying toolchain config — linter, formatter, type-checker, CI workflow, or git-hook config — must carry a `governance: allow-toolchain-config <reason>` line in its body. Stops the "fix the rule, not the code" move from passing silently. Protected paths ship in the directive's `defaults.conf` (which omits `.governance/**` — already guarded by `kit-version-sync` + `doc-integrity`), layered with the overlay `.governance/conf/governance-kit/audit/toolchain-config-protection.conf`. Merge/revert commits skipped. |

---

## Presets (per-pack, unioned at init)

Each pack declares only the preset tiers it contributes to; `governance init` unions the chosen preset across all five bundled packs. The union reproduces the directive sets below.

| Preset | Directives (unioned across all bundled packs) |
|---|---|
| `minimal`  | `required-docs`, `secrets-hygiene`, `token-permissions`, `pinned-dependencies`, `internal-doc-links`, `repo-hygiene` |
| `standard` | *minimal* + `kit-version-sync`, `doc-freshness`, `commit-message-format`, `issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`, `agent-token-accounting`, `agent-steering-accounting`, `toolchain-config-protection`, `doc-integrity` |
| `strict`   | *standard* + `no-orphan-todos`, `no-unjustified-suppressions` |

`repo-hygiene`, `doc-integrity`, and `agent-steering-accounting` are `always_install: true` — they install regardless of preset selection. `always_install: true` is reserved to the `governance-kit/*` bundled packs. Agent accounting is mandatory in this kit's model because every commit is agent-authored.

---

## In-source waivers

Line-level directives respect a trailing comment: `governance: allow-<directive-name> <reason>`.

```python
api_key = "AKIA..."  # governance: allow-secrets-hygiene INFRA-1247 — lab fixture
```

A flat `allow-<id>` token waives the concern (every homonym of that id). Waivers are visible in `git blame` and searchable by design. Only use them for documented, intentional exceptions.

---

## Adding a new directive to an existing pack

1. Create `<pack-root>/directives/<id>/` (where `<pack-root>` is `packs/<concern>/` for a kit-bundled pack, or your own pack's source tree for a community pack hosted in its own repo) and populate it:
   - `check.sh` — the bash test, `chmod +x`.
   - `constitution.md` — four sections: **Directive**, **Rationale**, **Enforced by**, **Exceptions**.
   - `directive.yaml` — scalar fields:
     ```yaml
     category: <Foundation|Security|...>
     recommended: true|false
     summary: <one-line menu description>
     surface: repo-state | change-set
     hook: pre-commit | commit-msg | prepare-commit-msg | post-commit | pre-push | none
     # standards:                         # optional advisory metadata
     #   - "OpenSSF Scorecard: <Check>"
     # always_install: true               # optional; reserved to governance-kit/* bundled packs
     # requires_hook_strategy: githooks   # optional environment filter
     ```
   - `config.conf` / `defaults.conf` — optional per-directive config (see [PACK_AUTHORING.md](PACK_AUTHORING.md)). The user overlay seeds to `.governance/conf/<owner>/<pack>/<id>.conf`.
   - `install-assets/` — optional files copied into the target repo before the first governance run.
   - `evals/test.sh` — pass + fail fixtures using `eval-lib.sh`.
2. If the directive should be part of a preset, add its id to the relevant block (`minimal` / `standard` / `strict`) in the pack's `pack.yaml`.
3. Run `bash scripts/test-packs.sh` — it validates every directive folder, installs the unioned `standard` preset across all bundled packs into a fresh repo and runs it, runs every eval, and smoke-tests hook generation.
4. Document the directive in this file under the pack's table.

For directives that belong in a new pack, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

### Directive template

```bash
#!/usr/bin/env bash
# Directive: <one-line statement of the directive>
# Rationale: <why it matters — link to an incident if possible>
set -u
source "$(dirname "$0")/../../../../../lib.sh"
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

# Directives Catalog

Every directive lives in a **pack** — the namespace directives are grouped into. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers every pack at activation, unions their preset menus, and installs the selected subset.

A directive's identity is `<owner>/<pack>/<id>`. The short id is a *given name*, not a global claim: two packs may ship same-named directives that check different things — they coexist and both run (`run.sh <bare-id>` runs every homonym; `run.sh <owner>/<pack>/<id>` runs exactly one). Suppression of another pack's directive is only ever explicit, via `replaces: <owner>/<pack>/<id>`.

Four concern-scoped packs ship in-tree, each at `packs/<concern>/`:

| Pack | Location | Concern | Default? |
|---|---|---|---|
| `governance-kit/foundation` | `packs/foundation/` | Repo scaffolding, working-tree hygiene + kit coherence. | Always present (bundled). |
| `governance-kit/docs`       | `packs/docs/`       | Documentation-graph health. | Always present (bundled). |
| `governance-kit/commits`    | `packs/commits/`    | Commit-message & in-source marker hygiene. | Always present (bundled). |
| `governance-kit/audit`      | `packs/audit/`      | A trustworthy record of agent work — issue → receipt → commit traceability, cost + steering accounting, and tamper-proof record integrity. | Always present (bundled). |

Presets are **per-pack** and unioned at init: each pack ships `minimal`/`standard`/`strict` blocks covering its slice, and `governance init` unions the chosen preset across all four (see [the preset table](#presets-per-pack-unioned-at-init)). Community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`. For authoring a **third-party pack**, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

Most directives are **synchronous** — enforced by `check.sh` at a git hook and in CI. The kit also ships a third surface, **`sweep`** (issue #142): a directive that ships `triage.sh` instead of `check.sh`, declares `engine: llm`, and is adjudicated asynchronously by a scheduled LLM-judge run that files a digest issue — it never gates a commit, push, or PR. The kit no longer bundles any sweep directives; they are authored in repo-local or community packs. See [SWEEP_FLOW.md](SWEEP_FLOW.md).

The **Standards** column records the external standard a directive implements (OpenSSF Scorecard checks, CWE entries, …) so coverage and gaps are visible. It is advisory metadata (`standards:` in `directive.yaml`); empty cells are not failures, they are the roadmap.

Several directives are **consolidated** — one directive rolling up multiple sub-checks over a shared surface: `required-docs`, `repo-hygiene`, and `internal-doc-links`. Each sub-check is independently waivable, and a whole sub-check can be carved out for your repo with `governance directive modify`.

---

## `governance-kit/foundation`

Repo scaffolding, working-tree hygiene, and managed-tree integrity — the documents a governed repo needs, a clean working tree, and a vendored `.governance/` tree that matches the digests recorded at install/update time (so it is never silently hand-edited).

| Directive | Standards | What it checks |
|---|---|---|
| `required-docs` | — | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links, **and a link to `CONSTITUTION.md`**); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). Scalars configurable via `.governance/conf/governance-kit/foundation/required-docs.conf`. To carve out a sub-check, use `governance directive modify`. |
| `managed-tree-integrity` | — | The vendored `.governance/` tree matches the content digests recorded at apply time, so it changes only through the install/update verbs — never by hand. For every `packs.lock` pack entry with a `digest:` map, each vendored directive folder matches its recorded `sha256` (and no unrecorded directive folder appears); for every file in `install.yaml`'s `managed_digests:` map (`run.sh`, `lib.sh`, the CI workflow, and the sweep pair when installed), the file matches its recorded `sha256`. The local-only hook dispatchers (`.githooks/*` etc.) are **not** digested — they sit outside the CI trust chain, are intentionally bypassable, and are regenerated by the verbs (issue #267). Also asserts each managed file's `# governance-kit:managed kit-version=<v>` marker equals the manifest's `kit_version` (subsuming the former `kit-version-sync`). Works **offline in any repo** — it compares recorded digests, not upstream pack git objects. No-op for a pack/manifest with no recorded digests (pre-#253 installs gain coverage on their next `pack update` / `update`). Per-unit waiver via `.governance/conf/<owner>/<pack>/managed-tree-integrity.conf`. |
| `repo-hygiene` | — | **`always_install: true`.** Rolled-up hygiene greps. Sub-checks: `merge-markers` (no `<<<<<<<` / `=======` / `>>>>>>>` at line start); `large-files` (no tracked file > 5 MB, override via `GOVERNANCE_MAX_FILE_SIZE_MB`); `build-artifacts` (denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files); `debug-statements` (no `console.log` / `debugger` / `breakpoint()` / `import pdb` / `dbg!` / `fmt.Println` in non-test source; line-level waiver `# governance: allow-repo-hygiene <reason>`); `file-size-limit` (no source file > 500 lines, override via `GOVERNANCE_FILE_SIZE_LIMIT`; file-level waiver `governance: allow-repo-hygiene file-size-limit <reason>` in the first 10 lines). Scalars configurable via `.governance/conf/governance-kit/foundation/repo-hygiene.conf`. |

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
| `receipt-per-issue` | — | Every tracked `receipts/*.md` carries a unique `issue-<N>` token in its filename (the slug is optional — `issue-<N>.md` is valid, not just `issue-<N>-<slug>.md`) **and** includes `## Checklist`, `## What changed`, `## Out of scope`, `## Verification`. The `## Checklist` mirrors the GitHub issue's checklist; each `- [x]` item's text must appear (case-insensitive substring) in `## What changed` or `## Verification`. **Only on receipts added in the current change set:** a `## Decisions` section (write "None" when the work followed the spec); at least one fenced code block in `## Verification`; **file coverage** — every changed file (added/modified/renamed) must be named in some added receipt, exempting receipts and the `COSTS.md`/`STEERING.md`/`CONSTITUTION.md` ledgers (scope-creep guard, #272); and a `## Audit` section carrying a `PASS`/`REFUTED` verdict from a fresh-context sub-agent that checked the receipt against the diff and the issue (#272, built on the shared `require_attestation` lib.sh infra; needs kit ≥ 0.9.0). Accounting-only stubs (a receipt whose only `## ` heading is `## Accounting` — created on demand by the accounting hooks) are exempt from the shape / crosswalk / Decisions / Verification / Audit / coverage rules until the agent adds narrative. Waiver: `governance: allow-receipt-per-issue <reason>` exempts a whole receipt. |
| `commit-issue-receipt-match` | — | Every non-merge, non-revert commit adds or updates a `receipts/issue-<N>.md`; the touched receipt path **is** the issue anchor (file-first, #293 — survives squash natively, no body trailer). `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Per-commit waiver: `governance: allow-commit-issue-receipt-match <reason>`. |
| `issue-templates` | — | `.github/ISSUE_TEMPLATE/` contains proposal + bug issue forms plus config; blank issues disabled; proposal requires Context / Decision / Scope / Acceptance criteria / Validation / Open questions; bug requires the core defect-report fields. Ships the templates under `install-assets/`. |
| `issues-tracked` | — | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md`. |
| `agent-token-accounting` | — | Each agent commit's token cost lands as one row in the per-issue receipt `receipts/issue-<N>.md` (under `## Accounting` → `### Costs`); a commit-time check reconciles the receipt's recorded cumulative `cum-*` against the transcript — a ledger that lags the transcript means a commit's cost row was never written (no commit trailers, #293). `cost-key` is an opaque, globally-unique join token (across all `receipts/*.md`). The pre-commit hook creates an accounting-only stub receipt on demand. `lib/report.py` aggregates the Accounting sections for per-issue + grand totals. Price overrides via `rate <model> …` rows in `.governance/conf/governance-kit/audit/agent-token-accounting.conf`. |
| `agent-steering-accounting` | — | **`always_install: true`.** Detected human-steering events (interrupts → `tier: structural`; corrections → `tier: classifier`, regex `tier: lexical` fallback) are recorded as rows in the per-issue receipt `receipts/issue-<N>.md` (under `## Accounting` → `### Steering`); `check.sh` validates the ledger shape — per-row fields, append-only order, per-session ordinal monotonicity, global steer-key uniqueness, cross-receipt `(session, ordinal)` identity (no commit trailers, #293). Every accounted event must resolve to an issue — the hook refuses to write events it can't attribute. Knobs in `.governance/conf/governance-kit/audit/agent-steering-accounting.conf`. Privacy caveat — `user-reason` cells contain verbatim operator text; redact via the classifier hook rather than skipping the directive. |
| `doc-integrity` | — | **`always_install: true` — the standard rules ship active in the directive's `defaults.conf`.** Makes system-of-record documents append-only relative to the change set's default-branch baseline (a rule is a no-op until its document exists). Layered with the overlay `.governance/conf/governance-kit/audit/doc-integrity.conf` (bare line adds, `!<rule>` drops a default). Three modes: `frozen-files <glob>` (each file immutable once on the trunk; new files OK — e.g. `receipts/*.md`, which now also seals each merged per-issue receipt's `## Accounting` rows), `append-only <file>` (baseline must be a byte-prefix of current), `frozen-section <file> <heading>` (baseline lines under the heading survive verbatim — e.g. `QUALITY.md` Resolved, `CONSTITUTION.md` Evolution Log). The legacy `COSTS.md` / `STEERING.md` ledgers are now sealed as `frozen-files` (no longer append-only): they are frozen history that stops receiving writes. `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Path-scoped waiver: `governance: allow-doc-integrity <path> <reason>`. |
| `toolchain-config-protection` | — | A commit modifying toolchain config — linter, formatter, type-checker, CI workflow, or git-hook config — must carry a `governance: allow-toolchain-config <reason>` line in its body. Stops the "fix the rule, not the code" move from passing silently. Protected paths ship in the directive's `defaults.conf` (which omits `.governance/**` — already guarded by `managed-tree-integrity` + `doc-integrity`), layered with the overlay `.governance/conf/governance-kit/audit/toolchain-config-protection.conf`. Merge/revert commits skipped. |

---

## The sweep lane

The kit ships the off-commit-path [sweep lane](SWEEP_FLOW.md) — the `surface: sweep` directive contract, the vendored engine (`.governance/sweep.py`), and the scheduled workflow ([governance-sweep.yml](SWEEP_FLOW.md)) — but bundles **no sweep directives**. Sweep directives (LLM-adjudicated invariants about *intent* and *architectural shape* that grep cannot reach, issue #142) are authored in repo-local or community packs; this repo dogfoods `no-legacy-fallbacks` and `no-path-bifurcation` in its repo-local `duaility/governance-kit` pack. Installing any sweep directive also installs the scheduled workflow and the vendored engine. The shared sub-agent-attestation infra ([SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md), issue #272) — a `surface: change-set` directive that demands a fresh-context sub-agent verdict recorded into the receipt — ships in the kit too, consumed by `receipt-per-issue` (bundled) and by repo-local dogfood directives such as `layer-boundaries`.

---

## Presets (per-pack, unioned at init)

Each pack declares only the preset tiers it contributes to; `governance init` unions the chosen preset across all four bundled packs. The union reproduces the directive sets below.

| Preset | Directives (unioned across all bundled packs) |
|---|---|
| `minimal`  | `required-docs`, `repo-hygiene`, `managed-tree-integrity`, `internal-doc-links` |
| `standard` | *minimal* + `doc-freshness`, `commit-message-format`, `issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`, `agent-token-accounting`, `agent-steering-accounting`, `toolchain-config-protection`, `doc-integrity` |
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
   - `defaults.conf` — optional pack-owned config: the live defaults **and** their docs (see [PACK_AUTHORING.md](PACK_AUTHORING.md)). The user overlay seeds to `.governance/conf/<owner>/<pack>/<id>.conf` from a generic stub.
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

# Directives Catalog

Every directive lives in a **pack** — the namespace directives are grouped into. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries only pack identity and presets. The bootstrap skill discovers every pack at activation, unions their preset menus, and installs the selected subset.

A directive's identity is `<owner>/<pack>/<id>`. The short id is a *given name*, not a global claim: two packs may ship same-named directives that check different things — they coexist and both run (`run.sh <bare-id>` runs every homonym; `run.sh <owner>/<pack>/<id>` runs exactly one). Suppression of another pack's directive is only ever explicit, via `replaces: <owner>/<pack>/<id>`.

Three concern-scoped packs ship in-tree, each at `packs/<concern>/`:

| Pack | Location | Concern | Default? |
|---|---|---|---|
| `governance-kit/foundation` | `packs/foundation/` | Repo scaffolding, internal doc-link health, working-tree hygiene + kit coherence. | Always present (bundled). |
| `governance-kit/commits`    | `packs/commits/`    | Commit-message & in-source marker hygiene. | Always present (bundled). |
| `governance-kit/audit`      | `packs/audit/`      | A trustworthy record of agent work — issue → receipt → commit traceability, session provenance, and tamper-proof record integrity. | Always present (bundled). |

Presets are **per-pack** and unioned at init: each pack ships `minimal`/`standard`/`strict` blocks covering its slice, and `governance init` unions the chosen preset across all three (see [the preset table](#presets-per-pack-unioned-at-init)). Community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`. For authoring a **third-party pack**, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

Most directives are **synchronous** — enforced by `check.sh` at a git hook and in CI. A directive can also carry a lane-independent `judge:` rubric (issues #142, #325, #355). Lane membership is explicit in `triggers:`. Live attestation uses fixed `ATTEST_SECTION` and `ATTEST_CMD` config; scheduled re-adjudication uses fixed `SCHEDULE_CMD`, per-member evidence, and optional staleness config. The scheduled lane never gates a commit, push, or PR by itself — only a mechanical `check.sh` member's failure fails its job. Every bundled directive ships a schedule-eligible rubric alongside its mechanical check; repo-local and community packs may author standalone `hook: none`, `triggers: [schedule]` judges with no `check.sh`. See [SCHEDULE_FLOW.md](SCHEDULE_FLOW.md).

The **Standards** column records the external standard a directive implements (OpenSSF Scorecard checks, CWE entries, …) so coverage and gaps are visible. It is advisory metadata (`standards:` in `directive.yaml`); empty cells are not failures, they are the roadmap.

Several directives are **consolidated** — one directive rolling up multiple sub-checks over a shared surface: `required-docs`, `repo-hygiene`, and `internal-doc-links`. Each sub-check is independently waivable, and a whole sub-check can be carved out for your repo with `governance directive modify`.

---

## `governance-kit/foundation`

Repo scaffolding, internal doc-link health, working-tree hygiene, and managed-tree integrity — the documents a governed repo needs, an internal link graph that resolves, a clean working tree, and a vendored `.governance/` tree that matches the digests recorded at install/update time (so it is never silently hand-edited).

| Directive | Standards | What it checks |
|---|---|---|
| `required-docs` | — | Rolled-up presence check for repo-root docs and local-hook scaffolding. Sub-checks (all enabled): `constitution` (`CONSTITUTION.md` ≥ 10 lines); `agents` (`AGENTS.md` at repo root, 30–250 lines, ≥ 3 internal links, **and a link to `CONSTITUTION.md`**); `readme` (`README.md`/`.rst` with heading + ≥ 30 words); `license` (`LICENSE`/variants, non-empty); `security` (`SECURITY.md` with contact); `architecture` (`ARCHITECTURE.md` ≥ 20 lines); `ci-workflow` (≥ 1 non-governance workflow); `env-example` (every key in local `.env` is declared in `.env.example`); `hooks` (`.githooks/pre-commit` tracked + executable, `core.hooksPath=.githooks`; no-ops on non-`githooks` strategies). Scalars configurable via `.governance/conf/governance-kit/foundation/required-docs.conf`. To carve out a sub-check, use `governance directive modify`. |
| `internal-doc-links` | — | Rolled-up health of the internal markdown link graph. **`resolve`** (always on): every relative-path link target in a tracked `.md` resolves to an existing file. **`reachable`** (opt-in): every tracked `.md` is reachable from an entry-point doc declared in `.governance/conf/governance-kit/foundation/internal-doc-links.conf` (`root <path>` / `exclude <glob>` lines) — no-op when that config is absent. Immutable historical ledgers (`receipts/`, `plans/`) are excluded — their links describe a past state and can't be repaired without violating append-only. Waivers: `resolve` — `<!-- governance: allow-internal-doc-links <reason> -->` on the broken-link line; `reachable` — a configured `exclude <glob>`, or `governance: allow-internal-doc-links reachable <reason>` in the orphan's first 10 lines. |
| `managed-tree-integrity` | — | The vendored `.governance/` tree matches the content digests recorded at apply time, so it changes only through the install/update verbs — never by hand. For every `packs.lock` pack entry with a `digest:` map, each vendored directive folder matches its recorded `sha256` (and no unrecorded directive folder appears); for every file in `install.yaml`'s `managed_digests:` map (`run.sh`, `lib.sh`, the CI workflow, and the generated `.github/workflows/governance-schedule.yml`, plus legacy prefixed workflows on pre-redesign installs), the file matches its recorded `sha256`. The local-only hook dispatchers (`.githooks/*` etc.) are **not** digested — they sit outside the CI trust chain, are intentionally bypassable, and are regenerated by the verbs (issue #267). Also asserts each managed file's `# governance-kit:managed kit-version=<v>` marker equals the manifest's `kit_version` (subsuming the former `kit-version-sync`). Works **offline in any repo** — it compares recorded digests, not upstream pack git objects. No-op for a pack/manifest with no recorded digests (pre-#253 installs gain coverage on their next `pack update` / `update`). Per-unit waiver via `.governance/conf/<owner>/<pack>/managed-tree-integrity.conf`. |
| `repo-hygiene` | — | **`always_install: true`.** Rolled-up hygiene greps. Sub-checks: merge markers, large files, build artifacts, debug statements, and source-file size. Thresholds and pattern lists are declared in `directive.yaml`; tunable entries use `.governance/conf/governance-kit/foundation/repo-hygiene.conf`. |

## `governance-kit/commits`

Commit-message and in-source marker hygiene — the rules a repo opts into past bootstrap.

| Directive | Standards | What it checks |
|---|---|---|
| `commit-message-format` | — | Commit subjects match `<type>(scope)?!?: subject (#123)` — Conventional Commits prefix **plus** a trailing GitHub issue reference. Default types live in the manifest's tunable `TYPES` list; the overlay can add a type or remove one with `!<type>`. Installs a `commit-msg` hook. |
| `no-orphan-todos` | — | Every `TODO` / `FIXME` on a line references `#123` or `ABC-123`. |
| `no-unjustified-suppressions` | — | Every lint / type-checker suppression — `eslint-disable*`, `@ts-ignore`, `@ts-expect-error`, `# noqa`, `# type: ignore`, `# pylint: disable`, `# pyright: ignore`, `#[allow(...)]`, `nolint`, `@SuppressWarnings` — references `#123` or `ABC-123` on the same line. Markdown is not scanned. Line waiver: `governance: allow-no-unjustified-suppressions <reason>`. |

## `governance-kit/audit`

A trustworthy record of agent work, for repos where every tree-change is produced through an agent runtime (Codex, Claude Code, Cursor, …). Three linked layers — **traceability** (every unit of work is a tracked issue with exactly one receipt, and every commit matches its receipt), **session provenance** (each agent commit records the explicit harness/session identity it was given), and **integrity** (those records stay tamper-proof — receipts immutable, frozen sections verbatim, toolchain config un-gameable). The `standard` preset bundles the full chain; `agent-session-identity` and `doc-integrity` are mandatory.

| Directive | Standards | What it checks |
|---|---|---|
| `receipt-per-issue` | — | Every tracked `receipts/*.md` carries a unique `issue-<N>` token in its filename; a receipt **added in the change set** must also carry a kebab-case slug (`issue-<N>-<slug>.md`), while session-only stubs and pre-existing (grandfathered) receipts may use the bare `issue-<N>.md` form. Each receipt also includes `## Checklist`, `## What changed`, `## Out of scope`, `## Verification`. The `## Checklist` mirrors the GitHub issue's checklist; each `- [x]` item's text must appear (case-insensitive substring) in `## What changed` or `## Verification`. **Only on receipts added in the current change set:** a `## Decisions` section (write "None" when the work followed the spec); at least one fenced code block in `## Verification`; **file coverage** — every changed file (added/modified/renamed) must be named in some added receipt, exempting receipts and the historical `COSTS.md`/`STEERING.md`/`CONSTITUTION.md` ledgers (scope-creep guard, #272); and a `## Audit` section carrying a `PASS`/`REFUTED` verdict from a fresh-context sub-agent that checked the receipt against the diff and the issue (#272, built on the shared `require_attestation` lib.sh infra; needs kit ≥ 0.9.0). Session-only stubs (a receipt whose only `## ` heading is `## Session` — created on demand by the session-identity hook) are exempt from the shape / crosswalk / Decisions / Verification / Audit / coverage rules until the agent adds narrative. Historical `## Accounting` stubs remain grandfathered for existing repositories only. Waiver: `governance: allow-receipt-per-issue <reason>` exempts a whole receipt. |
| `commit-issue-receipt-match` | — | Every non-merge, non-revert commit adds or updates a `receipts/issue-<N>.md`; the touched receipt path **is** the issue anchor (file-first, #293 — survives squash natively, no body trailer). `commit-msg` hook (Mode A) + CI merge-base→HEAD walk (Mode B). Per-commit waiver: `governance: allow-commit-issue-receipt-match <reason>`. |
| `issue-templates` | — | `.github/ISSUE_TEMPLATE/` contains proposal + bug issue forms plus config; blank issues disabled; proposal requires Context / Decision / Scope / Acceptance criteria / Validation / Open questions; bug requires the core defect-report fields. Ships the templates under `install-assets/`. |
| `issues-tracked` | — | `QUALITY.md` exists at repo root with `Open` and `Resolved` sections. Ships `install-assets/QUALITY.md`. |
| `agent-session-identity` | — | **`always_install: true`.** At commit time, the pre-commit hook detects only explicit runtime identity signals and records one `date | harness | session` row under `## Session` → `### Identifiers` in the issue receipt. It never opens transcripts, session databases, usage files, or harness-private paths; human commits and unnamed runtimes are safe no-ops. `check.sh` validates table shape and requires the active runtime/session row in the commit-message lane. |
| `doc-integrity` | — | **`always_install: true` — standard rules ship in the manifest's tunable `RULES` list.** Makes system-of-record documents append-only relative to the change-set baseline. The overlay may add rules or remove defaults with `!<rule>`. Modes: `frozen-files`, `append-only`, and `frozen-section`. `commit-msg` hook + CI merge-base→HEAD walk. |
| `toolchain-config-protection` | — | A commit modifying toolchain config must carry a `governance: allow-toolchain-config <reason>` line. Protected paths live in the manifest's tunable list config; merge/revert commits are skipped. |

---

## The scheduled lane

The kit ships the off-commit-path [scheduled lane](SCHEDULE_FLOW.md): a managed driver plus `governance workflow generate`, which compiles every non-empty directive-owned `SCHEDULE_CRON` into one consumer-owned workflow. Bundled directives opt in explicitly with a `schedule` trigger and own their rubric, command, and cadence; identical crons share a workflow trigger but every directive is judged independently. There is no schedule-wide budget or judge batching. Evidence is resolved per member, so range and per-commit judges coexist in one workflow. Repo-local and community packs may author standalone schedule-only directives with `hook: none`, `triggers: [schedule]`, and no mechanical `check.sh`. The shared live-attestation infra ([JUDGE.md](JUDGE.md), issue #272) remains the commit-time moment of the same judgment primitive.

---

## Presets (per-pack, unioned at init)

Each pack declares only the preset tiers it contributes to; `governance init` unions the chosen preset across all three bundled packs. The union reproduces the directive sets below.

| Preset | Directives (unioned across all bundled packs) |
|---|---|
| `minimal`  | `required-docs`, `internal-doc-links`, `repo-hygiene`, `managed-tree-integrity` |
| `standard` | *minimal* + `commit-message-format`, `issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`, `agent-session-identity`, `toolchain-config-protection`, `doc-integrity` |
| `strict`   | *standard* + `no-orphan-todos`, `no-unjustified-suppressions` |

`repo-hygiene`, `doc-integrity`, and `agent-session-identity` are `always_install: true` — they install regardless of preset selection. `always_install: true` is reserved to the `governance-kit/*` bundled packs. Session provenance is mandatory in this kit's model because every commit is agent-authored.

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
     # config:                            # optional typed defaults/docs/tunability
     #   - {name: LIMIT, type: scalar, doc: Maximum count., default: 5, tunable: true}
     # standards:                         # optional advisory metadata
     #   - "OpenSSF Scorecard: <Check>"
     # always_install: true               # optional; reserved to governance-kit/* bundled packs
     # requires_hook_strategy: githooks   # optional environment filter
     ```
   - `config:` in `directive.yaml` — optional typed config registry (see [PACK_AUTHORING.md](PACK_AUTHORING.md)). Its presence seeds the generic user overlay.
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

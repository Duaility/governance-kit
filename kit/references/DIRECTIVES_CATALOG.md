# Directives Catalog

Every directive lives in a **pack** — the namespace directives are grouped into. Each directive is a self-contained folder at `directives/<directive-id>/` carrying its metadata (`directive.yaml`), the executable test (`check.sh`), its Directive snippet (`constitution.md`), and pass/fail evals (`evals/test.sh`). The pack's top-level `pack.yaml` carries pack identity (community packs may also declare presets). The bootstrap skill discovers every pack at activation and installs the bundled set in full.

A directive's identity is `<owner>/<pack>/<id>`. The short id is a *given name*, not a global claim: two packs may ship same-named directives that check different things — they coexist and both run (`run.sh <bare-id>` runs every homonym; `run.sh <owner>/<pack>/<id>` runs exactly one). Suppression of another pack's directive is only ever explicit, via `replaces: <owner>/<pack>/<id>`.

One pack ships in-tree:

| Pack | Location | Concern | Default? |
|---|---|---|---|
| `governance-kit/audit` | `packs/audit/` | The kit primitives — managed tree, commit subject, receipts, frozen record. | Always present (bundled). |

There is no preset menu. `governance init` installs every directive in this pack. Community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`; they may still declare `minimal`/`standard`/`strict` for their own slice. Former `governance-kit/{foundation,commits,docs}` packs are retired (issue #370). Existing installs drop leftover lock entries with `governance pack remove` after the audit pack update that absorbs the moved directives. For authoring a **third-party pack**, see [PACK_AUTHORING.md](PACK_AUTHORING.md).

Most directives are **synchronous** — enforced by `check.sh` at a git hook and in CI. A directive can also carry a lane-independent `judge:` rubric (issues #142, #325, #355). Lane membership is explicit in `triggers:`. Live attestation uses fixed `ATTEST_SECTION` and `ATTEST_CMD` config; scheduled re-adjudication uses consumer-selected `SCHEDULE_CMD`, per-member evidence, and optional staleness config. The scheduled lane never gates a commit, push, or PR by itself — only a mechanical `check.sh` member's failure fails its job. Every bundled directive ships a schedule-eligible rubric alongside its mechanical check; repo-local and community packs may author standalone `hook: none`, `triggers: [schedule]` judges with no `check.sh`. See [SCHEDULE_FLOW.md](SCHEDULE_FLOW.md).

The **Standards** column records the external standard a directive implements (OpenSSF Scorecard checks, CWE entries, …) so coverage and gaps are visible. It is advisory metadata (`standards:` in `directive.yaml`); empty cells are not failures, they are the roadmap.

---

## `governance-kit/audit`

The kit primitives. All four install on `governance init`. Session identifiers are a harness concern (Claude Code's `Claude-Session:` trailer and equivalents). GitHub issue forms and toolchain-config waivers are not bundled.

| Directive | Standards | What it checks |
|---|---|---|
| `managed-tree-integrity` | — | The vendored `.governance/` tree matches the content digests recorded at apply time, so it changes only through the install/update verbs — never by hand. For every `packs.lock` pack entry with a `digest:` map, each vendored directive folder matches its recorded `sha256` (and no unrecorded directive folder appears); for every file in `install.yaml`'s `managed_digests:` map (`run.sh`, `lib.sh`, the CI workflow, and the generated `.github/workflows/governance-schedule.yml`, plus legacy prefixed workflows on pre-redesign installs), the file matches its recorded `sha256`. The local-only hook dispatchers (`.githooks/*` etc.) are **not** digested (issue #267). Also asserts each managed file's `# governance-kit:managed kit-version=<v>` marker equals the manifest's `kit_version`. Works **offline in any repo**. Per-unit waiver via `.governance/conf/<owner>/<pack>/managed-tree-integrity.conf`. |
| `commit-message-format` | — | Commit subjects match `<type>(scope)?!?: subject (#123)` — Conventional Commits prefix **plus** a trailing GitHub issue reference. Default types live in the manifest's tunable `TYPES` list; the overlay can add a type or remove one with `!<type>`. Installs a `commit-msg` hook. |
| `receipt-per-issue` | — | Unique `issue-<N>` receipts (optional kebab-case slug). A **completed change** (PR aggregate `base..HEAD`, or a commit directly on the default branch) must add or update a receipt; that non-stub receipt needs `## What changed` and `## Verification` (fence **plus** outcome, or an `http(s)` URL). A fence alone is not evidence. `## Decisions` is optional. Independent review (`## Audit`) remains required. Intermediate commits do not each need a receipt edit. Historical session/accounting stubs cannot close a completed change. Waiver: `governance: allow-receipt-per-issue <reason>` on the receipt or in the commit body. |
| `doc-integrity` | — | Receipts freeze once on the trunk (`frozen-files receipts/*.md`, always restored). The constitution Evolution Log keeps baseline lines verbatim. Overlay may add `frozen-files` / `append-only` / `frozen-section` rules or drop the Evolution Log freeze. `commit-msg` hook + CI merge-base→HEAD walk. |

---

## The scheduled lane

The kit ships the off-commit-path [scheduled lane](SCHEDULE_FLOW.md): a managed driver plus `governance workflow generate`, which compiles every non-empty directive-owned `SCHEDULE_CRON` into one consumer-owned workflow. Bundled directives opt in explicitly with a `schedule` trigger and own their rubric, command, and cadence; identical crons share a workflow trigger but every directive is judged independently. There is no schedule-wide budget or judge batching. Evidence is resolved per member, so range and per-commit judges coexist in one workflow. Repo-local and community packs may author standalone schedule-only directives with `hook: none`, `triggers: [schedule]`, and no mechanical `check.sh`. The shared live-attestation infra ([JUDGE.md](JUDGE.md), issue #272) remains the commit-time moment of the same judgment primitive.

---

## Install set

`governance init` installs all four bundled directives. There is no `minimal` / `standard` / `strict` menu. Community packs may still declare presets for their own directives. `always_install: true` remains reserved to the bundled `governance-kit/*` pack.

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

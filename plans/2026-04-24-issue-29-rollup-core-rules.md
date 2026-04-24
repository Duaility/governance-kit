<!-- last-verified: 2026-04-24 -->

# 2026-04-24 — Roll up low-signal core rules into substantive ones

## Goal

The `core` pack grew to 21 rules, most of them single-fact grep-or-exists
checks (`readme-exists`, `security-md-exists`, `license-exists`,
`no-merge-conflict-markers`, `no-large-files`, …). Every one added a
rule.yaml / check.sh / constitution.md / evals triple for a one-line
assertion. The menu got noisy, the `CONSTITUTION.md` got noisy, the
rule picker got noisy, and the signal-to-volume ratio of governance
output dropped.

Consolidate related one-fact rules into three substantive rolled-up
rules. Each sub-check is preserved as an internal pass/fail item and
can be disabled individually via env, so users who want the old
granularity still have it without shipping 16 separate rule folders.

Closes [#29](https://github.com/Duaility/governance-kit/issues/29).

## Scope

### Rolled up

- `required-docs` — 9 presence sub-checks: `constitution`, `agents`,
  `readme`, `license`, `security`, `architecture`, `ci-workflow`,
  `env-example`, `hooks`. Opt-out: `GOVERNANCE_REQUIRED_DOCS_DISABLE`.
- `repo-hygiene` — 5 hygiene sub-checks: `merge-markers`, `large-files`,
  `build-artifacts`, `debug-statements`, `file-size-limit`.
  `always_install: true` preserved from `no-merge-conflict-markers`.
  Opt-out: `GOVERNANCE_REPO_HYGIENE_DISABLE`. Waiver name:
  `allow-repo-hygiene`.
- `secrets-hygiene` — 2 sub-checks: `no-secrets`, `dotenv`.
  Opt-out: `GOVERNANCE_SECRETS_HYGIENE_DISABLE`. Waiver name:
  `allow-secrets-hygiene`.

### Kept as-is

`conventional-commits`, `doc-freshness`, `workflows-hardened`,
`no-broken-internal-doc-links`, `no-orphan-todos`. Each is a distinct
concern that earns its own rule.

### Out of scope

- `agent-governance` pack — not touched.
- Pack format / discovery / hook-dispatch — not touched.
- Migration tooling — downstream consumers who installed the old rule
  ids by name will need to update their `installed-packs.yaml` and
  waiver comments. The evolution log calls this out.

## Tradeoffs

- **Sub-check DISABLE as the escape hatch.** We chose one rolled-up rule
  with internal opt-outs over keeping 16 separate rules. The env var is
  mentioned in each rule's `constitution.md` Exceptions section so it
  surfaces at amendment time.
- **`always_install: true` on the rollup.** `no-merge-conflict-markers`
  used to be always-on. Repo-hygiene inherits that flag, which means
  large-files / build-artifacts / debug-statements / file-size-limit are
  also always-on by default. Acknowledged in the constitution text as the
  price of the consolidation.
- **Waiver rename is breaking.** Downstream repos with
  `# governance: allow-no-secrets` or `# governance: allow-no-debug-statements`
  comments need to rewrite to the new names. Called out in the evolution
  log; no shim.

## Dogfood

This repo's governance install migrates to the new rule set:

- `.governance-kit/installed-packs.yaml` lists the 7 core + 4
  agent-governance rules (down from 12 core + 4).
- `tests/governance/rules/{required-docs,repo-hygiene,secrets-hygiene}/`
  replace 15 individual rule folders.
- `CONSTITUTION.md` invariants replaced + evolution log entry.
- Added real `SECURITY.md` and `ARCHITECTURE.md` so `required-docs`
  passes its presence sub-checks.
- Added `.github/workflows/pack-tests.yml` to run `scripts/test-packs.sh`
  on PR — a legitimate non-governance CI workflow that satisfies the
  `required-docs` `ci-workflow` sub-check without self-referential
  escape hatches.

## Verification

- `bash scripts/test-packs.sh` — 2 packs, 12 rules, 12 evals pass.
  Fresh-repo contract seeds LICENSE / SECURITY.md / ARCHITECTURE.md.
- `bash tests/governance/run.sh` — all 11 rules pass in this repo.

## Follow-ups

- Peripheral eval fixtures under `governance-{reset,gardener,amend}/evals/files/`
  still reference the old rule ids. These are frozen snapshots used as
  test data; updating them is cosmetic. Flag as a separate pass.
- Downstream-consumer migration note in the project README — not shipped
  here; pack versioning will handle this at the next release bump.

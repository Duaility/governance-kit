# Issue #366 — self-contained directive configuration

## Checklist

- [x] Replace `defaults.conf` with a strict typed `directive.yaml config:` registry.
- [x] Make the per-directive overlay the sole persistent consumer override and remove the environment tier.
- [x] Reduce `judge:` to `inputs`, `checks`, and `gate`; move lane behavior into config.
- [x] Make schedule eligibility explicit and author-owned.
- [x] Resolve evidence per member and surface staleness advisories.
- [x] Retrofit bundled directive tunables and migrate lifecycle engines.
- [x] Update normative references, generated docs, evals, and runtime tests.
- [x] Preserve the release-managed `.governance/` tree unchanged.
- [x] Remove judge grouping and compile all scheduled crons into one generated workflow without a schedule budget.
- [x] Make clean schedule runs advance a durable resume marker and deduplicate un-adjudicated members.
- [x] Validate per-member evidence and enforce explicit schedule/attest lane membership.
- [x] Keep manifest, overlay, workflow, reset, and digest parsers on one comment/tunability contract.
- [x] Cover tunable and fixed config behavior, schedule fixtures, Bash 3.2 empty-array paths, and doc-sync extraction.

## What changed

Directive manifests now carry each setting's type, documentation, default, and tunability. Runtime helpers enforce that contract without an environment fallback, lifecycle verbs seed generic overlays from manifest presence, pack planning reports registry drift, and validation rejects legacy defaults files or lane-specific judge keys.

The scheduled lane now derives evidence for every member independently, supports mixed range/commit members in one run, treats triggers as author-owned policy, and reports stale cadence declarations without rewriting the lane.

The follow-up simplification removes cross-directive judge grouping entirely. Each pending section receives its own fresh-context judgment, while identical directive-owned cron expressions share only a workflow trigger. `governance workflow generate` now reconciles one `.github/workflows/governance-schedule.yml`; schedule-wide budgets and legacy lane files are gone.

Remove judge grouping and compile all scheduled crons into one generated workflow without a schedule budget.

The review follow-up makes the schedule runtime resumable on clean runs via a
lane state issue, prevents repeated un-adjudicated issue creation, validates
`SCHEDULE_EVIDENCE`, preserves hand-authored workflow files, and gives the
generated job a finite 30-minute GitHub timeout without restoring a
per-directive budget. Config readers now share quote-aware inline-comment
semantics, accept normal YAML whitespace/comments and scalar booleans, and
honor only tunable overlays. Reset, validator, lifecycle, constitution,
fixture, and generated-reference paths were updated together.

- Replace `defaults.conf` with a strict typed `directive.yaml config:` registry. The manifests now own values and docs, and the legacy files are deleted.
- Make the per-directive overlay the sole persistent consumer override and remove the environment tier. `conf_get` and `conf_list` enforce manifest tunability.
- Reduce `judge:` to `inputs`, `checks`, and `gate`; move lane behavior into config. Validator and runtime coverage reject the old fused shape.
- Make schedule eligibility explicit and author-owned. Only manifest `triggers:` determine membership.
- Resolve evidence per member and surface staleness advisories. Mixed range/commit lanes and cadence warnings are covered by schedule tests.
- Retrofit bundled directive tunables and migrate lifecycle engines. All three bundled packs and install/update planning use the registry.
- Update normative references, generated docs, evals, and runtime tests. Source references and generated site pages are synchronized.
- Preserve the release-managed `.governance/` tree unchanged. Its real update remains the post-release consumer-sync step required by repository policy.
- Make clean schedule runs advance a durable resume marker and deduplicate un-adjudicated members.
- Validate per-member evidence and enforce explicit schedule/attest lane membership.
- Keep manifest, overlay, workflow, reset, and digest parsers on one comment/tunability contract.
- Cover tunable and fixed config behavior, schedule fixtures, Bash 3.2 empty-array paths, and doc-sync extraction.

Changed or removed paths:

```text
AGENTS.md
CONSTITUTION.md
docs/concepts/audit-chain.mdx
docs/concepts/runtime.mdx
docs/guide/configuration.mdx
docs/reference/authoring-directives.mdx
docs/reference/authoring-packs.mdx
docs/reference/directive-catalog.mdx
docs/reference/schemas.mdx
docs/reference/verbs.mdx
kit/assets/amend/directive.template.sh
kit/assets/conf-overlay.stub.conf
kit/assets/dot-governance/lib.sh
kit/assets/dot-governance/run.sh
kit/assets/dot-governance/schedule.sh
kit/assets/governance-schedule.template.yml
kit/assets/packs/lib/initapply.py
kit/assets/packs/lib/install.sh
kit/assets/packs/lib/applylib.py
kit/assets/packs/lib/digestlib.py
kit/assets/packs/lib/hooks.sh
kit/assets/packs/lib/packapply.py
kit/assets/packs/lib/packctl.py
kit/assets/packs/lib/packplan.py
kit/assets/packs/lib/packvalidate.py
kit/assets/packs/lib/packverb.py
kit/assets/packs/lib/resetapply.py
kit/assets/packs/lib/schedulelib.py
kit/assets/packs/lib/workflowlib.py
kit/assets/packs/lib/resetplan.py
kit/evals/schedule/evals.json
kit/evals/schedule/files/scheduled-repo-with-lane/.github/workflows/governance-schedule.yml
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/install.yaml
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/conf/acme/local/naming-convention.conf
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/conf/governance-kit/core/license-headers.conf
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/conf/governance-kit/core/secrets-hygiene.conf
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/acme/local/directives/naming-convention/directive.yaml
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/license-headers/directive.yaml
kit/evals/schedule/files/scheduled-repo-with-lane/.governance/packs/governance-kit/core/directives/secrets-hygiene/directive.yaml
kit/evals/schedule/files/scheduled-repo-with-lane/README.md
kit/evals/schedule/files/scheduled-repo/.github/workflows/governance-schedule.yml
kit/evals/schedule/files/scheduled-repo/.governance/install.yaml
kit/evals/schedule/files/scheduled-repo/README.md
kit/evals/schedule/files/scheduled-repo/.governance/conf/acme/local/naming-convention.conf
kit/evals/schedule/files/scheduled-repo/.governance/conf/governance-kit/core/license-headers.conf
kit/evals/schedule/files/scheduled-repo/.governance/conf/governance-kit/core/secrets-hygiene.conf
kit/evals/schedule/files/scheduled-repo/.governance/packs/acme/local/directives/naming-convention/directive.yaml
kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/license-headers/directive.yaml
kit/evals/schedule/files/scheduled-repo/.governance/packs/governance-kit/core/directives/secrets-hygiene/directive.yaml
kit/references/DIRECTIVES_CATALOG.md
kit/references/DIRECTIVE_AUTHORING.md
kit/references/DIRECTIVE_VERBS.md
kit/references/INIT_FLOW.md
kit/references/INSTALL_SCHEMA.md
kit/references/JUDGE.md
kit/references/LIB_API.md
kit/references/PACK_AUTHORING.md
kit/references/PACK_VERBS.md
kit/references/RESET_FLOW.md
kit/references/RELEASE_FLOW.md
kit/references/SCHEDULE_FLOW.md
kit/references/UNINSTALL_MATRIX.md
kit/references/UPDATE_FLOW.md
kit/references/VERBS.md
packs/audit/directives/agent-session-identity/check.sh
packs/audit/directives/agent-session-identity/directive.yaml
packs/audit/directives/agent-session-identity/lib/runtime.sh
packs/audit/directives/agent-session-identity/hooks/pre-commit.sh
packs/audit/directives/commit-issue-receipt-match/check.sh
packs/audit/directives/commit-issue-receipt-match/directive.yaml
packs/audit/directives/doc-integrity/check.sh
packs/audit/directives/doc-integrity/constitution.md
packs/audit/directives/doc-integrity/defaults.conf
packs/audit/directives/doc-integrity/directive.yaml
packs/audit/directives/doc-integrity/evals/test.sh
packs/audit/directives/issue-templates/check.sh
packs/audit/directives/issue-templates/directive.yaml
packs/audit/directives/issues-tracked/check.sh
packs/audit/directives/issues-tracked/directive.yaml
packs/audit/directives/issues-tracked/evals/test.sh
packs/audit/directives/receipt-per-issue/check.sh
packs/audit/directives/receipt-per-issue/defaults.conf
packs/audit/directives/receipt-per-issue/directive.yaml
packs/audit/pack.yaml
packs/audit/directives/toolchain-config-protection/check.sh
packs/audit/directives/toolchain-config-protection/constitution.md
packs/audit/directives/toolchain-config-protection/defaults.conf
packs/audit/directives/toolchain-config-protection/directive.yaml
packs/commits/directives/commit-message-format/check.sh
packs/commits/directives/commit-message-format/constitution.md
packs/commits/directives/commit-message-format/defaults.conf
packs/commits/directives/commit-message-format/directive.yaml
packs/commits/directives/no-orphan-todos/check.sh
packs/commits/directives/no-orphan-todos/directive.yaml
packs/commits/directives/no-unjustified-suppressions/check.sh
packs/commits/directives/no-unjustified-suppressions/directive.yaml
packs/commits/pack.yaml
packs/foundation/directives/internal-doc-links/check.sh
packs/foundation/directives/internal-doc-links/defaults.conf
packs/foundation/directives/internal-doc-links/directive.yaml
packs/foundation/directives/managed-tree-integrity/check.sh
packs/foundation/directives/managed-tree-integrity/defaults.conf
packs/foundation/directives/managed-tree-integrity/directive.yaml
packs/foundation/directives/managed-tree-integrity/evals/test.sh
packs/foundation/directives/managed-tree-integrity/constitution.md
packs/foundation/directives/repo-hygiene/check.sh
packs/foundation/directives/repo-hygiene/constitution.md
packs/foundation/directives/repo-hygiene/defaults.conf
packs/foundation/directives/repo-hygiene/directive.yaml
packs/foundation/directives/repo-hygiene/evals/test.sh
packs/foundation/directives/required-docs/check.sh
packs/foundation/directives/required-docs/defaults.conf
packs/foundation/directives/required-docs/directive.yaml
packs/foundation/directives/required-docs/evals/test.sh
packs/foundation/directives/required-docs/constitution.md
packs/foundation/pack.yaml
scripts/test-conf-knob-doc-sync.sh
scripts/test-init.py
scripts/test-install-sh.sh
scripts/test-packctl-subagent.py
scripts/test-packctl-triggers.py
scripts/test-packctl-validate.py
scripts/test-packverb-apply.py
scripts/test-runtime.sh
scripts/test-schedule.sh
scripts/test-schedulelib.py
scripts/test-subagent.sh
scripts/test.sh
skill/SKILL.md
receipts/issue-366-self-contained-directive-config.md
```

## Out of scope

Release version bumps and the post-release refresh of the pinned `.governance/` consumer tree are intentionally excluded. Those remain release-script and real update-verb responsibilities.

## Decisions

- One branch and one PR implement the full umbrella scope, per the user request.
- `config:` is a strict list of mappings so the bash runtime can consume one validated shape without another parser or compatibility layer.
- Fixed entries ignore overlay rows; tunable entries use the overlay; environment variables never override config.
- List overlays are key-qualified (`KEY+=item` / `KEY-=item`) when a manifest has multiple list keys; bare/`!item` syntax remains shorthand for single-list directives.
- `SCHEDULE_CMD` is a consumer-selected, tunable command setting; `ATTEST_CMD` remains an author-fixed execution contract. A missing schedule command is reported honestly; no environment fallback supplies it.
- Schedule evidence defaults from `surface` when `SCHEDULE_EVIDENCE` is absent: `repo-state` → `range`, `change-set` → `commits`.
- Old `defaults.conf`, `TRIGGERS=` overrides, lane-wide `--evidence`, and lane-specific `judge:` keys fail rather than silently degrading.
- Scheduled cadence is a tunable `SCHEDULE_CRON` value owned by each directive; an empty value opts out. The generated workflow groups only identical cron triggers and never combines judge prompts or verdicts. Clean runs persist a lane state marker, while open finding/un-adjudicated issues remain deduplicated.
- Receipt coupling is a fixed cross-pack invariant even when other doc-integrity rules are tunable; workflow reconciliation removes only kit-marked legacy artifacts and preserves unmarked hand-authored files.
- The review's suggested-disposition follow-ups and backward-compatible migration of already-released consumer snapshots are intentionally not part of this PR, per the user's direction.

## Verification

```sh
bash scripts/test.sh
bash .governance/run.sh
npm run docs:gen:check
bash scripts/test-runtime.sh
bash scripts/test-schedule.sh
python3 scripts/test-schedulelib.py
python3 scripts/test-packctl-subagent.py
bash scripts/test-conf-knob-doc-sync.sh
git diff --check
```

## Audit

PASS — A fresh-context re-audit confirmed that the typed registry, keyed list overlays (including `#`-prefixed values), consumer-selected schedule commands, explicit lane membership, clean-run resume state, per-member schedule behavior, parser parity, docs, and regression coverage implement the source feature coherently. Release-time floors and the post-release dogfood sync remain correctly deferred by repository policy; backward-compatible migration is intentionally out of scope for this v0 change.

## Layer boundaries

PASS — Generic mechanics remain in `kit/`, directive policy and config remain in source `packs/`, specifications/generated docs/tests remain in their owned layers, the protected consumed tree is untouched, and dependencies continue downward.

## Steering

PASS — The transcript contains one human-steering event: the ordinal 168 correction directing the agent to keep the full scope in one issue and one PR. That correction is recorded once in the Steering ledger; the initial task request is ordinary tasking, and there are no interrupts or tool-denial events to record.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-08-06 | codex | 019fd69e-ee48-7c02-b0a9-9f83691f3f90 | gpt-5.6-luna | 3393191 | 0 | 153488384 | 380599 | - | session-file |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-019fd69e-1786012648-1 | 019fd69e-ee48-7c02-b0a9-9f83691f3f90 | #366 | correction | classifier | Keep the entire scope in one issue and one PR; do not split the work. | feat(config): unify directive configuration (#366) | 168 | 2026-08-06T10:37:28.430Z |

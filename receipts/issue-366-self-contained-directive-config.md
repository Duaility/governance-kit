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

## What changed

Directive manifests now carry each setting's type, documentation, default, and tunability. Runtime helpers enforce that contract without an environment fallback, lifecycle verbs seed generic overlays from manifest presence, pack planning reports registry drift, and validation rejects legacy defaults files or lane-specific judge keys.

The scheduled lane now derives evidence for every member independently, supports mixed range/commit members in one run, treats triggers as author-owned policy, and reports stale cadence declarations without rewriting the lane.

- Replace `defaults.conf` with a strict typed `directive.yaml config:` registry. The manifests now own values and docs, and the legacy files are deleted.
- Make the per-directive overlay the sole persistent consumer override and remove the environment tier. `conf_get` and `conf_list` enforce manifest tunability.
- Reduce `judge:` to `inputs`, `checks`, and `gate`; move lane behavior into config. Validator and runtime coverage reject the old fused shape.
- Make schedule eligibility explicit and author-owned. Only manifest `triggers:` determine membership.
- Resolve evidence per member and surface staleness advisories. Mixed range/commit lanes and cadence warnings are covered by schedule tests.
- Retrofit bundled directive tunables and migrate lifecycle engines. All three bundled packs and install/update planning use the registry.
- Update normative references, generated docs, evals, and runtime tests. Source references and generated site pages are synchronized.
- Preserve the release-managed `.governance/` tree unchanged. Its real update remains the post-release consumer-sync step required by repository policy.

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
docs/reference/verbs.mdx
kit/assets/amend/directive.template.sh
kit/assets/conf-overlay.stub.conf
kit/assets/dot-governance/lib.sh
kit/assets/dot-governance/run.sh
kit/assets/dot-governance/schedule.sh
kit/assets/governance-schedule.template.yml
kit/assets/packs/lib/initapply.py
kit/assets/packs/lib/install.sh
kit/assets/packs/lib/packapply.py
kit/assets/packs/lib/packctl.py
kit/assets/packs/lib/packplan.py
kit/assets/packs/lib/packvalidate.py
kit/assets/packs/lib/resetapply.py
kit/assets/packs/lib/schedulelib.py
kit/evals/schedule/evals.json
kit/evals/schedule/files/scheduled-repo-with-lane/README.md
kit/references/DIRECTIVES_CATALOG.md
kit/references/DIRECTIVE_AUTHORING.md
kit/references/DIRECTIVE_VERBS.md
kit/references/INIT_FLOW.md
kit/references/JUDGE.md
kit/references/LIB_API.md
kit/references/PACK_AUTHORING.md
kit/references/PACK_VERBS.md
kit/references/RELEASE_FLOW.md
kit/references/SCHEDULE_FLOW.md
kit/references/UPDATE_FLOW.md
kit/references/VERBS.md
packs/audit/directives/agent-session-identity/check.sh
packs/audit/directives/agent-session-identity/directive.yaml
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
packs/audit/directives/receipt-per-issue/check.sh
packs/audit/directives/receipt-per-issue/defaults.conf
packs/audit/directives/receipt-per-issue/directive.yaml
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
packs/foundation/directives/internal-doc-links/check.sh
packs/foundation/directives/internal-doc-links/defaults.conf
packs/foundation/directives/internal-doc-links/directive.yaml
packs/foundation/directives/managed-tree-integrity/check.sh
packs/foundation/directives/managed-tree-integrity/defaults.conf
packs/foundation/directives/managed-tree-integrity/directive.yaml
packs/foundation/directives/repo-hygiene/check.sh
packs/foundation/directives/repo-hygiene/constitution.md
packs/foundation/directives/repo-hygiene/defaults.conf
packs/foundation/directives/repo-hygiene/directive.yaml
packs/foundation/directives/repo-hygiene/evals/test.sh
packs/foundation/directives/required-docs/check.sh
packs/foundation/directives/required-docs/defaults.conf
packs/foundation/directives/required-docs/directive.yaml
packs/foundation/directives/required-docs/evals/test.sh
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
receipts/issue-366-self-contained-directive-config.md
```

## Out of scope

Release version bumps and the post-release refresh of the pinned `.governance/` consumer tree are intentionally excluded. Those remain release-script and real update-verb responsibilities.

## Decisions

- One branch and one PR implement the full umbrella scope, per the user request.
- `config:` is a strict list of mappings so the bash runtime can consume one validated shape without another parser or compatibility layer.
- Fixed entries ignore overlay rows; tunable entries use the overlay; environment variables never override config.
- List overlays are key-qualified (`KEY+=item` / `KEY-=item`) when a manifest has multiple list keys; bare/`!item` syntax remains shorthand for single-list directives.
- Attest and schedule commands are fixed author contracts. A missing command is reported honestly; no environment fallback supplies it.
- Schedule evidence defaults from `surface` when `SCHEDULE_EVIDENCE` is absent: `repo-state` → `range`, `change-set` → `commits`.
- Old `defaults.conf`, `TRIGGERS=` overrides, lane-wide `--evidence`, and lane-specific `judge:` keys fail rather than silently degrading.

## Verification

```sh
bash scripts/test.sh
bash .governance/run.sh
npm run docs:gen:check
git diff --check
```

## Audit

PASS — A fresh-context re-audit confirmed that the typed registry, keyed list overlays (including `#`-prefixed values), fixed judge commands, per-member schedule behavior, parser parity, docs, and regression coverage implement the source feature coherently. Release-time floors and the post-release dogfood sync remain correctly deferred by repository policy.

## Layer boundaries

PASS — Generic mechanics remain in `kit/`, directive policy and config remain in source `packs/`, specifications/generated docs/tests remain in their owned layers, the protected consumed tree is untouched, and dependencies continue downward.

## Steering

PASS — The transcript contains one human-steering event: the ordinal 168 correction directing the agent to keep the full scope in one issue and one PR. That correction is recorded once in the Steering ledger; the initial task request is ordinary tasking, and there are no interrupts or tool-denial events to record.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-08-06 | codex | 019fd69e-ee48-7c02-b0a9-9f83691f3f90 | - | - | - | - | - | - | unresolved |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-019fd69e-1786012648-1 | 019fd69e-ee48-7c02-b0a9-9f83691f3f90 | #366 | correction | classifier | Keep the entire scope in one issue and one PR; do not split the work. | feat(config): unify directive configuration (#366) | 168 | 2026-08-06T10:37:28.430Z |

# issue-251 — move kit-authoring checks from dogfood directives to test layers

Closes [#251](https://github.com/Duaility/governance-kit/issues/251).

## Checklist

- [x] Three test layers added and wired into scripts/test.sh
- [x] Three dogfood directives removed following the pinned kit's directive-remove flow
- [x] CONSTITUTION updated; illustrative lock-shape samples surfaced, not churned
- [x] Suite green

## What changed

- **Three test layers added and wired into scripts/test.sh.** Ported the logic of the three dogfood directives into standalone kit-internal test scripts: `scripts/test-kit-version-consistency.sh` (kit/pack version-axis floor: `kit/assets/kit.yaml` version ≥ every `packs/*/pack.yaml` `min_governance_kit`), `scripts/test-precommit-gate.sh` (the `.githooks/pre-commit` hook invokes `scripts/test.sh` and every required layer is wired — now including the three new layers themselves), and `scripts/test-conf-knob-doc-sync.sh` (every `conf_get <id> <KEY>` in a bundled `check.sh` has a `<KEY>=` row in its sibling `defaults.conf`). All three are wired into `scripts/test.sh` as `run_layer` entries after the pack-smoke layer. Each is a faithful port — same checks, same waiver handling — minus the `lib.sh`/`directive_*` scaffolding, exiting non-zero on any violation.
- **Three dogfood directives removed following the pinned kit's directive-remove flow.** Resolved the repo's pinned kit (`bootstrap.py current` → `kit/v0.7.2`, served from cache, offline) and followed its `DIRECTIVE_AMEND_FLOW.md` removal branch for `kit-version-consistency`, `pre-commit-test-gate`, and `conf-knob-doc-sync` in the `duaility/governance-kit` local pack: `git rm` the three directive folders, removed their `CONSTITUTION.md` Directives subsections, appended one Evolution Log entry, and synced the lockfile's local-pack `directives:` list via `packverb lock-add` (now `[consumed-tree-integrity]`). The local pack retains `consumed-tree-integrity` — it is retired separately in item C, once its universal replacement (`managed-tree-integrity`, item A) lands in the vendored tree, so the vendored tree is never left unguarded.
- **CONSTITUTION updated; illustrative lock-shape samples surfaced, not churned.** The three Directives subsections were removed from `CONSTITUTION.md` and the removal recorded in the Evolution Log. The `directives: [pre-commit-test-gate]` samples in `kit/references/LOCK_SCHEMA.md`, `kit/references/PACK_VERBS.md`, `docs/concepts/packs.mdx`, `docs/reference/schemas.mdx`, and a `scripts/test-packverb.py` lock-add fixture are deliberately left as-is: they illustrate lockfile *shape* with an opaque directive id and reference no live directive folder, so nothing breaks. `DIRECTIVES_CATALOG.md` lists shippable bundled directives, not repo-local dogfood ones, so it needed no edit.
- **Suite green.** Both the kit-internal umbrella (`scripts/test.sh`) and the dogfood governance suite (`.governance/run.sh`) pass; the governance suite drops from 21 to 18 directives, and `consumed-tree-integrity` still passes because the vendored local-pack directive set now equals the lockfile list.

## Out of scope

- `managed-tree-integrity` and the digest mechanism (work item A of the redesign).
- Retiring `consumed-tree-integrity` (work item C, post-release — gated on the universal replacement reaching the vendored tree).
- Genericizing the illustrative `pre-commit-test-gate` lock-shape samples in the schema docs / docs site / packverb test — harmless opaque ids; a possible later cleanup, not churned here.

## Decisions

- **Hand-executed the removal per the directive-remove flow rather than a single engine call.** `directive *` verbs have no plan/apply engine (unlike `pack`/`init`/`uninstall`); the pinned kit's `DIRECTIVE_AMEND_FLOW.md` directs the agent to delete folders, edit `CONSTITUTION.md`, and run `packverb` for the lock sync. Followed that flow, deferring the commit so all of item B lands in one commit through the hook.
- **Kept `consumed-tree-integrity` in this PR.** Removing it now would leave the dogfood's vendored tree mechanically unguarded during the release lag before `managed-tree-integrity` arrives. It is retired in item C, in the same post-release `pack update` PR that lands the replacement with digests.
- **Left the illustrative lock-shape samples untouched.** Editing four docs (and their freshness markers) plus a unit-test fixture to swap an opaque example id is churn for no functional gain; the samples reference lockfile shape, not a live directive.

## Verification

```sh
# the three ported layers pass standalone
bash scripts/test-kit-version-consistency.sh   # ✓ axis floor holds
bash scripts/test-precommit-gate.sh            # ✓ hook runs test.sh; all required layers wired
bash scripts/test-conf-knob-doc-sync.sh        # ✓ every conf_get knob has a defaults.conf row

# both suites green
bash scripts/test.sh        # ✓ all kit-internal test layers passed (incl. the 3 new layers)
bash .governance/run.sh     # ✓ governance: all 18 directive(s) passed (was 21; consumed-tree-integrity still ✓)
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-1e57cae2837-1781359556-1 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | interrupt | structural |  | refactor(governance): move kit-authoring checks from dogfood directives to test… | 1 | 2026-06-12T18:47:42.558Z |
| steer-1e57cae2837-1781359556-2 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | Banner alignment fix failed; alignment still disturbed in user's renderer | refactor(governance): move kit-authoring checks from dogfood directives to test… | 2 | 2026-06-13T06:06:22.822Z |
| steer-1e57cae2837-1781359556-3 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | README still too rule-first/vague; wants context ramp-up before rules | refactor(governance): move kit-authoring checks from dogfood directives to test… | 3 | 2026-06-13T07:51:19.473Z |
| steer-1e57cae2837-1781359556-4 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | Asked to step back and re-review the code before proceeding | refactor(governance): move kit-authoring checks from dogfood directives to test… | 4 | 2026-06-13T10:36:42.074Z |
| steer-1e57cae2837-1781359556-5 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | Touched .governance folder which should only change during kit upgrades | refactor(governance): move kit-authoring checks from dogfood directives to test… | 5 | 2026-06-13T12:35:30.794Z |
| steer-1e57cae2837-1781359556-6 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | Rejects the two-lane (lane 1/lane 2) integrity design; wants simpler approach | refactor(governance): move kit-authoring checks from dogfood directives to test… | 6 | 2026-06-13T12:53:23.805Z |
| steer-1e57cae2837-1781359556-7 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | interrupt | structural |  | refactor(governance): move kit-authoring checks from dogfood directives to test… | 7 | 2026-06-13T13:00:39.202Z |
| steer-1e57cae2837-1781359556-8 | 1e57cae2-8379-4355-a13d-9864aea0247b | #251 | correction | classifier | Steers design: directive belongs in packs so .governance is edited only via kit update | refactor(governance): move kit-authoring checks from dogfood directives to test… | 8 | 2026-06-13T13:01:32.834Z |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-be0615d9-5b5-1781359557-1 | claude-code | be0615d9-5b5e-462b-a27a-697dc6f3eb84 | #251 | claude-opus-4-8 | 5526 | 30430 | 32006 | 2442 | 38398 | 0.2949 | 5526 | 30430 | 32006 | 2442 | refactor(governance): move kit-authoring checks from dogfood directives to test  |
